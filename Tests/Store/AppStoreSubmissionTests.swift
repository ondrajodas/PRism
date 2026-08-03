import Foundation
import Testing

@testable import PRism

/// Cesta od draftu k odeslání, jak ji skládá store. Proti **skutečnému** `ReviewDraftStore`
/// nad dočasnou složkou: po úspěšném odeslání má draft zmizet i z disku, a to fake ověřit
/// neumí.
///
/// Nic se tu neodesílá — `submission(for:)` publisher **nevyrábí**, jen ho umí složit až
/// v `send()`, a `send()` se odsud nevolá. Testy se proto dívají na to, jestli sheet vůbec
/// vznikne, a na úklid po úspěchu.
@Suite("AppStore — odeslání review")
@MainActor
struct AppStoreSubmissionTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    /// Sandboxové repo: `PublishScope` je součástí odpovědi na „dá se odeslat“, takže na
    /// `cli/cli` by nevznikl žádný sheet bez ohledu na obsah draftu.
    private let pr = PRIdentifier("ondrajodas/prism-review-sandbox#7")!

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func detail(headSha: String = "aaaa1111") -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: headSha,
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/ondrajodas/prism-review-sandbox/pull/7")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func summary(updatedAt: TimeInterval = 100) -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/ondrajodas/prism-review-sandbox/pull/7")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    private func conversation() -> Conversation {
        Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    private func gateway() -> FakeGitHubGateway {
        FakeGitHubGateway(
            always: .success([summary()]),
            detail: .success(detail()),
            conversations: [.success(conversation())]
        )
    }

    /// `gh` je jen cesta — publisher se z ní skládá až při odesílání, ke kterému tyhle testy
    /// nedojdou. `nil` by znamenalo „odsud se neposílá“ a sheet by nevznikl nikdy.
    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: layout),
            gh: URL(filePath: "/usr/bin/true")
        )
    }

    /// Detail je to, odkud se ví, proti kterému commitu se review píše — bez něj se draft
    /// ani nezakládá.
    private func prepared(_ gateway: FakeGitHubGateway) async -> AppStore {
        let store = store(gateway)
        await store.loadDetail(for: summary())
        return store
    }

    /// Zápis draftu běží v tasku, takže se na něj musí počkat točením.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    // MARK: - Kdy sheet vznikne

    @Test("Hotový draft dá odeslání se snímkem a s návrhem z nálezů")
    func buildsASubmission() async throws {
        let store = await prepared(gateway())
        store.setDraftBody("vypadá to dobře", for: pr)
        store.setDraftVerdict(.approve, for: pr)

        let submission = try #require(store.submission(for: summary()))

        #expect(store.draftSendBlock(for: pr) == nil)
        #expect(submission.draft.body == "vypadá to dobře")
        #expect(submission.draft.verdict == .approve)
        #expect(submission.draft.headSha == "aaaa1111")
        // Nálezy nejsou, takže není z čeho soudit — a to je vlastní odpověď, ne opatrné
        // „approve“.
        #expect(submission.suggestion == nil)
    }

    /// Sheet se nad zastaralým draftem **neotevře vůbec**. Zakázané tlačítko je první
    /// pojistka, tahle druhá — spoléhat na to, že si to pohlídá view, je o jedno místo
    /// k zapomenutí víc.
    @Test("Draft proti staršímu commitu odeslání nesloží")
    func refusesAStaleDraft() async {
        let gateway = gateway()
        let store = await prepared(gateway)
        store.setDraftBody("vypadá to dobře", for: pr)
        store.setDraftVerdict(.approve, for: pr)

        // Nový commit v PR — detail se načte znovu, protože se změnilo `updatedAt`.
        gateway.detailFromNowOn = .success(detail(headSha: "cccc3333"))
        await store.loadDetail(for: summary(updatedAt: 200))

        #expect(store.isDraftStale(for: pr))
        #expect(store.draftSendBlock(for: pr) == .stale(draft: "aaaa1111", head: "cccc3333"))
        #expect(store.submission(for: summary()) == nil)
    }

    @Test("Bez vybraného verdiktu odeslání nevznikne")
    func refusesADraftWithoutAVerdict() async {
        let store = await prepared(gateway())
        store.setDraftBody("vypadá to dobře", for: pr)

        #expect(store.draftSendBlock(for: pr) == .noVerdict)
        #expect(store.submission(for: summary()) == nil)
    }

    @Test("Bez rozdělaného review není co odesílat")
    func refusesWithoutADraft() async {
        let store = await prepared(gateway())

        #expect(store.draftSendBlock(for: pr) == .nothingToSend)
        #expect(store.submission(for: summary()) == nil)
    }

    /// „Načítá se“ a „nepovedlo se to“ jsou různé odpovědi: první se dořeší samo, druhá ne.
    /// Slíbit „hned to bude“ nad chybou, která sama nezmizí, je horší než mlčet — a proč se
    /// hlava nezná, ví jen store, ne `Policy`.
    @Test("Selhaný detail řekne důvod, načítající se slíbí, že to bude")
    func explainsWhyTheHeadIsUnknown() async throws {
        let drafts = ReviewDraftStore(layout: layout)
        let prepared = await prepared(gateway())
        prepared.setDraftVerdict(.approve, for: pr)
        await settle()

        // Draft z disku existuje, ale detail se nepovedl — psát se do něj dá, odeslat ne.
        let failing = AppStore(
            gateway: FakeGitHubGateway(
                always: .success([summary()]),
                detail: .failure(GitHubError.notAuthenticated)
            ),
            time: FakeTimeSource(),
            drafts: drafts,
            gh: URL(filePath: "/usr/bin/true")
        )
        await failing.loadStoredDrafts()

        // Bez pokusu o detail se jen čeká.
        #expect(failing.draftSendBlock(for: pr) == .headUnknown(detail: nil))

        await failing.loadDetail(for: summary())

        let block = try #require(failing.draftSendBlock(for: pr))
        guard case .headUnknown(let detail?) = block else {
            Issue.record("Čekal jsem neznámou hlavu s důvodem, přišlo \(block)")
            return
        }
        #expect(block.userDescription.contains(detail))
        #expect(!block.userDescription.contains("Zjišťuji"))
        #expect(failing.submission(for: summary()) == nil)
    }

    // MARK: - Úklid po úspěchu

    /// Draft se maže **až po potvrzené odpovědi** — a musí zmizet i z disku, jinak by se po
    /// restartu vrátilo review, které už na GitHubu leží.
    @Test("Po odeslání draft zmizí z paměti i z disku")
    func clearsTheDraftAfterSubmitting() async throws {
        let store = await prepared(gateway())
        store.setDraftBody("vypadá to dobře", for: pr)
        store.setDraftVerdict(.approve, for: pr)
        await settle()

        // Čte se **novým** storem nad tou samou složkou — tedy to, co by našel restart.
        #expect(try await ReviewDraftStore(layout: layout).load(for: pr) != nil)

        await store.draftWasSubmitted(for: summary())
        await settle()

        #expect(store.draft(for: pr) == nil)
        #expect(!store.hasDraft(pr))
        #expect(try await ReviewDraftStore(layout: layout).load(for: pr) == nil)
    }

    /// Od odeslání leží v konverzaci moje vlastní review. `updatedAt` se tím měnit nemusí,
    /// takže cache je potřeba zahodit ručně — jinak by se v tabu `Přehled` neobjevilo až do
    /// přepnutí PR.
    @Test("Po odeslání se konverzace načte znovu")
    func reloadsTheConversationAfterSubmitting() async throws {
        let gateway = gateway()
        let store = await prepared(gateway)
        store.setDraftVerdict(.approve, for: pr)
        await store.loadConversation(for: summary())

        #expect(gateway.conversationRequests.count == 1)

        await store.draftWasSubmitted(for: summary())

        #expect(gateway.conversationRequests.count == 2)
    }
}
