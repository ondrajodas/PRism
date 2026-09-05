import Foundation
import Testing

@testable import PRism

/// Návrh změny kódu (#528) — složení bloku z výběru, jeho přečtení zpátky a to, co se **nestalo**.
///
/// Čisté funkce, nic se nemockuje. Nejcennější tvrzení téhle sady jsou ta záporná: že návrh sám
/// nic neodesílá, že nevznikla nová metoda protokolu (tvrdá podmínka č. 1) a že se na cizím PR
/// tlačítko do zadání **nekreslí**. Ty se totiž rozbijí potichu.
@Suite("Policy — návrh změny kódu (#528)")
struct CodeSuggestionTests {
    // MARK: - Pomocníci

    /// Soubor se **dvěma** hunky (nové řádky 5–7 a 20–22), tentýž tvar jako v `DraftRangeTests`:
    /// mezi hunky je kód, který diff neukazuje — přesně to, co návrh přepsat nesmí.
    private func file() throws -> FileDiff {
        let diff = DiffParser.parse("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -5,3 +5,3 @@
             první kontext
            -staré páté
            +nové páté
             druhý kontext
            @@ -20,3 +20,3 @@
             třetí kontext
            -staré dvacáté
            +nové dvacáté
             čtvrtý kontext
            """)
        return try #require(diff.files.first)
    }

    private func anchor(_ line: Int, from start: Int? = nil, side: DiffSide = .right) -> DraftAnchor {
        DraftAnchor(
            line: line,
            side: side,
            start: start.map { DraftAnchor.Endpoint(line: $0, side: side) }
        )
    }

    private func thread(hunk: String?, bodies: [String] = ["Návrh:"], author: String = "odinuv") -> ReviewThread {
        let items = bodies.enumerated().map { index, body in
            ThreadComment(
                id: "c\(index)",
                author: author,
                body: body,
                createdAt: Date(timeIntervalSince1970: 100),
                url: URL(string: "https://github.com/ondrajodas/PRism/pull/1#discussion_r1")!
            )
        }
        return ReviewThread(
            id: "t1",
            path: "Cart.php",
            line: 41,
            originalLine: 41,
            side: .right,
            isResolved: false,
            isOutdated: false,
            diffHunk: hunk,
            comments: ConversationPage(items: items, total: items.count, hasNextPage: false)
        )
    }

    // MARK: - Skládání z výběru

    /// Jeden řádek: blok se předvyplní **jeho** textem. Zelená i červená strana jsou zatím totéž —
    /// návrh se přepisuje, ne píše.
    @Test("Jeden řádek se předvyplní svým textem")
    func offersASingleLine() throws {
        let offer = Policy.suggestionOffer(for: anchor(6), in: try file())

        let suggestion = try #require(offer.suggestion)
        #expect(suggestion.original == ["nové páté"])
        #expect(suggestion.replacement == ["nové páté"])
        #expect(suggestion.changesNothing)
    }

    /// Rozsah uvnitř jednoho hunku vezme řádky **v pořadí, jak stojí v souboru** — ne podle toho,
    /// kterým koncem se táhlo.
    @Test("Rozsah v jednom hunku vezme všechny své řádky v pořadí")
    func offersARangeInOrder() throws {
        let offer = Policy.suggestionOffer(for: anchor(7, from: 5), in: try file())

        #expect(try #require(offer.suggestion).original == ["první kontext", "nové páté", "druhý kontext"])
    }

    /// Odebraný řádek uvnitř rozsahu v nové verzi souboru není, takže ho návrh nemá čím nahradit —
    /// vypadne, jako to dělá GitHub. Kdyby zůstal, návrh by do souboru vrátil kód, který z něj
    /// tenhle PR odstranil.
    @Test("Odebraný řádek uvnitř rozsahu se do návrhu nedostane")
    func dropsRemovedLinesFromTheRange() throws {
        let offer = Policy.suggestionOffer(for: anchor(7, from: 5), in: try file())

        #expect(try #require(offer.suggestion).original.allSatisfy { !$0.hasPrefix("staré") })
    }

    /// **Hranice hunku je hranice návrhu.** Rozsah přes dva hunky GitHub u komentáře dovolí
    /// (změřeno u #110), jenže návrh nahrazuje **souvislý** kus souboru — a mezi hunky leží kód,
    /// který diff neukazuje.
    @Test("Rozsah přes dva hunky se zamítne, a věta říká proč")
    func refusesARangeAcrossHunks() throws {
        let offer = Policy.suggestionOffer(for: anchor(21, from: 6), in: try file())

        #expect(offer.suggestion == nil)
        let reason = try #require(offer.refusal)
        #expect(reason.contains("hunku"))
        #expect(reason.contains("diff neukazuje"))
    }

    /// Komentář na odebraném řádku je legitimní, návrh k němu ne: návrh se aplikuje na hlavu PR,
    /// kde ten řádek není.
    @Test("Kotva na staré straně se zamítne")
    func refusesTheOldSide() throws {
        let offer = Policy.suggestionOffer(for: anchor(6, side: .left), in: try file())

        #expect(try #require(offer.refusal).contains("nové verzi souboru"))
    }

    /// Konce rozsahu se posuzují **oba**: začátek ve staré verzi je tentýž problém jako konec.
    @Test("Rozsah, který začíná na staré straně, se zamítne taky")
    func refusesARangeStartingOnTheOldSide() throws {
        let mixed = DraftAnchor(
            line: 7,
            side: .right,
            start: DraftAnchor.Endpoint(line: 6, side: .left)
        )

        #expect(Policy.suggestionOffer(for: mixed, in: try file()).suggestion == nil)
    }

    /// Kotva mimo diff (rozbalený kontext #47, jiný soubor) nemá co předvyplnit.
    @Test("Kotva, která v diffu není, se zamítne")
    func refusesAnAnchorOutsideTheDiff() throws {
        let offer = Policy.suggestionOffer(for: anchor(999), in: try file())

        #expect(try #require(offer.refusal).contains("diff ukazuje"))
    }

    // MARK: - Podoba bloku

    @Test("Fence má jazyk suggestion a řádky mezi značkami")
    func buildsTheFence() {
        #expect(Policy.suggestionFence(replacing: ["a", "b"]) == "```suggestion\na\nb\n```")
    }

    /// Prázdný návrh je legitimní — GitHub ho bere jako „tenhle kus smaž“.
    @Test("Prázdný návrh je fence bez řádků")
    func buildsAnEmptyFence() {
        #expect(Policy.suggestionFence(replacing: []) == "```suggestion\n```")
    }

    @Test("Do prázdného komentáře se blok vloží sám")
    func insertsIntoAnEmptyBody() {
        #expect(Policy.blockInsertion(of: "BLOK", into: "   \n ") == "BLOK")
    }

    /// Prázdný řádek před fencem je podmínka, ne kosmetika: bez něj se odstavec nad ním slije
    /// s blokem.
    @Test("Za rozepsaný text se blok vloží po prázdném řádku")
    func insertsAfterABlankLine() {
        #expect(Policy.blockInsertion(of: "BLOK", into: "Fallback bych otočil:") == "Fallback bych otočil:\n\nBLOK")
        #expect(Policy.blockInsertion(of: "BLOK", into: "Text\n") == "Text\n\nBLOK")
    }

    // MARK: - Čtení zpátky

    @Test("Fence suggestion se pozná, obyčejný blok kódu ne")
    func recognizesOnlyTheSuggestionFence() {
        let body = """
            Takhle:

            ```suggestion
            return $row['value'] ?? throw new SecretNotFound($key);
            ```

            ```php
            echo 1;
            ```
            """

        let suggestions = Policy.suggestions(in: body)
        #expect(suggestions.count == 1)
        #expect(suggestions[0].replacement == ["return $row['value'] ?? throw new SecretNotFound($key);"])
        #expect(Policy.hasSuggestion(in: body))
    }

    /// Odcitovaný návrh se přijmout nedá — GitHub z něj tlačítko taky nedělá. Kdyby se kreslil
    /// jako mini diff, tvrdil by, že jde přijmout něco, co je jen ocitované.
    @Test("Návrh v citaci ani v details návrh není")
    func ignoresNestedFences() {
        let quoted = """
            > ```suggestion
            > return null;
            > ```
            """
        let hidden = """
            <details><summary>Ukázka</summary>

            ```suggestion
            return null;
            ```

            </details>
            """

        #expect(Policy.suggestions(in: quoted).isEmpty)
        #expect(Policy.suggestions(in: hidden).isEmpty)
        #expect(!Policy.hasSuggestion(in: quoted))
    }

    /// Těla komentářů z GitHubu mají `CRLF` (webová `textarea` je tak normalizuje). Kdyby se
    /// dělila `split(separator: "\n")`, byl by z celého bloku **jeden** řádek — a náhled by
    /// ukázal návrh, který nikdo nenapsal.
    @Test("CRLF v těle komentáře rozdělí návrh na řádky")
    func splitsSuggestionLinesOnCRLF() {
        let body = "Takhle:\r\n\r\n```suggestion\r\nprvní\r\ndruhý\r\n```\r\n"

        #expect(Policy.suggestions(in: body).first?.replacement == ["první", "druhý"])
    }

    @Test("Velikost písmen v jazyce fence nerozhoduje")
    func acceptsAnyCase() {
        #expect(Policy.hasSuggestion(in: "```SUGGESTION\na\n```"))
    }

    // MARK: - Co návrh ve vlákně nahrazuje

    /// `diffHunk` končí u komentovaného řádku (#158), takže poslední řádek je to, co návrh
    /// nahradí. Znaménko se strhává, hlavička hunku se nepočítá.
    @Test("Původní řádek se bere z konce diff hunku")
    func readsTheOriginalFromTheHunk() {
        let hunk = "@@ -38,4 +38,4 @@\n context\n-staré\n+        private readonly int $ttl = self::MAX_TTL,"

        #expect(Policy.suggestionOriginal(of: thread(hunk: hunk)) == ["        private readonly int $ttl = self::MAX_TTL,"])
    }

    /// **Prázdné znamená „nevíme“**, ne „nic tam není“: mini diff pak kreslí jen zelenou stranu.
    /// Vymyslet červený řádek by bylo tvrzení, které data neunesou.
    @Test("Bez diff hunku se původní řádek nevymýšlí")
    func admitsAnUnknownOriginal() {
        #expect(Policy.suggestionOriginal(of: thread(hunk: nil)).isEmpty)
        #expect(Policy.suggestionOriginal(of: thread(hunk: "@@ -1,1 +1,1 @@")).isEmpty)
    }

    @Test("CRLF v diff hunku se rozdělí správně")
    func readsTheOriginalFromACRLFHunk() {
        #expect(Policy.suggestionOriginal(of: thread(hunk: "@@ -1,2 +1,2 @@\r\n první\r\n+druhý")) == ["druhý"])
    }

    // MARK: - Popisek

    @Test("Popisek počítá nové řádky česky, mazání říká slovem")
    func labelsTheBlock() {
        #expect(Policy.suggestionLabel(of: CodeSuggestion(replacement: ["a"])) == "návrh · 1 řádek")
        #expect(Policy.suggestionLabel(of: CodeSuggestion(replacement: ["a", "b"])) == "návrh · 2 řádky")
        #expect(Policy.suggestionLabel(of: CodeSuggestion(replacement: Array(repeating: "a", count: 5))) == "návrh · 5 řádků")
        #expect(Policy.suggestionLabel(of: CodeSuggestion(original: ["a"], replacement: [])) == "návrh · smazat")
    }

    /// `TextEditor` s obsahem neroste, takže pole vysoké na dva řádky by z bloku ukázalo dva
    /// řádky — a přepisovat se v něm dá jedině naslepo. Vyšší pole se nasazuje **jen** tam, kde
    /// návrh je: u jednovětého komentáře by zabíralo místo diffu.
    @Test("Pole s návrhem je vyšší, bez návrhu zůstává jak bylo")
    func growsTheEditorForASuggestion() {
        #expect(Policy.draftEditorHeight(hasSuggestion: false) == 54)
        #expect(Policy.draftEditorHeight(hasSuggestion: true) > Policy.draftEditorHeight(hasSuggestion: false))
    }

    // MARK: - Zadání pro agenta

    /// Návrh je jediná položka zadání, u které je hotové znění — proto z ní vzniká **úkol**,
    /// a proto se pozná už z nadpisu.
    @Test("Vlákno s návrhem dostane v zadání úkol i značku")
    func turnsASuggestionIntoATask() throws {
        let item = AgentPromptItem.thread(thread(hunk: nil, bodies: ["TTL bych přebil:\n\n```suggestion\nnové\n```"]))

        let task = try #require(Policy.agentPromptSuggestionTask(of: thread(hunk: nil, bodies: ["```suggestion\nnové\n```"])))
        #expect(task.hasPrefix("Aplikuj návrh od odinuv na ř. 41"))
        #expect(Policy.agentPromptHeading(of: item, inFileSection: true).contains("návrh změny"))
        // Próza kolem návrhu zůstává: bývá v ní to, **proč** se návrh píše.
        #expect(Policy.agentPromptBody(of: item).contains { $0.contains("TTL bych přebil") })
    }

    @Test("Vlákno bez návrhu žádný úkol ani značku nedostane")
    func leavesOrdinaryThreadsAlone() {
        let item = AgentPromptItem.thread(thread(hunk: nil, bodies: ["Tohle bych přepsal."]))

        #expect(Policy.agentPromptSuggestionTask(of: thread(hunk: nil, bodies: ["Tohle bych přepsal."])) == nil)
        #expect(!Policy.agentPromptHeading(of: item, inFileSection: true).contains("návrh změny"))
    }

    // MARK: - Co se nestalo

    /// **Aplikovat návrh je zápis do repozitáře a schválně tu není.** Kdyby se to jméno v aplikaci
    /// objevilo, znamenalo by to desátou metodu protokolu, kterou tvrdá podmínka č. 1 nevyjmenovává.
    @Test("Aplikace neumí návrh aplikovat")
    func neverAppliesASuggestion() throws {
        for file in try sources() {
            #expect(!file.code.contains("applySuggestedChanges"), "\(file.path) sahá na aplikování návrhu")
        }
    }

    /// Nic z toho, co #528 přidalo, **neodesílá**: návrh je text komentáře a odchází s review
    /// toutéž cestou, jaká tu byla dřív. Grep na `ReviewPublishing` musí dál vydat sedm souborů
    /// z `App/Publish/` (hlídá `SingleWayOutTests`) — tady se hlídá druhá strana: že se do něj
    /// nový soubor nepřidal.
    @Test("Nové soubory #528 neznají ani protokol, ani gh")
    func keepsTheNewCodeAwayFromPublishing() throws {
        let added = [
            "Policy/CodeSuggestionPolicy.swift",
            "Models/CodeSuggestion.swift",
            "Views/SuggestionBlockView.swift",
            "Views/TextInsertionBox.swift",
        ]
        let sources = try sources()

        for path in added {
            let file = try #require(sources.first { $0.path == path }, "\(path) v App/ není")
            #expect(!file.condensed.contains("ReviewPublishing"))
            #expect(!file.condensed.contains("BranchPushing"))
            #expect(!file.condensed.contains("GhReviewPublisher"))
        }
    }

    /// **Na cizím PR se tlačítko nekreslí vůbec, ne zašedle.** Drží to dvě věci a obě jsou nad
    /// zdrojáky, protože store se odsud nespustí: brána u složení akcí a `if let` u kresby.
    /// Zašedlé tlačítko tvrdí „tady se to dělá, jen teď ne“ — a na cizím PR se to nedělá nikdy.
    @Test("Do zadání pro agenta je jen na vlastním PR")
    func offersTheHandoffOnlyOnOwnPullRequests() throws {
        let sources = try sources()
        let detail = try #require(sources.first { $0.path == "Views/PullRequestDetailView.swift" })
        let bubble = try #require(sources.first { $0.path == "Views/ThreadBubbleView.swift" })

        // Do `#expect` jde **`Bool`**, ne výraz nad `condensed`: framework by při pádu vypsal
        // celý zhuštěný soubor a hláška by měla desítky kilobajtů.
        let gated = detail.condensed.contains("handoff:store.isOwnPullRequest(pullRequest.id)")
        let drawn = bubble.condensed.contains("iflethandoff=actions.handoff")
        #expect(gated, "PullRequestDetailView předává handoff i na cizím PR")
        #expect(drawn, "ThreadBubbleView kreslí tlačítko i bez akce")
        // Výchozí hodnota je `nil`, takže bublina bez zapojeného storu (náhled, sonda) tlačítko
        // nemá — a nemá ho ani cizí PR, kde se `handoff` nepředá.
        #expect(ThreadActions().handoff == nil)
    }

    // MARK: - Zdrojáky

    private struct Source {
        let path: String
        let code: String
        /// Kód bez mezer — ve Swiftu je mezera uvnitř volání volná, takže stráž nad surovým
        /// textem by pustila `actions . handoff` (#490, sem u #550).
        let condensed: String
    }

    private static let appRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "App")

    /// Zdrojáky `App/` **bez komentářových řádků**: o aplikování návrhu se v dokumentačních
    /// komentářích mluví (a mluvit má), takže by se stráž chytla na vlastním vysvětlení.
    private func sources() throws -> [Source] {
        guard let walker = FileManager.default.enumerator(at: Self.appRoot, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(Self.appRoot.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let code = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            files.append(
                Source(
                    path: url.path.replacingOccurrences(of: Self.appRoot.path + "/", with: ""),
                    code: code,
                    condensed: code.filter { !$0.isWhitespace }
                )
            )
        }
        guard !files.isEmpty else { throw SourceError.unreadable(Self.appRoot.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }
}
