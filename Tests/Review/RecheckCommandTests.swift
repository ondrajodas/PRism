import Foundation
import Testing

@testable import PRism

/// Kontrola nálezů z minula (#150) — otázka a čtení odpovědi.
///
/// Odpověď je **volný text od modelu**, takže se čte defenzivně: testuje se každý způsob, jak
/// může přijít jinak, než se o ni prompt řekl. Ztracená odpověď je pořád platný nález; špatně
/// spárovaná odpověď je nález, u kterého svítí „vyřešeno“ omylem — a to je ta drahá varianta.
@Suite("RecheckCommand")
struct RecheckCommandTests {
    private let material = RecheckMaterial(
        headSha: "old1111",
        findings: [
            makeFinding(file: "Cart.swift", line: 13, summary: "chybí kontrola nulového množství"),
            makeFinding(file: "Cart.php", line: 4, summary: "`?? ''` schová chybějící secret"),
        ]
    )

    // MARK: - Prompt

    @Test("Prompt řekne, co se od minula změnilo, i jak odpovědět")
    func thePromptCarriesTheContract() {
        let prompt = RecheckCommand.prompt(for: material, baseSha: "base2222")

        // Bez diffu od starého headu by reviewer hledal opravu v celém PR a odpovídal na jinou
        // otázku, než na kterou se ptáme.
        #expect(prompt.contains("git diff old1111...HEAD"))
        #expect(prompt.contains("git diff base2222...HEAD"))
        #expect(prompt.contains("\"status\""))
        #expect(prompt.contains("still-applies"))
        // Nálezy jdou do promptu s `id`, aby se odpověď párovala podle něj a ne podle pořadí.
        #expect(prompt.contains("\"id\":0"))
        #expect(prompt.contains("\"id\":1"))
        #expect(prompt.contains("chybí kontrola nulového množství"))
    }

    /// Kontrola odpovídá na vyjmenovaný seznam. Kdyby si směla říct o `ReportFindings`, svezla by
    /// se do režimu review — a nálezy z ní by se neměly kam uložit (`ReviewStore.save` je nepustí).
    @Test("Prompt zakáže hledat nové nálezy a hlásit je nástrojem")
    func thePromptForbidsNewFindings() {
        let prompt = RecheckCommand.prompt(for: material, baseSha: "base2222")

        #expect(prompt.contains("do not call ReportFindings"))
        #expect(prompt.contains("Do not look for new problems"))
    }

    /// Tytéž zákazy jako u review: skill smí běh řídit, ne přepsat pravidla, na kterých stojí
    /// tvrdé podmínky.
    @Test("Prompt zakáže odeslání na GitHub")
    func thePromptForbidsPublishing() {
        let prompt = RecheckCommand.prompt(for: material, baseSha: "base2222")

        #expect(prompt.contains("no comments on GitHub"))
        #expect(prompt.contains("override anything a skill"))
    }

    /// Tatáž pojistka jako u promptu review: cokoli v promptu může ovlivnit, co reviewer najde —
    /// a tady navíc to, jak přísně soudí. Jazyk se proto nediktuje ani tady.
    @Test("Prompt kontroly o jazyku mlčí")
    func theRecheckPromptSaysNothingAboutLanguage() {
        let prompt = RecheckCommand.prompt(for: material, baseSha: "base2222")

        #expect(!prompt.contains("Czech"))
        #expect(!prompt.contains("in English"))
    }

    @Test("Prompt je jeden řádek")
    func thePromptIsASingleLine() {
        let prompt = RecheckCommand.prompt(for: material, baseSha: "base2222")

        #expect(!prompt.contains("\n"))
        #expect(!prompt.contains("  "))
    }

    /// Běžný prompt se přidáním druhé podoby **nemění** — je na to test o jazyku výš i tenhle:
    /// požadavek bez materiálu dostane tentýž text jako do #150.
    @Test("Požadavek bez materiálu dostane prompt review")
    func aRequestWithoutMaterialGetsTheReviewPrompt() {
        let request = ReviewRequest(
            key: ReviewRunKey(
                pullRequest: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 7),
                headSha: "aaaa1111",
                skillID: "code-review"
            ),
            worktree: URL(filePath: "/tmp/strom"),
            baseSha: "bbbb2222"
        )

