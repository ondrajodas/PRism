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

        #expect(ClaudeCommand.prompt(for: request) == Policy.reviewPrompt(
            template: ReviewPromptTemplate.standard,
            skillID: "code-review",
            baseSha: "bbbb2222",
            // Požadavek bez zadání (#120) — o souboru se v promptu nemluví.
            intent: nil,
            // A bez přírůstku (#517) — o rozsahu taky ne.
            increment: nil
        ))
    }

    /// Kontrola nálezů **šablonu z nastavení nebere** (#281) a je to schválně: její odpověď
    /// nenese nástroj, ale parser o pár řádků níž, takže by editovatelný prompt rozbil čtení,
    /// ne jen výsledek. Požadavek kontroly proto šablonu ani nemá kam uložit.
    @Test("Kontrola nálezů šablonu z nastavení nebere")
    func theRecheckIgnoresTheConfiguredTemplate() {
        let request = ReviewRequest.recheck(
            of: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 7),
            at: "new3333",
            worktree: URL(filePath: "/tmp/strom"),
            baseSha: "bbbb2222",
            material: material
        )

        // Šablonu si požadavek kontroly nenese vůbec — není kam ji propašovat.
        #expect(request.promptTemplate.isEmpty)
        // A prompt kontroly z ní nevzniká: nemá v sobě nic z psané půlky review.
        #expect(!ClaudeCommand.prompt(for: request).contains("First call the Skill tool"))
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

    // MARK: - Moje odeslané komentáře (#522)

    private let comments = [
        SentComment(
            threadID: "PRRT_1",
            path: "Cart.swift",
            line: 21,
            body: "Co se stane, když je množství nula?"
        ),
        SentComment(
            threadID: "PRRT_2",
            path: "Cart.php",
            line: nil,
            body: "Tohle by mělo být za konstantou."
        ),
    ]

    private var withComments: RecheckMaterial {
        RecheckMaterial(headSha: "old1111", findings: material.findings, comments: comments)
    }

    /// **Bez komentářů se prompt nezměnil ani o písmeno.** Je to podmínka, ne estetika: kontrola
    /// z #150 běží dál na PR, kde jsem nic neodeslal, a jiná formulace by u ní znamenala jinou
    /// přísnost, aniž by se o to kdokoli řekl.
    @Test("Bez komentářů zůstává prompt kontroly beze změny")
    func withoutCommentsThePromptIsUnchanged() {
        let prompt = RecheckCommand.prompt(for: material, baseSha: "base2222")

        #expect(prompt.contains("For every finding decide whether the new commits resolved it."))
        #expect(prompt.contains("the listed findings and nothing else"))
        #expect(prompt.contains("one object per finding"))
        #expect(!prompt.contains("My comments"))
        #expect(!prompt.contains("one object per item"))
    }

    /// Komentáře jdou do promptu **za nálezy a se `id`, které na ně navazuje** — jedno pole
    /// odpovědí, takže druhá řada indexů od nuly by znamenala verdikt o komentáři přiřazený
    /// nálezu s týmž číslem.
    @Test("Komentáře mají id navazující na nálezy")
    func commentIDsContinueAfterTheFindings() {
        let prompt = RecheckCommand.prompt(for: withComments, baseSha: "base2222")

        #expect(withComments.commentIDOffset == 2)
        #expect(withComments.questionCount == 4)
        #expect(prompt.contains("My comments"))
        #expect(prompt.contains(#""id":2"#))
        #expect(prompt.contains(#""id":3"#))
        #expect(prompt.contains("Co se stane, když je množství nula?"))
        #expect(prompt.contains(#""file":"Cart.swift""#))
        #expect(prompt.contains(#""line":21"#))
    }

    /// **Hranice, kterou model nesmí přejít**: o tom, jestli mi někdo odpověděl, rozhodují data
    /// (#72). Prompt to říká výslovně — bez té věty je „someone replied, so it is handled“
    /// nejpřirozenější odpověď, kterou může dát.
    @Test("Prompt zakáže soudit, jestli někdo odpověděl")
    func thePromptForbidsJudgingReplies() {
        let prompt = RecheckCommand.prompt(for: withComments, baseSha: "base2222")

        #expect(prompt.contains("Do not judge whether anyone replied"))
        #expect(prompt.contains("decide whether the new commits addressed what it asks about"))
    }

    /// Tvar odpovědi zůstává **týž** — `parse` je jeden a čte jedno pole. Mění se jediné slovo,
    /// podstatné jméno položky, protože seznam už není jen z nálezů.
    @Test("Tvar odpovědi se s komentáři nemění")
    func theAnswerShapeStaysTheSame() {
        let prompt = RecheckCommand.prompt(for: withComments, baseSha: "base2222")

        #expect(prompt.contains("one object per item"))
        #expect(prompt.contains(#""status""#))
        #expect(prompt.contains("still-applies"))
        #expect(prompt.contains("unclear"))
        // Zákazy z #150 platí u obou podob beze změny.
        #expect(prompt.contains("do not call ReportFindings"))
        #expect(prompt.contains("no comments on GitHub"))
    }

    /// Identita vlákna se modelu **neposílá**: k odpovědi ji nepotřebuje (páruje se `id`)
    /// a byla by to adresa, na kterou se dá na GitHubu psát.
    @Test("Identita vlákna do promptu nejde")
    func theThreadIdentityStaysOutOfThePrompt() {
        let prompt = RecheckCommand.prompt(for: withComments, baseSha: "base2222")

        #expect(!prompt.contains("PRRT_1"))
        #expect(!prompt.contains("PRRT_2"))
    }

    @Test("Prompt s komentáři je pořád jeden řádek")
    func thePromptWithCommentsIsASingleLine() {
        let prompt = RecheckCommand.prompt(for: withComments, baseSha: "base2222")

        #expect(!prompt.contains("\n"))
        #expect(!prompt.contains("  "))
    }

    /// Kotva bez řádku (zastaralé vlákno, kterému zmizel i `originalLine`) klíč **vynechá**,
    /// místo aby poslala `null` — `null` by se v promptu četlo jako „řádek číslo nic“.
    @Test("Komentář bez řádku klíč vynechá")
    func aCommentWithoutALineOmitsTheKey() {
        let json = RecheckCommand.json(of: [comments[1]], startingAt: 0)

        #expect(json.contains(#""file":"Cart.php""#))
        #expect(!json.contains(#""line""#))
    }

    /// Přírůstkové review (#517) se ptá dál **jen na nálezy**, takže jeho tvar zůstává slovo od
    /// slova ten původní. Sdílený zdroj formátu se tím nerozešel.
    @Test("Formát pro nálezy zůstává týž jako do #522")
    func theFindingsOnlyFormatIsUnchanged() {
        #expect(RecheckCommand.verdictFormat == RecheckCommand.verdictFormat(of: "finding"))
        #expect(RecheckCommand.verdictFormat.contains("one object per finding"))
    }
}
