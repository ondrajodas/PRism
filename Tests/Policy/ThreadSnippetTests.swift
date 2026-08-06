import Foundation
import Testing

@testable import PRism

/// Úryvek kódu k vláknu (#158) — `diffHunk` z GitHubu na řádky, které umí nakreslit diff.
///
/// Čistá funkce, takže vyčerpávajícím výčtem a bez mockování. Kde to jde, proti **skutečné**
/// odpovědi (`conversation-diff-hunks.json`): tvrzení „poslední řádek hunku je ten komentovaný“
/// je o datech GitHubu, ne o našem kódu, takže vymyšlený hunk by ho nedoložil.
@Suite("Úryvek kódu k vláknu")
struct ThreadSnippetTests {
    private func threads() throws -> [ReviewThread] {
        let text = try Fixture.text("gh/conversation-diff-hunks.json")
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(text.utf8)
        )
        let conversation = try response.conversation(
            id: PRIdentifier(repo: RepoID("cli/cli")!, number: 13084)
        )
        return conversation.threads.items
    }

    private func thread(
        hunk: String?,
        path: String = "Cart.php",
        line: Int? = nil,
        originalLine: Int? = nil,
        side: DiffSide? = .right
    ) -> ReviewThread {
        ReviewThread(
            id: "t1",
            path: path,
            line: line,
            originalLine: originalLine,
            side: side,
            isResolved: false,
            isOutdated: line == nil,
            diffHunk: hunk,
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    // MARK: - Skutečná data

    @Test("Hunk se přečte u každého vlákna ve fixture")
    func readsTheHunkOfEveryThread() throws {
        let threads = try threads()

        #expect(threads.count == 3)
        #expect(threads.allSatisfy { $0.diffHunk?.isEmpty == false })
        #expect(threads.allSatisfy { Policy.snippet(of: $0) != nil })
    }

    /// To hlavní tvrzení o datech: GitHub posílá hunk **po komentovaný řádek**, takže kontext
    /// je před ním. Kdyby to tak nebylo, ukazoval by úryvek konec kódu, který s komentářem
    /// nesouvisí — a nikdo by to nepoznal, protože vypadá stejně věrohodně.
    ///
    /// Číslo se bere podle `side`, stejně jako u kotvení bublin: u `right` nové, u `left` staré.
    @Test("Poslední řádek úryvku je ten komentovaný")
    func endsOnTheCommentedLine() throws {
        for thread in try threads() {
            let snippet = try #require(Policy.snippet(of: thread))
            let last = try #require(snippet.lines.last)
            let number = thread.side == .left ? last.oldNumber : last.newNumber

            #expect(number == thread.originalLine, "vlákno \(thread.id) na \(thread.path)")
        }
    }

    /// Zastaralé vlákno je to, kvůli kterému úryvek existuje: v diffu se nekreslí, takže
    /// `Přehled` je jediné místo, kde se ten kód dá ukázat.
    @Test("Zastaralé vlákno úryvek má")
    func keepsTheSnippetOfAnOutdatedThread() throws {
        let outdated = try threads().filter(\.isOutdated)

        #expect(outdated.count == 2)
        #expect(outdated.allSatisfy { Policy.snippet(of: $0) != nil })
        #expect(outdated.allSatisfy { $0.line == nil })
    }

    /// Ze 106 a 129 řádků se ukáže šest a **je to poznat**. Fixture má schválně i vlákno
    /// s krátkým hunkem, u kterého se zkrácení hlásit nesmí — jinak by test prošel i s příznakem
    /// zadrátovaným na `true`.
    @Test("Dlouhý hunk se zkrátí a hlásí to, krátký ne")
    func truncatesOnlyWhatItMustTruncate() throws {
        let threads = try threads()
        let snippets = try threads.map { try #require(Policy.snippet(of: $0)) }

        let short = snippets[0]
        #expect(short.lines.count == 2)
        #expect(!short.isTruncated)

        for long in snippets.dropFirst() {
            #expect(long.lines.count == Policy.threadSnippetContext + 1)
            #expect(long.isTruncated)
        }
    }

    /// Řádky si nesou druh, jinak by se úryvek vykreslil jednobarevně — a obarvení je to,
    /// kvůli čemu se kreslí `DiffLineView` a ne obyčejný text.
    @Test("Úryvek si drží druhy řádků")
    func keepsTheKindOfEachLine() throws {
        let threads = try threads()
        let kinds = try threads.flatMap { try #require(Policy.snippet(of: $0)).lines.map(\.kind) }

        #expect(kinds.contains(.added))
        #expect(kinds.contains(.context))
    }

    // MARK: - Proč syntetická hlavička

    /// Doklad k tomu, proč se hunk obaluje: `DiffParser` zařazuje řádky podle stavu a před
    /// první hlavičkou souboru nemá řádek kam patřit. Samotný `@@` blok tedy celý spadne do
    /// `unrecognizedLines` — a bez hlavičky by úryvek nebyl prázdný omylem, ale vždycky.
    @Test("Samotný hunk parser nezařadí")
    func provesTheHeaderIsNeeded() {
        let hunk = """
            @@ -1,2 +1,2 @@
             kontext
            +přidané
            """
        let diff = DiffParser.parse(hunk)

        #expect(diff.files.isEmpty)
        #expect(diff.unrecognizedLines == 3)
    }

    /// Cesta se do syntetické hlavičky píše, jak přišla — bez uvozovek a bez escapování.
    /// Mezera v ní tedy hlavičku rozdělí jinak, než `git` zamýšlel, a tenhle test hlídá, že
    /// to úryvku nevadí: cesty z hlavičky nikdo nečte, potřeba je jen to, že soubor začal.
    @Test("Cesta s mezerou úryvek nepoloží")
    func survivesAPathWithASpace() throws {
        let snippet = try #require(Policy.snippet(of: thread(
            hunk: "@@ -1,1 +1,1 @@\n+dva slova",
            path: "src/My Class.php",
            originalLine: 1
        )))

        #expect(snippet.lines.count == 1)
        #expect(!snippet.isTruncated)
    }

    // MARK: - Levá strana

    /// Ve vzorku jsou všechna vlákna `RIGHT` (jako u #63), takže se komentář k **odebranému**
    /// řádku ze skutečné odpovědi nesehnal — proto ručně sestavený hunk. Číslo se u něj musí
    /// brát ze **starého** souboru; kdyby se bralo nové, ukazoval by úryvek jiný řádek.
    @Test("U levé strany končí úryvek na starém čísle")
    func endsOnTheOldNumberOnTheLeft() throws {
        let snippet = try #require(Policy.snippet(of: thread(
            hunk: "@@ -40,2 +40,1 @@\n kontext\n-smazané",
            line: nil,
            originalLine: 41,
            side: .left
        )))
        let last = try #require(snippet.lines.last)

        #expect(last.kind == .removed)
        #expect(last.oldNumber == 41)
        #expect(last.newNumber == nil)
    }

    // MARK: - Kolik řádků

    @Test("Kontext se dá zúžit až na samotný komentovaný řádek")
    func honoursTheContextSize() throws {
        let hunk = "@@ -1,6 +1,6 @@\n a\n b\n c\n d\n e\n f"

        let single = try #require(Policy.snippet(of: thread(hunk: hunk, originalLine: 6), context: 0))
        #expect(single.lines.count == 1)
        #expect(single.lines.last?.text == "f")
        #expect(single.isTruncated)

        let all = try #require(Policy.snippet(of: thread(hunk: hunk, originalLine: 6), context: 5))
        #expect(all.lines.count == 6)
        #expect(!all.isTruncated)
    }

    /// Delší kontext, než je hunk, nesmí hlásit zkrácení ani spadnout na výřezu.
    @Test("Kratší hunk než kontext projde celý")
    func takesAShortHunkWhole() throws {
        let snippet = try #require(Policy.snippet(of: thread(
            hunk: "@@ -1,2 +1,2 @@\n a\n b",
            originalLine: 2
        )))

        #expect(snippet.lines.count == 2)
        #expect(!snippet.isTruncated)
    }

    // MARK: - Když se úryvek vzít nedá

    /// Starší fixtures `diffHunk` nemají, protože vznikly dřív, než se do dotazu přidal.
    /// Vlákno se musí vykreslit **jako dřív**, ne prázdné: `nil` znamená „nevíme“, kdežto
    /// prázdný úryvek by tvrdil, že kontext žádný není.
    @Test("Vlákno bez hunku úryvek nemá")
    func hasNoSnippetWithoutAHunk() {
        #expect(Policy.snippet(of: thread(hunk: nil)) == nil)
        #expect(Policy.snippet(of: thread(hunk: "")) == nil)
    }

    /// Starší fixtures projdou celé — je to tatáž kontrola jako u chybějících práv (#73).
    @Test(
        "Odpověď bez diffHunku vlákna nepoloží",
        arguments: [("conversation-small.json", 11451), ("conversation-threads.json", 13084)]
    )
    func survivesAResponseWithoutHunks(fixture: String, number: Int) throws {
        let text = try Fixture.text("gh/\(fixture)")
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(text.utf8)
        )
        let conversation = try response.conversation(
            id: PRIdentifier(repo: RepoID("cli/cli")!, number: number)
        )

        #expect(!conversation.threads.items.isEmpty)
        #expect(conversation.threads.items.allSatisfy { $0.diffHunk == nil })
        #expect(conversation.threads.items.allSatisfy { Policy.snippet(of: $0) == nil })
    }

    /// Text, který hunk není, nesmí dát prázdný rámeček ani spadnout.
    @Test("Text bez hlavičky hunku úryvek nedá")
    func refusesTextThatIsNotAHunk() {
        #expect(Policy.snippet(of: thread(hunk: "tohle není diff")) == nil)
        #expect(Policy.snippet(of: thread(hunk: "@@ rozbitá hlavička @@\n a")) == nil)
    }
}