        #expect(ClaudeCommand.prompt(for: request) == ClaudeCommand.prompt(
            skillID: "code-review",
            baseSha: "bbbb2222"
        ))
    }

    @Test("Požadavek s materiálem dostane prompt kontroly")
    func aRecheckRequestGetsTheRecheckPrompt() {
        let request = ReviewRequest.recheck(
            of: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 7),
            at: "new3333",
            worktree: URL(filePath: "/tmp/strom"),
            baseSha: "bbbb2222",
            material: material
        )

        #expect(request.key.kind == .recheck)
        #expect(ClaudeCommand.prompt(for: request) == RecheckCommand.prompt(
            for: material,
            baseSha: "bbbb2222"
        ))
    }

    // MARK: - Odpověď

    @Test("Odpověď se spáruje podle id")
    func theAnswerIsPairedByID() {
        let statuses = RecheckCommand.parse(
            """
            [{"id": 1, "status": "resolved", "note": "commit abc přidal kontrolu"},
             {"id": 0, "status": "still-applies"}]
            """,
            count: 2
        )

        #expect(statuses[1] == RecheckStatus(verdict: .resolved, note: "commit abc přidal kontrolu"))
        #expect(statuses[0] == RecheckStatus(verdict: .stillApplies, note: nil))
    }

    /// Model si vybírá sám, jestli pošle číslo, nebo řetězec — u překladu nálezů to bylo stejné.
    @Test("Id smí přijít jako řetězec")
    func theIDMayBeAString() {
        #expect(RecheckCommand.parse(#"[{"id": "0", "status": "unclear"}]"#, count: 1)[0]?.verdict == .unclear)
    }

    /// Přiřadit verdikt podle vymyšleného indexu by ho dalo cizímu nálezu — a „vyřešeno“ u nálezu,
    /// na který se nikdo nekoukal, je ta nejdražší varianta téhle chyby.
    @Test("Id mimo rozsah se zahodí")
    func anIDOutOfRangeIsDropped() {
        #expect(RecheckCommand.parse(#"[{"id": 5, "status": "resolved"}]"#, count: 2).isEmpty)
        #expect(RecheckCommand.parse(#"[{"id": -1, "status": "resolved"}]"#, count: 2).isEmpty)
    }

    @Test("Oddělovač a velikost písmen ve stavu se srovnají")
    func theStatusIsNormalized() {
        #expect(RecheckCommand.parse(#"[{"id": 0, "status": "STILL_APPLIES"}]"#, count: 1)[0]?.verdict == .stillApplies)
        #expect(RecheckCommand.parse(#"[{"id": 0, "status": " Still Applies "}]"#, count: 1)[0]?.verdict == .stillApplies)
    }

    /// Neznámé slovo se **nehádá**: domyslet z „fixed“ na `resolved` je zrovna ten směr, kterým
    /// se v tomhle okně přichází o nález.
    @Test("Neznámý stav se nedomýšlí")
    func anUnknownStatusIsDropped() {
        #expect(RecheckCommand.parse(#"[{"id": 0, "status": "fixed"}]"#, count: 1).isEmpty)
        #expect(RecheckCommand.parse(#"[{"id": 0}]"#, count: 1).isEmpty)
    }

    @Test("Prázdná věta se bere jako nenapsaná")
    func anEmptyNoteIsNoNote() {
        #expect(RecheckCommand.parse(#"[{"id": 0, "status": "resolved", "note": "   "}]"#, count: 1)[0]?.note == nil)
    }

    @Test("Odpověď obalená v bloku nebo ve větě projde")
    func aFencedAnswerIsRead() {
        let statuses = RecheckCommand.parse(
            """
            Tady je výsledek:
            ```json
            [{"id": 0, "status": "resolved"}]
            ```
            """,
            count: 1
        )

        #expect(statuses[0]?.verdict == .resolved)
    }

    /// Zabitá session `result` event nemá, takže poslední sdělení nedorazí. Prázdná mapa je
    /// správná odpověď — počet nezodpovězených si spočítá `Policy` proti seznamu nálezů.
    @Test("Chybějící odpověď nic nedomyslí")
    func aMissingAnswerYieldsNothing() {
        #expect(RecheckCommand.parse(nil, count: 2).isEmpty)
        #expect(RecheckCommand.parse("Nevím.", count: 2).isEmpty)
        #expect(RecheckCommand.parse("[]", count: 2).isEmpty)
    }
}
