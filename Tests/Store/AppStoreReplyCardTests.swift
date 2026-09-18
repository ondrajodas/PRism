import Foundation
import Testing

@testable import PRism

/// Druhé kolo na obrazovce ze strany store (#523) — karta, předepsané schválení a hláška.
///
/// **Nejcennější tvrzení téhle sady jsou negativní**: klik na `Schválit` **nic neodesílá** (jen
/// předepíše draft a složí sheet) a na **vlastním PR se nehlásí nic**. Obojí se rozbije potichu —
/// první tak, že by se review odeslalo bez potvrzení, druhé tak, že by aplikace hlásila práci,
/// o kterou nikdo nežádal.
@Suite("AppStore — druhé kolo (#523)")
@MainActor
struct AppStoreReplyCardTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier("ondrajodas/prism-review-sandbox#7")!
    private let time = FakeTimeSource()

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    // MARK: - Data

    private func detail(headSha: String = "new22222") -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "sykora-ji",
            headSha: headSha,
            baseSha: "base0000",
            url: URL(string: "https://github.com/ondrajodas/prism-review-sandbox/pull/7")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func summary(author: String = "sykora-ji") -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/ondrajodas/prism-review-sandbox/pull/7")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func comment(_ id: String, by author: String, at offset: TimeInterval) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: author == "ondrajodas" ? "nonce z konstruktoru" : "necháme na AJDA-570",
            createdAt: Date(timeIntervalSince1970: 1_000_000 + offset),
            url: URL(string: "https://github.com/ondrajodas/prism-review-sandbox/pull/7#d-\(id)")!
        )
    }

    /// Vlákno, které jsem založil já. `answered` = kolega do něj odpověděl.
    private func thread(_ id: String, line: Int, answered: Bool = false) -> ReviewThread {
        var comments = [comment("\(id)-0", by: "ondrajodas", at: 0)]
        if answered { comments.append(comment("\(id)-1", by: "sykora-ji", at: 10)) }
        return ReviewThread(
            id: id,
            path: "src/Cart.swift",
            line: line,
            originalLine: line,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false)
        )
    }

    private func conversation(_ threads: [ReviewThread]) -> Conversation {
        Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(
                items: [SubmittedReview(
                    id: "rv",
                    author: "ondrajodas",
                    state: .changesRequested,
                    body: "",
                    submittedAt: Date(timeIntervalSince1970: 900_000)
                )],
                total: 1,
                hasNextPage: false
            ),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    private var publishing: Configuration {
        var configuration = Configuration.standard
        configuration.global.ownLogins = ["ondrajodas"]
        configuration.setRepository(RepositoryConfig(allowsPublishing: true), for: pr.repo)
        return configuration
    }

    private func store(
        threads: [ReviewThread],
        author: String = "sykora-ji",
        center: FakeNotificationCenter? = nil,
        reviewer: FakeReviewRunner = FakeReviewRunner(),
        reviews: ReviewStore
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(
                always: .success([summary(author: author)]),
                detail: .success(detail()),
                conversations: [.success(conversation(threads))]
            ),
            configuration: publishing,
            configStore: ConfigStore(layout: layout),
            time: time,
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: reviews,
            drafts: ReviewDraftStore(layout: layout),
            // `gh` je jen cesta — publisher se z ní skládá až v `send()`, ke kterému tyhle testy
            // schválně nedojdou.
            gh: URL(filePath: "/usr/bin/true"),
            notifications: center,
            activityLog: ActivityLog(layout: layout)
        )
    }

    /// Uložený záznam proti staršímu commitu — bez něj se kontrola nenabízí (brána zůstala
    /// u nálezů, #522).
    private func storedFindings(in reviews: ReviewStore) async throws {
        var stream = StreamSummary()
        stream.calledReportFindings = true
        stream.findings = [makeReported(file: "src/Cart.swift", line: 13, summary: "chybí kontrola")]
        try await reviews.save(ReviewRun(
            key: ReviewRunKey(pullRequest: pr, headSha: "old11111", skillID: "code-review"),
            summary: stream,
            outcome: .finished
        ))
    }

    private func prepared(_ store: AppStore) async {
        await store.loadStoredReviews()
        await store.refresh()
        await store.loadDetail(for: summary())
        await store.loadConversation(for: summary())
    }

    private func waitUntilIdle(_ store: AppStore) async {
        await waitUntil("kontrola nálezů doběhne") { !store.isRechecking(pr) }
    }

    // MARK: - Karta

    /// Karta se skládá **při čtení**, ze dvou zdrojů: uložených verdiktů a **živé** konverzace.
    /// Odpověď kolegy proto platí i bez dalšího běhu.
    @Test("Karta složí obě osy druhého kola")
    func theCardJoinsBothAxes() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        try await storedFindings(in: reviews)
        // Odpovědi kontroly: nález (id 0), pak moje dvě vlákna (id 1, 2).
        let reviewer = FakeReviewRunner(resultText: """
            [{"id": 0, "status": "resolved"},
             {"id": 1, "status": "resolved", "note": "commit to otočil na výjimku"},
             {"id": 2, "status": "still_applies"}]
            """)
        let store = store(
            threads: [thread("t1", line: 81), thread("t2", line: 60)],
            reviewer: reviewer,
            reviews: reviews
        )
        await prepared(store)

        store.startRecheck(for: pr)
        await waitUntilIdle(store)

        let card = try #require(store.replyCard(for: pr))
        #expect(card.title.hasPrefix("Odpověď na tvoje review z "))
        #expect(card.rows.map(\.mark) == [.fixed, .unanswered])
        #expect(card.rows.first?.place == "ř. 81")
        #expect(card.proposal == .comment(.unanswered(1)))
        #expect(card.openRemaining?.threadID == "t2")
        // Přes nezodpovězený bod se schválení nepředepisuje.
        #expect(card.approvalBody == nil)
        #expect(card.approveLabel == "Schválit i tak")
    }

    /// **Na vlastním PR se karta nekreslí** — a je to brána ve `Policy`, kterou store jen
    /// předává; schválení vlastního PR GitHub odmítne.
    @Test("Na vlastním PR karta není")
    func noCardOnMyOwnPullRequest() async {
        let reviews = ReviewStore(layout: layout, time: time)
        let store = store(threads: [thread("t1", line: 81)], author: "ondrajodas", reviews: reviews)
        await prepared(store)

        #expect(store.replyCard(for: pr) == nil)
    }

    // MARK: - Předepsané schválení

    /// **Nejcennější test sady: kliknutí na kartu nic neodešle.** Předepíše se draft (soubor
    /// v cache) a složí se sheet — odeslat smí dál jedině `ReviewPublishing` z potvrzení
    /// (tvrdá podmínka č. 1).
    @Test("Předepsané schválení nic neodešle, jen složí potvrzení")
    func prescribingApprovalSendsNothing() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        try await storedFindings(in: reviews)
        let reviewer = FakeReviewRunner(resultText: """
            [{"id": 0, "status": "resolved"}, {"id": 1, "status": "resolved"}]
            """)
        let store = store(threads: [thread("t1", line: 81)], reviewer: reviewer, reviews: reviews)
        await prepared(store)
        store.startRecheck(for: pr)
        await waitUntilIdle(store)

        #expect(store.draft(for: pr) == nil)
        store.prescribeReplyApproval(for: pr)

        // Zapsal se **draft**, ne odeslání: verdikt i předepsané tělo leží v cache.
        let draft = try #require(store.draft(for: pr))
        #expect(draft.verdict == .approve)
        #expect(draft.body == "Díky, opraveno.")
        // Sheet se **dá** otevřít — a to je celé, co klik udělá.
        #expect(store.submission(for: summary()) != nil)
        // A na GitHub se přitom nesáhlo ani čtením navíc: cesta ven vede jedině přes potvrzení.
        #expect(store.draftSendBlock(for: pr) == nil)
    }

    /// Rozepsaná věta má přednost: předpis ji nesmí přepsat, protože review se dá pustit znovu,
    /// kdežto moje próza ne.
    @Test("Předpis nepřepíše rozepsané tělo")
    func prescriptionKeepsMyText() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        try await storedFindings(in: reviews)
        let reviewer = FakeReviewRunner(resultText: """
            [{"id": 0, "status": "resolved"}, {"id": 1, "status": "resolved"}]
            """)
        let store = store(threads: [thread("t1", line: 81)], reviewer: reviewer, reviews: reviews)
        await prepared(store)
        store.startRecheck(for: pr)
        await waitUntilIdle(store)

        store.setDraftBody("ještě se mrknu na ten test", for: pr)
        store.prescribeReplyApproval(for: pr)

        #expect(store.draft(for: pr)?.body == "ještě se mrknu na ten test")
        #expect(store.draft(for: pr)?.verdict == .approve)
    }

    /// Bez karty se **nezapíše nic** — na vlastním PR by to byl draft za tlačítko, které tam
    /// není.
    @Test("Bez karty se draft nezaloží")
    func noCardMeansNoDraft() async {
        let reviews = ReviewStore(layout: layout, time: time)
        let store = store(threads: [thread("t1", line: 81)], author: "ondrajodas", reviews: reviews)
        await prepared(store)

        store.prescribeReplyApproval(for: pr)

        #expect(store.draft(for: pr) == nil)
    }

    // MARK: - Hláška

    /// Po kontrole na **cizím** PR s mým odeslaným review přijde banner i řádek v `Dění`.
    @Test("Po kontrole přijde hláška o druhém kole")
    func theRoundIsAnnounced() async throws {
        let center = FakeNotificationCenter()
        let reviews = ReviewStore(layout: layout, time: time)
        try await storedFindings(in: reviews)
        let reviewer = FakeReviewRunner(resultText: """
            [{"id": 0, "status": "resolved"},
             {"id": 1, "status": "resolved"},
             {"id": 2, "status": "still_applies"}]
            """)
        let store = store(
            threads: [thread("t1", line: 81), thread("t2", line: 60)],
            center: center,
            reviewer: reviewer,
            reviews: reviews
        )
        await prepared(store)

        store.startRecheck(for: pr)
        await waitUntilIdle(store)

        let delivered = try #require(center.delivered.first { $0.event == .replies })
        #expect(delivered.title == "sykora-ji opravil 1 z 2")
        #expect(delivered.body.hasPrefix("1 bez odpovědi\n"))
        #expect(store.activityEvents.contains { $0.kind == .replyRound })
    }

    /// **Na vlastním PR se nehlásí nic** — ani banner, ani řádek. Je to tatáž dvojitá kontrola
    /// jako u cizí aktivity: metodu volá i test a jedna zapomenutá podmínka by z toho udělala
    /// hlášky o vlastní práci.
    @Test("Na vlastním PR se nehlásí nic")
    func nothingIsAnnouncedOnMyOwnPullRequest() async {
        let center = FakeNotificationCenter()
        let reviews = ReviewStore(layout: layout, time: time)
        let store = store(
            threads: [thread("t1", line: 81, answered: true)],
            author: "ondrajodas",
            center: center,
            reviews: reviews
        )
        await prepared(store)

        await store.notifyAboutReplyRound(on: pr)

        // Filtruje se **na druh**, ne na prázdno: na vlastním PR chodí cizí aktivita (#335),
        // a ta je v pořádku. Vadila by tady jedině hláška o druhém kole.
        #expect(center.delivered.contains { $0.event == .replies } == false)
        #expect(store.activityEvents.contains { $0.kind == .replyRound } == false)
    }

    /// Vypnutý přepínač umlčí **banner, ne záznam** (#414): vyrušit ne, dohledat ano.
    @Test("Vypnutý přepínač nechá řádek v Dění")
    func aDisabledToggleStillLeavesTheRow() async throws {
        let center = FakeNotificationCenter()
        let reviews = ReviewStore(layout: layout, time: time)
        let store = store(
            threads: [thread("t1", line: 81, answered: true)],
            center: center,
            reviews: reviews
        )
        var configuration = publishing
        configuration.global.notifications.replies = false
        try await store.updateConfiguration(configuration)
        await prepared(store)

        await store.notifyAboutReplyRound(on: pr)

        #expect(center.delivered.isEmpty)
        let event = try #require(store.activityEvents.first { $0.kind == .replyRound })
        #expect(event.wasAnnounced == false)
        #expect(Policy.showsSilentChip(event.kind, announced: event.wasAnnounced))
    }

    // MARK: - Otevření zbývajícího vlákna

    /// `Otevřít zbývající` **přepne do `Konverzace` a vlákno rozbalí** — cíl, na kterém není co
    /// přečíst, je k nerozeznání od skoku, který se nepovedl.
    @Test("Otevření zbývajícího přepne tab a rozbalí vlákno")
    func openingTheRemainingThread() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        let store = store(threads: [thread("t1", line: 60)], reviews: reviews)
        await prepared(store)
        let thread = try #require(store.conversation(for: pr)?.threads.items.first)
        // Nevyřešené vlákno je rozbalené ve výchozím stavu — sbalíme ho, ať je co otevřít.
        store.toggleThread(thread, in: pr)
        #expect(store.isThreadExpanded(thread, in: pr) == false)

        store.revealReplyThread("t1", in: pr)

        #expect(store.detailTab(for: pr) == .conversation)
        #expect(store.isThreadExpanded(thread, in: pr))
    }
}
