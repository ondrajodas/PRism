import Foundation
import Testing

@testable import PRism

/// Parsování konverzace ze skutečných GraphQL odpovědí.
///
/// Fixtures jsou surové odpovědi z **veřejných** PR `cli/cli`, sebrané tím dotazem, který
/// posílá aplikace (`ConversationQuery.document`) — ne ručně upraveným. Kdyby se sbíraly
/// jinak, testovaly by tvar, který ve provozu nikdy nepřijde.
@Suite("GhConversation")
struct GhConversationTests {
    private let id = PRIdentifier(repo: RepoID("cli/cli")!, number: 11451)

    private func load(_ fixture: String, number: Int = 11451) throws -> Conversation {
        let text = try Fixture.text("gh/\(fixture)")
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(text.utf8)
        )
        return try response.conversation(id: PRIdentifier(repo: RepoID("cli/cli")!, number: number))
    }

    // MARK: - Celá odpověď

    @Test("Malý PR se přečte celý")
    func readsASmallPullRequest() throws {
        let conversation = try load("conversation-small.json")

        #expect(conversation.viewer == "ondrajodas")
        #expect(conversation.reviews.items.count == 4)
        #expect(conversation.reviews.total == 4)
        #expect(conversation.threads.items.count == 2)
        #expect(conversation.comments.items.count == 2)
        #expect(!conversation.isTruncated)
    }

    @Test("PR s osmatřiceti vlákny se přečte celý")
    func readsAPullRequestWithManyThreads() throws {
        let conversation = try load("conversation-threads.json", number: 13084)

        #expect(conversation.threads.items.count == 38)
        #expect(conversation.reviews.items.count == 2)
        #expect(conversation.comments.items.count == 4)
        #expect(!conversation.isTruncated)
    }

    /// Ze všech fixtures se musí přečíst **všechno**, co v nich je. Zahozená položka by
    /// znamenala komentář kolegy, který v okně není — a to se od „nikdo nic nenapsal“
    /// nepozná.
    @Test(
        "Nic se ze skutečné odpovědi nezahodí",
        arguments: [("conversation-small.json", 11451), ("conversation-threads.json", 13084)]
    )
    func dropsNothingFromRealResponses(fixture: String, number: Int) throws {
        let conversation = try load(fixture, number: number)

        #expect(conversation.reviews.missing == 0)
        #expect(conversation.threads.missing == 0)
        #expect(conversation.comments.missing == 0)
        for thread in conversation.threads.items {
            #expect(thread.comments.missing == 0)
        }
    }

    // MARK: - Vlákna

    @Test("Vyřešené vlákno si příznak drží")
    func keepsTheResolvedFlag() throws {
        let conversation = try load("conversation-small.json")
        let resolved = conversation.threads.items.filter(\.isResolved)

        #expect(resolved.count == 1)
        #expect(resolved.first?.path == "pkg/cmd/release/shared/fetch.go")
        #expect(resolved.first?.line == 168)
    }

    /// Ověřeno na živém API: ze 38 vláken bylo 24 `isOutdated` a `line == nil` právě u nich.
    /// Je to tvrzení o datech, ne o našem kódu — proto se testuje proti fixture.
    @Test("Zastaralé vlákno nemá aktuální řádek, ale původní ano")
    func losesTheLineButKeepsTheOriginal() throws {
        let conversation = try load("conversation-threads.json", number: 13084)
        let outdated = conversation.threads.items.filter(\.isOutdated)

        #expect(outdated.count == 24)
        #expect(outdated.allSatisfy { $0.line == nil })
        #expect(outdated.allSatisfy { $0.originalLine != nil })
        // A obráceně: neaktuální řádek nemá jen zastaralé vlákno.
        #expect(conversation.threads.items.filter { $0.line == nil }.count == 24)
    }

    @Test("Zastaralé vlákno se ukotví na původní řádek")
    func anchorsAnOutdatedThreadToItsOriginalLine() throws {
        let conversation = try load("conversation-threads.json", number: 13084)
        let outdated = try #require(conversation.threads.items.first { $0.isOutdated })

        #expect(outdated.anchorLine == outdated.originalLine)
        #expect(outdated.anchorLine != nil)
    }

    // MARK: - Úryvek kódu

    /// `diffHunk` je na komentáři, ale do modelu jde na **vlákno**: kotva je jedna a odpovědi
    /// ve vlákně nesou tentýž úryvek (změřeno na `cli/cli#13084` u všech 38 vláken). Co se
    /// z hunku ukáže, rozhoduje `Policy` — testuje to `ThreadSnippetTests`.
    @Test("Hunk se přečte z komentáře na vlákno")
    func liftsTheDiffHunkOntoTheThread() throws {
        let conversation = try load("conversation-diff-hunks.json", number: 13084)
        let threads = conversation.threads.items

        #expect(threads.count == 3)
        #expect(threads.allSatisfy { $0.diffHunk?.hasPrefix("@@") == true })
    }

    /// Kdyby GitHub hunk u prvního komentáře vynechal, vlákno by o kontext přišlo kvůli
    /// pořadí — proto se bere první, **který ho má**.
    @Test("Hunk se najde i u pozdější odpovědi ve vlákně")
    func findsTheHunkOnALaterComment() throws {
        let json = """
        {"data": {"viewer": {"login": "ondrajodas"},
          "repository": {"pullRequest": {"number": 1,
            "reviews": {"totalCount": 0, "nodes": []},
            "comments": {"totalCount": 0, "nodes": []},
            "reviewThreads": {"totalCount": 1, "nodes": [
              {"id": "PRRT_1", "path": "src/Cart.php", "line": null, "originalLine": 5,
               "diffSide": "RIGHT", "isResolved": false, "isOutdated": true,
               "comments": {"totalCount": 2, "nodes": [
                 {"id": "a", "body": "bez hunku", "createdAt": "2026-08-01T10:00:00Z",
                  "url": "https://github.com/o/r/pull/1#discussion_a",
                  "author": {"login": "kolega"}, "diffHunk": null},
                 {"id": "b", "body": "s hunkem", "createdAt": "2026-08-01T11:00:00Z",
                  "url": "https://github.com/o/r/pull/1#discussion_b",
                  "author": {"login": "kolega"}, "diffHunk": "@@ -5,1 +5,1 @@\\n+kód"}
               ]}}]}}}}}
        """
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(json.utf8)
        )
        let conversation = try response.conversation(
            id: PRIdentifier(repo: RepoID("ondrajodas/PRism")!, number: 1)
        )
        let thread = try #require(conversation.threads.items.first)

        #expect(thread.diffHunk == "@@ -5,1 +5,1 @@\n+kód")
    }

    @Test("Strana diffu se přečte")
    func readsTheDiffSide() throws {
        let conversation = try load("conversation-small.json")

        #expect(conversation.threads.items.allSatisfy { $0.side == .right })
    }

    // MARK: - Práva na vyřešení

    /// Skutečná odpověď z **cizího** repa: na `cli/cli` právo vyřešit vlákno nemám, takže
    /// `viewerCanResolve` je `false` u vyřešeného i nevyřešeného. Přesně proto se to pole
    /// tahá — bez něj by okno nabízelo tlačítko, které vždycky selže.
    @Test("Vlákno v cizím repu se vyřešit nedá a je to v datech")
    func readsMissingResolveRights() throws {
        let conversation = try load("conversation-thread-rights.json", number: 13084)

        let threads = conversation.threads.items
        let allowed = threads.filter { $0.canResolve || $0.canUnresolve }
        // A tedy ani přepnout — v obou stavech, protože ani jedno právo tam není.
        let togglable = threads.filter(\.canToggleResolution)
        // Obojí schválně: kdyby ve fixture byla jen vyřešená vlákna, test by neřekl nic
        // o tom, že se `canResolve` čte i u otevřeného.
        let resolved = threads.filter(\.isResolved)
        let open = threads.filter { !$0.isResolved }

        #expect(threads.count == 2)
        #expect(allowed.isEmpty)
        #expect(togglable.isEmpty)
        #expect(resolved.count == 1)
        #expect(open.count == 1)
    }

    /// Starší fixtures ta pole nemají, protože vznikly dřív, než se do dotazu přidala.
    /// Chybějící právo znamená **„smíš“** — tlačítko schované kvůli údaji, který nedorazil,
    /// vypadá jako rozbitá aplikace, kdežto odmítnutí od GitHubu má hlášku s návodem.
    @Test(
        "Odpověď bez polí o právech je bere jako povolení",
        arguments: [("conversation-small.json", 11451), ("conversation-threads.json", 13084)]
    )
    func treatsMissingRightsAsAllowed(fixture: String, number: Int) throws {
        let conversation = try load(fixture, number: number)

        let threads = conversation.threads.items
        let denied = threads.filter { !$0.canResolve || !$0.canUnresolve }
        let togglable = threads.filter(\.canToggleResolution)

        #expect(!threads.isEmpty)
        #expect(denied.isEmpty)
        #expect(togglable.count == threads.count)
    }

    /// Každé z těch dvou práv platí v jiném stavu vlákna, takže se nedají zaměnit: GitHub
    /// u vyřešeného vlákna posílá `canResolve: false` a `canUnresolve: true`. Kdyby okno
    /// koukalo pořád na to samé, nabízelo by `Znovu otevřít` podle práva k opačné akci.
    ///
    /// Na skutečné odpovědi se to nesehná — na cizím repu jsou obě `false` a na vlastním obě
    /// `true`, takže rozdíl se pozná až tady.
    @Test("Co jde přepnout, rozhoduje stav vlákna")
    func picksTheRightPermissionForTheState() throws {
        let resolved = try thread(isResolved: true, canResolve: false, canUnresolve: true)
        #expect(resolved.canToggleResolution)

        let open = try thread(isResolved: false, canResolve: false, canUnresolve: true)
        #expect(!open.canToggleResolution)
    }

    private func thread(
        isResolved: Bool,
        canResolve: Bool,
        canUnresolve: Bool
    ) throws -> ReviewThread {
        let json = """
        {"data": {"viewer": {"login": "ondrajodas"},
          "repository": {"pullRequest": {"number": 1,
            "reviews": {"totalCount": 0, "nodes": []},
            "comments": {"totalCount": 0, "nodes": []},
            "reviewThreads": {"totalCount": 1, "nodes": [
              {"id": "PRRT_1", "path": "src/Cart.php", "line": 5, "originalLine": 5,
               "diffSide": "RIGHT", "isResolved": \(isResolved), "isOutdated": false,
               "viewerCanResolve": \(canResolve), "viewerCanUnresolve": \(canUnresolve),
               "comments": {"totalCount": 0, "nodes": []}}]}}}}}
        """
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(json.utf8)
        )
        let conversation = try response.conversation(
            id: PRIdentifier(repo: RepoID("ondrajodas/PRism")!, number: 1)
        )
        return try #require(conversation.threads.items.first)
    }

    // MARK: - Odpovědi ve vláknech

    @Test("Odpověď ve vlákně ukazuje na svého předchůdce")
    func linksAReplyToItsParent() throws {
        let conversation = try load("conversation-small.json")
        let thread = try #require(conversation.threads.items.first { $0.comments.items.count > 1 })
        let comments = thread.comments.items

        #expect(comments.count == 2)
        #expect(comments[0].replyToID == nil)
        #expect(comments[1].replyToID != nil)
        // Odpovídá na první komentář vlákna, ne na cokoli.
        #expect(comments[1].replyToID == comments[0].id)
    }

    @Test("Vlákno o jednom komentáři odpověď nemá")
    func hasNoReplyInASingleCommentThread() throws {
        let conversation = try load("conversation-small.json")
        let single = try #require(conversation.threads.items.first { $0.comments.items.count == 1 })

        #expect(single.comments.items[0].replyToID == nil)
    }

    // MARK: - Review

    @Test("Stavy review se přečtou včetně schválení bez textu")
    func readsReviewStates() throws {
        let conversation = try load("conversation-small.json")
        let states = conversation.reviews.items.map(\.state)

        #expect(states.contains(.approved))
        #expect(states.contains(.changesRequested))
        #expect(states.contains(.commented))

        // Schválení bez prózy je běžné — z prázdného těla nesmí být „nic tu není“.
        let approved = try #require(conversation.reviews.items.first { $0.state == .approved })
        #expect(approved.body.isEmpty)
        #expect(approved.isVerdict)
        #expect(approved.submittedAt != nil)
    }

    @Test("Komentované review verdikt nenese")
    func doesNotTreatACommentAsAVerdict() throws {
        let conversation = try load("conversation-small.json")
        let commented = try #require(conversation.reviews.items.first { $0.state == .commented })

        #expect(!commented.isVerdict)
    }

    // MARK: - Zkrácení

    /// Useknutá data nesmí vypadat jako úplná. Fixture je tentýž PR jako výš, jen
    /// s `first: 1` — tedy 1 ze 38 vláken.
    @Test("Useknutá stránka je v datech vidět")
    func showsThatThePageWasTruncated() throws {
        let conversation = try load("conversation-truncated.json", number: 13084)

        #expect(conversation.isTruncated)
        #expect(conversation.threads.items.count == 1)
        #expect(conversation.threads.total == 38)
        #expect(conversation.threads.missing == 37)
        #expect(conversation.reviews.isTruncated)
        #expect(conversation.comments.isTruncated)
    }

    /// `isTruncated` je `or` dvou signálů. Na skutečných datech se **nerozcházejí** — a
    /// právě to je potřeba ověřit, protože kdyby se rozešly, `or` to schová a nikdo se
    /// nedozví, že jednomu z nich nerozumíme.
    @Test(
        "hasNextPage a počty říkají o zkrácení totéž",
        arguments: [
            ("conversation-small.json", 11451),
            ("conversation-threads.json", 13084),
            ("conversation-truncated.json", 13084),
        ]
    )
    func agreesWithHasNextPage(fixture: String, number: Int) throws {
        let conversation = try load(fixture, number: number)

        #expect(
            conversation.reviews.hasNextPage
                == (conversation.reviews.items.count < conversation.reviews.total)
        )
        #expect(
            conversation.threads.hasNextPage
                == (conversation.threads.items.count < conversation.threads.total)
        )
        #expect(
            conversation.comments.hasNextPage
                == (conversation.comments.items.count < conversation.comments.total)
        )
    }

    // MARK: - Rozbité odpovědi

    @Test("Chybějící pull request je chyba, ne prázdná konverzace")
    func treatsAMissingPullRequestAsAnError() throws {
        let json = #"{"data":{"viewer":{"login":"me"},"repository":{"pullRequest":null}}}"#
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(json.utf8)
        )

        #expect(throws: GitHubError.self) { try response.conversation(id: id) }
    }

    /// Tatáž kontrola, jakou má `GhPullRequestDetail`. Komentáře kolegů přilepené k cizímu
    /// PR by v okně vypadaly naprosto v pořádku, takže tichý rozchod je to nejhorší, co se
    /// tu může stát.
    @Test("Konverzace cizího PR je chyba")
    func rejectsAConversationForADifferentPullRequest() throws {
        let json = """
        {"data":{"viewer":{"login":"me"},"repository":{"pullRequest":{
          "number":999,
          "reviews":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":[]},
          "reviewThreads":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":[]},
          "comments":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":[]}
        }}}}
        """
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(json.utf8)
        )

        #expect(throws: GitHubError.self) { try response.conversation(id: id) }
    }

    @Test("Chybějící repozitář je chyba")
    func treatsAMissingRepositoryAsAnError() throws {
        let json = #"{"data":{"viewer":{"login":"me"},"repository":null}}"#
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(json.utf8)
        )

        #expect(throws: GitHubError.self) { try response.conversation(id: id) }
    }

    /// PR bez konverzace je normální stav, ne rozbitá odpověď — chybějící `nodes` se proto
    /// bere jako prázdný seznam.
    @Test("PR bez konverzace projde jako prázdný")
    func readsAnEmptyConversation() throws {
        let json = """
        {"data":{"viewer":{"login":"me"},"repository":{"pullRequest":{
          "number":11451,
          "reviews":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":[]},
          "reviewThreads":{"totalCount":0,"pageInfo":{"hasNextPage":false}},
          "comments":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":null}
        }}}}
        """
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(json.utf8)
        )
        let conversation = try response.conversation(id: id)

        #expect(conversation.reviews.items.isEmpty)
        #expect(conversation.threads.items.isEmpty)
        #expect(conversation.comments.items.isEmpty)
        #expect(!conversation.isTruncated)
    }

    /// Smazaný účet vrací `author: null`. Komentář „od nikoho“ se zahodí, ale **musí být
    /// vidět, že chybí** — jinak je ztracený komentář k nerozeznání od nenapsaného.
    @Test("Komentář bez autora se zahodí a je to vidět")
    func dropsAnAuthorlessCommentVisibly() throws {
        let json = """
        {"data":{"viewer":{"login":"me"},"repository":{"pullRequest":{
          "number":11451,
          "reviews":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":[]},
          "reviewThreads":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":[]},
          "comments":{"totalCount":2,"pageInfo":{"hasNextPage":false},"nodes":[
            {"id":"a","body":"mám autora","createdAt":"2026-08-01T10:00:00Z",
             "url":"https://github.com/cli/cli/pull/1#issuecomment-1","author":{"login":"kdosi"}},
            {"id":"b","body":"smazaný účet","createdAt":"2026-08-01T11:00:00Z",
             "url":"https://github.com/cli/cli/pull/1#issuecomment-2","author":null}
          ]}
        }}}}
        """
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(json.utf8)
        )
        let conversation = try response.conversation(id: id)

        #expect(conversation.comments.items.count == 1)
        #expect(conversation.comments.total == 2)
        #expect(conversation.comments.missing == 1)
        #expect(conversation.isTruncated)
    }

    /// Neznámý stav review nesmí položit celou konverzaci — na rozdíl od stavu PR, ze
    /// kterého plyne chování.
    @Test("Neznámý stav review konverzaci nepoloží")
    func survivesAnUnknownReviewState() throws {
        let json = """
        {"data":{"viewer":{"login":"me"},"repository":{"pullRequest":{
          "number":11451,
          "reviews":{"totalCount":1,"pageInfo":{"hasNextPage":false},"nodes":[
            {"id":"r","state":"TELEPORTED","body":"co to je","submittedAt":null,
             "author":{"login":"kdosi"}}
          ]},
          "reviewThreads":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":[]},
          "comments":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":[]}
        }}}}
        """
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(json.utf8)
        )
        let conversation = try response.conversation(id: id)

        #expect(conversation.reviews.items.count == 1)
        #expect(conversation.reviews.items[0].state == nil)
        #expect(!conversation.reviews.items[0].isVerdict)
        #expect(conversation.reviews.missing == 0)
    }

    // MARK: - Moje vs. cizí

    @Test("Svoje komentáře pozná podle přihlášeného uživatele")
    func recognisesMyOwnComments() throws {
        let mine = ThreadComment(
            id: "a",
            author: "ondrajodas",
            body: "moje",
            createdAt: .now,
            url: URL(string: "https://github.com")!
        )
        let theirs = ThreadComment(
            id: "b",
            author: "kdosi",
            body: "cizí",
            createdAt: .now,
            url: URL(string: "https://github.com")!
        )
        let conversation = Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: [mine, theirs], total: 2, hasNextPage: false)
        )

        #expect(conversation.isMine(mine))
        #expect(!conversation.isMine(theirs))
    }
}

