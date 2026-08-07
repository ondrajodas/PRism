import Foundation
import Testing

@testable import PRism

/// Mapování časové osy z GraphQL odpovědi (#171).
///
/// Fixtures jsou surové odpovědi sebrané **tím dotazem, který posílá aplikace**
/// (`ConversationQuery.document`), z veřejných repozitářů:
///
/// - `conversation-timeline.json` — `ondrajodas/PRism#167`, tedy malý PR s **botem** jako
///   vyžádaným reviewerem. Na cizím repu se to nesehná: `copilot-pull-request-reviewer` si
///   vyžádá naše `bin/copilot-review.sh`.
/// - `conversation-force-push.json` — `cli/cli#13084` s `page=3`, tedy **force push** ze
///   skutečného provozu. Malá stránka schválně: celá odpověď je 280 kB kvůli hunkům a tvar
///   událostí je v prvních třech uzlech vidět celý. Nese navíc `hasNextPage: true`.
///
/// Co se ze skutečné odpovědi sehnat nedá, se testuje inline JSONem.
@Suite("GhTimeline")
struct GhTimelineTests {
    private func load(_ fixture: String, repo: String, number: Int) throws -> Conversation {
        let text = try Fixture.text("gh/\(fixture)")
        let response = try GhOutput.decoder.decode(GhConversationResponse.self, from: Data(text.utf8))
        return try response.conversation(id: PRIdentifier(repo: RepoID(repo)!, number: number))
    }

    private func conversation(fromInline json: String) throws -> Conversation {
        let response = try GhOutput.decoder.decode(GhConversationResponse.self, from: Data(json.utf8))
        return try response.conversation(id: PRIdentifier(repo: RepoID("cli/cli")!, number: 1))
    }

    /// Obal kolem událostí, ať inline JSON nemusí opisovat celou konverzaci.
    private func inlineTimeline(_ nodes: String, totalCount: Int = 1, hasNextPage: Bool = false) -> String {
        """
        {"data":{"viewer":{"login":"me"},"repository":{"pullRequest":{
          "number":1,
          "reviews":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":[]},
          "reviewThreads":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":[]},
          "comments":{"totalCount":0,"pageInfo":{"hasNextPage":false},"nodes":[]},
          "timelineItems":{"totalCount":\(totalCount),
            "pageInfo":{"hasNextPage":\(hasNextPage)},
            "nodes":[\(nodes)]}
        }}}}
        """
    }

    // MARK: - Skutečné odpovědi

    @Test("Události malého PR se přečtou celé")
    func readsTheEventsOfASmallPullRequest() throws {
        let conversation = try load("conversation-timeline.json", repo: "ondrajodas/PRism", number: 167)

        #expect(conversation.events.items.count == 5)
        #expect(conversation.events.items.filter { if case .commit = $0.kind { true } else { false } }.count == 2)
        #expect(conversation.events.items.contains { $0.kind == .closed })
        #expect(conversation.events.items.contains { $0.kind == .merged(into: "main") })
    }

    @Test("Commit nese sha, titulek i avatar autora")
    func readsACommit() throws {
        let conversation = try load("conversation-timeline.json", repo: "ondrajodas/PRism", number: 167)

        let commit = try #require(conversation.events.items.first { if case .commit = $0.kind { true } else { false } })
        guard case .commit(let oid, let headline) = commit.kind else { return }
        #expect(oid.count == 40, "sha se krátí až při zobrazení")
        #expect(!headline.isEmpty)
        #expect(commit.actor?.login == "ondrajodas")
        #expect(commit.actor?.avatarURL != nil)
        #expect(commit.at != nil)
    }

