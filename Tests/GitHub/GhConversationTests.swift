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

    @Test("Strana diffu se přečte")
    func readsTheDiffSide() throws {
        let conversation = try load("conversation-small.json")

        #expect(conversation.threads.items.allSatisfy { $0.side == .right })
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

