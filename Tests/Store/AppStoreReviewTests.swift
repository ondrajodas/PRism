import Foundation
import Testing

@testable import PRism

/// Drát od tlačítka k nálezům. Fake gateway, fake checkout, fake reviewer — a **skutečný**
/// `ReviewStore` nad dočasnou složkou, protože právě on rozhoduje, co se objeví po restartu.
@Suite("AppStore — review")
@MainActor
struct AppStoreReviewTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private var detail: PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func gateway(detail: Result<PullRequest, any Error>? = nil) -> FakeGitHubGateway {
        FakeGitHubGateway(always: .success([]), detail: detail ?? .success(self.detail))
    }

    private func reviewStore() -> ReviewStore {
        ReviewStore(layout: layout, time: FakeTimeSource())
    }

    private func store(
        gateway: FakeGitHubGateway,
        reviewer: FakeReviewRunner = FakeReviewRunner(),
        checkout: FakeRepoCheckout = FakeRepoCheckout(),
        reviews: ReviewStore? = nil
    ) -> AppStore {
        AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            checkout: checkout,
            reviewer: reviewer,
            reviews: reviews ?? reviewStore()
        )
    }

    private func finding(category: String = "correctness") -> ReportedFinding {
        ReportedFinding(
            file: "Cart.swift",
            line: 13,
            category: category,
            verdict: .confirmed,
            shortSummary: nil,
            summary: "total() ignoruje množství",
            failureScenario: nil
        )
    }

    /// Počká, až review doběhne — ale ne donekonečna.
    private func waitUntilIdle(_ store: AppStore) async throws {
        for _ in 0..<100_000 where store.isReviewing(pr) { await Task.yield() }
        #expect(!store.isReviewing(pr))
    }

    // MARK: - Šťastná cesta

    @Test("Review doběhne a nálezy skončí v řádku i na disku")
    func aFinishedReviewShowsUpEverywhere() async throws {
        let reviews = reviewStore()
        let store = store(
            gateway: gateway(),
            reviewer: FakeReviewRunner(findings: [finding()]),
            reviews: reviews
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(store.reviewState(for: pr) == .completed(findings: 1))
        #expect(store.reviewRecord(for: pr)?.findings.count == 1)
        // Přežije to restart: druhý store čte tutéž složku.
        let restarted = self.store(gateway: gateway(), reviews: reviews)
        await restarted.loadStoredReviews()
        #expect(restarted.reviewRecord(for: pr)?.findings.count == 1)
    }

    @Test("Reviewer dostane worktree a base commit")
    func theReviewerGetsTheWorktreeAndBase() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(gateway: gateway(), reviewer: reviewer)

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        let request = try #require(reviewer.requests.first)
        #expect(request.key.headSha == "aaaa1111")
        #expect(request.baseSha == "bbbb2222")
        #expect(request.key.skillID == AppStore.defaultSkills.first)
        #expect(request.worktree.path(percentEncoded: false).contains("aaaa1111"))
    }

    @Test("Doběhlé review bez nálezů je čisté, ne selhání")
    func aCleanReviewIsNotAFailure() async throws {
        let store = store(gateway: gateway(), reviewer: FakeReviewRunner())

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(store.reviewState(for: pr) == .clean)
    }

    @Test("Nezavolaný ReportFindings se za čisté nevydává")
    func aRunThatNeverReportedIsNotClean() async throws {
        let store = store(
            gateway: gateway(),
            reviewer: FakeReviewRunner(calledReportFindings: false)
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        guard case .failed = store.reviewState(for: pr) else {
            Issue.record("Očekáván rozlišený stav, přišlo \(store.reviewState(for: pr))")
            return
        }
    }

    // MARK: - Průběh a zrušení

    @Test("Během běhu řádek ukazuje, kolik je hotovo")
    func theRowShowsProgressWhileRunning() async throws {
        let reviewer = FakeReviewRunner(holdsUntilRelease: true)
        let store = store(gateway: gateway(), reviewer: reviewer)

        store.startReview(for: pr)
        await reviewer.waitForStarts(1)

        #expect(store.reviewState(for: pr) == .running(finished: 0, total: 1))
        #expect(store.isReviewing(pr))
        // Repo s běžícím review je pro eviction nedotknutelné.
        #expect(store.busyRepositories.contains(pr.repo))

        reviewer.releaseAll()
        try await waitUntilIdle(store)
    }

    @Test("Zrušení běh ukončí a nic neuloží")
    func cancellingLeavesNothingBehind() async throws {
        let reviewer = FakeReviewRunner(findings: [finding()], holdsUntilRelease: true)
        let store = store(gateway: gateway(), reviewer: reviewer)

        store.startReview(for: pr)
        await reviewer.waitForStarts(1)
        store.cancelReview(for: pr)
        try await waitUntilIdle(store)

        #expect(store.reviewRecord(for: pr) == nil)
        #expect(store.reviewState(for: pr) == .notStarted)
    }

    @Test("Druhé zmáčknutí během běhu nespustí nic dalšího")
    func startingTwiceRunsOnce() async throws {
        let reviewer = FakeReviewRunner(holdsUntilRelease: true)
        let store = store(gateway: gateway(), reviewer: reviewer)

        store.startReview(for: pr)
        await reviewer.waitForStarts(1)
        store.startReview(for: pr)
        reviewer.releaseAll()
        try await waitUntilIdle(store)

        #expect(reviewer.requests.count == 1)
    }

    // MARK: - Chyby

    @Test("Chyba GitHubu je stav tohohle PR, ne celého repa")
    func aGitHubErrorBelongsToThePullRequest() async throws {
        let store = store(gateway: gateway(detail: .failure(GitHubError.notFound("PR není"))))

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        guard case .failed(let detail) = store.reviewState(for: pr) else {
            Issue.record("Očekáváno selhání, přišlo \(store.reviewState(for: pr))")
            return
        }
        #expect(detail.isEmpty == false)
        #expect(store.checkoutState(for: pr.repo) == .absent)
    }

    @Test("Selhání pracovní kopie je stav repa")
    func aCheckoutErrorBelongsToTheRepository() async throws {
        // Druhé PR téhož repa na ni narazí taky a řeší se stejným tlačítkem.
        let failure = CheckoutError.notAuthenticated("gh není přihlášený")
        let checkout = FakeRepoCheckout(outcome: .failure(failure))
        let store = store(gateway: gateway(), checkout: checkout)

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        guard case .failed = store.checkoutState(for: pr.repo) else {
            Issue.record("Očekáváno selhání checkoutu, přišlo \(store.checkoutState(for: pr.repo))")
            return
        }
        #expect(store.reviewState(for: pr) == .checkoutFailed(detail: failure.userDescription))
    }

    // MARK: - Zastaralost

    @Test("Nový commit zneplatní nálezy z minula hned, ne až po doběhnutí")
    func aNewCommitInvalidatesOldFindingsImmediately() async throws {
        // Bez toho by řádek celou dobu běhu ukazoval nálezy proti kódu, který v PR není.
        let reviews = reviewStore()
        let older = ReviewRunKey(pullRequest: pr, headSha: "0000dead", skillID: "code-review")
        var summary = StreamSummary()
        summary.calledReportFindings = true
        summary.findings = [finding()]
        try await reviews.save(ReviewRun(key: older, summary: summary, outcome: .finished))

        let reviewer = FakeReviewRunner(holdsUntilRelease: true)
        let store = store(gateway: gateway(), reviewer: reviewer, reviews: reviews)
        await store.loadStoredReviews()
        #expect(store.reviewState(for: pr) == .completed(findings: 1))

        store.startReview(for: pr)
        await reviewer.waitForStarts(1)
        #expect(store.reviewRecord(for: pr)?.isStale == true)

        reviewer.releaseAll()
        try await waitUntilIdle(store)
        #expect(store.reviewState(for: pr) == .clean)
    }
}