    /// Ten případ z prvního snímku v #171: review si vyžádal bot. Bez `__typename` u cíle by
    /// z něj vyšel obyčejný uživatel a v okně by chyběl odznak.
    @Test("Bot jako vyžádaný reviewer je poznat")
    func tellsABotReviewerApart() throws {
        let conversation = try load("conversation-timeline.json", repo: "ondrajodas/PRism", number: 167)

        let requested = try #require(conversation.events.items.first {
            if case .reviewRequested = $0.kind { true } else { false }
        })
        #expect(requested.kind == .reviewRequested(reviewer: "copilot-pull-request-reviewer"))
        #expect(requested.actor?.login == "ondrajodas")
        #expect(requested.actor?.isBot == false)
    }

    @Test("Force push nese commit před i po")
    func readsAForcePush() throws {
        let conversation = try load("conversation-force-push.json", repo: "cli/cli", number: 13084)

        let pushed = try #require(conversation.events.items.first {
            if case .forcePushed = $0.kind { true } else { false }
        })
        guard case .forcePushed(let before, let after) = pushed.kind else { return }
        #expect(before?.count == 40)
        #expect(after?.count == 40)
        #expect(pushed.actor?.login == "maxbeizer")
    }

    /// **Tenhle test drží celý bod o `totalCount`.** `timelineItems` s `itemTypes` vrací
    /// `totalCount` **bez filtru** — v téhle fixture 49 proti třem uzlům. Kdyby se z toho
    /// rozdílu počítalo „chybí“, hlásila by aplikace ztrátu 46 událostí, které nikdy
    /// neexistovaly.
    @Test("Nefiltrovaný totalCount nehlásí ztracené události")
    func ignoresTheUnfilteredTotalCount() throws {
        let conversation = try load("conversation-force-push.json", repo: "cli/cli", number: 13084)

        #expect(conversation.events.items.count == 3)
        #expect(conversation.events.missing == 0)
    }

    /// Zbývající signál ale platit musí: tahle fixture je sebraná s `page=3`, takže se
    /// časová osa **doopravdy** neveze celá.
    @Test("Další stránka událostí se hlásí jako zkrácení")
    func reportsTheNextPage() throws {
        let conversation = try load("conversation-force-push.json", repo: "cli/cli", number: 13084)

        #expect(conversation.events.isTruncated)
        #expect(conversation.isTruncated, "zkrácená osa musí být vidět i na celé konverzaci")
    }

    /// Fixtures z doby před #171 `timelineItems` nemají — a nesmí se kvůli tomu přestat
    /// dekódovat. Tatáž úvaha jako u chybějících práv vlákna nebo `diffHunk`u.
    @Test("Starší odpověď bez časové osy se přečte")
    func readsAResponseWithoutATimeline() throws {
        let conversation = try load("conversation-small.json", repo: "cli/cli", number: 11451)

        #expect(conversation.events.items.isEmpty)
        #expect(!conversation.isTruncated)
        #expect(conversation.reviews.items.count == 4, "zbytek konverzace se tím nesmí rozbít")
    }

    // MARK: - Syntetické odpovědi

    /// Změřeno na živém API: typ uvedený v `itemTypes` **bez fragmentu** dorazí jako
    /// `{"__typename": "ClosedEvent"}` a nic víc. Takový uzel se nesmí nakreslit jako
    /// prázdný řádek.
    @Test("Uzel, kterému nerozumíme, se nekreslí")
    func dropsAnUnknownNode() throws {
        let conversation = try conversation(fromInline: inlineTimeline("""
        {"__typename":"ClosedEvent"},
        {"__typename":"AutoMergeEnabledEvent","id":"X_1","createdAt":"2026-08-01T10:00:00Z"}
        """, totalCount: 2))

        #expect(conversation.events.items.isEmpty)
    }

    @Test("Převedení na draft, otevření znovu a změna base se přečtou")
    func readsTheRemainingKinds() throws {
        let conversation = try conversation(fromInline: inlineTimeline("""
        {"__typename":"ConvertToDraftEvent","id":"C_1","createdAt":"2026-08-01T10:00:00Z",
         "actor":{"__typename":"User","login":"ondrajodas","avatarUrl":null}},
        {"__typename":"ReopenedEvent","id":"R_1","createdAt":"2026-08-01T11:00:00Z",
         "actor":{"__typename":"User","login":"ondrajodas","avatarUrl":null}},
        {"__typename":"BaseRefChangedEvent","id":"B_1","createdAt":"2026-08-01T12:00:00Z",
         "actor":{"__typename":"User","login":"ondrajodas","avatarUrl":null},
         "previousRefName":"main","currentRefName":"develop"},
        {"__typename":"ReadyForReviewEvent","id":"D_1","createdAt":"2026-08-01T13:00:00Z",
         "actor":{"__typename":"User","login":"ondrajodas","avatarUrl":null}}
        """, totalCount: 4))

        #expect(conversation.events.items.map(\.kind) == [
            .convertedToDraft,
            .reopened,
            .baseChanged(from: "main", to: "develop"),
            .readyForReview,
        ])
    }

    /// Změřeno na `cli/cli#13084`: `requestedReviewer` umí přijít `null`. „Někdo si vyžádal
    /// review“ je pořád informace, takže se událost **nezahazuje**.
    @Test("Vyžádané review bez cíle zůstane")
    func keepsARequestWithoutAReviewer() throws {
        let conversation = try conversation(fromInline: inlineTimeline("""
        {"__typename":"ReviewRequestedEvent","id":"Q_1","createdAt":"2026-08-01T10:00:00Z",
         "actor":{"__typename":"User","login":"maxbeizer","avatarUrl":null},
         "requestedReviewer":null}
        """))

        #expect(conversation.events.items.map(\.kind) == [.reviewRequested(reviewer: nil)])
    }

    /// Tým se od uživatele liší tím, že má `name`, ne `login`.
    @Test("Vyžádané review od týmu nese jméno týmu")
    func readsATeamReviewer() throws {
        let conversation = try conversation(fromInline: inlineTimeline("""
        {"__typename":"ReviewRequestedEvent","id":"Q_2","createdAt":"2026-08-01T10:00:00Z",
         "actor":{"__typename":"User","login":"ondrajodas","avatarUrl":null},
         "requestedReviewer":{"__typename":"Team","name":"platform","avatarUrl":null}}
        """))

        #expect(conversation.events.items.map(\.kind) == [.reviewRequested(reviewer: "platform")])
    }

    /// Bot jako **aktér** — `github-actions requested a review from …` z prvního snímku #171.
    @Test("Bot jako aktér je poznat")
    func tellsABotActorApart() throws {
        let conversation = try conversation(fromInline: inlineTimeline("""
        {"__typename":"ReviewRequestedEvent","id":"Q_3","createdAt":"2026-08-01T10:00:00Z",
         "actor":{"__typename":"Bot","login":"github-actions","avatarUrl":null},
         "requestedReviewer":{"__typename":"User","login":"ondrajodas","avatarUrl":null}}
        """))

        let event = try #require(conversation.events.items.first)
        #expect(event.actor?.isBot == true)
    }

    /// Commit s e-mailem, který nesedí na účet: `user` je `null`, takže zbývá jméno
    /// z commitu a avatar není. Řádek bez autora z toho vyjít nesmí.
    @Test("Commit bez napojeného účtu má aspoň jméno z commitu")
    func fallsBackToTheCommitAuthorName() throws {
        let conversation = try conversation(fromInline: inlineTimeline("""
        {"__typename":"PullRequestCommit","id":"P_1",
         "commit":{"oid":"90449b51970c05fe07ed5270ee75578c3f8568d4",
           "messageHeadline":"fix: bez účtu","committedDate":"2026-08-01T10:00:00Z",
           "author":{"name":"Někdo Bez Účtu","user":null}}}
        """))

        let event = try #require(conversation.events.items.first)
        #expect(event.actor?.login == "Někdo Bez Účtu")
        #expect(event.actor?.avatarURL == nil)
        #expect(event.actor?.isBot == false)
    }

    /// Vyžádání review od sebe sama — to, co GitHub píše jako „self-requested a review“.
    @Test("Vyžádání review od sebe sama se pozná i po namapování")
    func mapsSelfRequestedReviews() throws {
        let conversation = try conversation(fromInline: inlineTimeline("""
        {"__typename":"ReviewRequestedEvent","id":"S_1","createdAt":"2026-08-01T10:00:00Z",
         "actor":{"__typename":"User","login":"ondrajodas","avatarUrl":null},
         "requestedReviewer":{"__typename":"User","login":"ondrajodas","avatarUrl":null}}
        """))

        let event = try #require(conversation.events.items.first)
        #expect(event.isSelfDirected)
    }
}
