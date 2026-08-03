import Foundation
import Testing

@testable import PRism

/// Zahození uložených nálezů. Proti **skutečnému** `ReviewStore` nad dočasnou složkou —
/// jde právě o to, co po vyčištění zbude na disku.
@Suite("AppStore — zahození nálezů")
@MainActor
struct AppStoreClearFindingsTests {
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

    private func finding() -> ReportedFinding {
        ReportedFinding(
            file: "Cart.swift",
            line: 13,
            category: "correctness",
            verdict: .confirmed,
            shortSummary: nil,
            summary: "total() ignoruje množství",
            failureScenario: nil
        )
    }

    private func reviews() -> ReviewStore {
        ReviewStore(layout: layout, time: FakeTimeSource())
    }

    private func store(_ reviews: ReviewStore, findings: [ReportedFinding] = []) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: findings),
            reviews: reviews
        )
    }

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func runReview(_ store: AppStore) async {
        store.startReview(for: pr)
        for _ in 0..<100_000 where store.isReviewing(pr) { await Task.yield() }
    }

    @Test("Zahození vyprázdní panel, řádek i disk")
    func clearsEverywhere() async throws {
        let reviews = reviews()
        let store = store(reviews, findings: [finding()])
        await runReview(store)
        #expect(store.reviewRecord(for: pr) != nil)

        try await store.clearFindings(for: pr)

        #expect(store.reviewRecord(for: pr) == nil)
        #expect(store.reviewState(for: pr) == .notStarted)
        // A hlavně: přežije to restart.
        let restarted = self.store(reviews)
        await restarted.loadStoredReviews()
        #expect(restarted.reviewRecord(for: pr) == nil)
    }

    /// Smysl toho tlačítka je pustit review znovu, tak to musí jít.
    @Test("Po zahození začíná další běh načisto")
    func theNextRunStartsFresh() async throws {
        let reviews = reviews()
        let store = store(reviews, findings: [finding()])
        await runReview(store)
        try await store.clearFindings(for: pr)

        await runReview(store)

        #expect(store.reviewRecord(for: pr)?.findings.count == 1)
    }

    /// Tlačítko se dá zmáčknout dvakrát a druhé zmáčknutí nemá nic položit.
    @Test("Druhé zahození nic nerozbije")
    func clearingTwiceIsHarmless() async throws {
        let reviews = reviews()
        let store = store(reviews, findings: [finding()])
        await runReview(store)

        try await store.clearFindings(for: pr)
        try await store.clearFindings(for: pr)

        #expect(store.reviewRecord(for: pr) == nil)
    }

    @Test("Bez záznamu se nic neděje")
    func doesNothingWithoutARecord() async throws {
        let store = store(reviews())

        try await store.clearFindings(for: pr)

        #expect(store.reviewRecord(for: pr) == nil)
    }

    /// Zahození nálezů je právě ta chvíle, kdy se má review pustit znovu — a u repa
    /// v automatickém režimu na to nemá čekat tlačítko.
    @Test("Na automatickém repu se po zahození review pustí samo")
    func clearingRestartsAutomaticReview() async throws {
        let reviewer = FakeReviewRunner(findings: [finding()])
        var configuration = Configuration.standard
        configuration.repositories = [pr.repo: RepositoryConfig(mode: .automatic)]
        let store = AppStore(
            gateway: FakeGitHubGateway(
                always: .success([summary()]),
                detail: .success(detail)
            ),
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: reviews(),
            autoRuns: AutoRunLedger(layout: layout, time: FakeTimeSource())
        )
        await store.refresh()
        for _ in 0..<100_000 where store.isReviewing(pr) { await Task.yield() }
        #expect(reviewer.requests.count == 1)

        try await store.clearFindings(for: pr)
        for _ in 0..<100_000 where store.isReviewing(pr) { await Task.yield() }

        #expect(reviewer.requests.count == 2)
    }

    /// U manuálního repa se nesmí spustit nic — tam se review pouští tlačítkem.
    @Test("Na manuálním repu zahození nic nespustí")
    func clearingDoesNotStartManualReview() async throws {
        let reviewer = FakeReviewRunner(findings: [finding()])
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail)),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: reviews(),
            autoRuns: AutoRunLedger(layout: layout, time: FakeTimeSource())
        )
        await store.refresh()
        await runReview(store)

        try await store.clearFindings(for: pr)
        for _ in 0..<1000 { await Task.yield() }

        #expect(reviewer.requests.count == 1)
    }

    /// Historie znamená **ostatní** záznamy, ne ochranu toho viditelného. Kdo zmáčkne
    /// „zahodit“ nad zastaralými nálezy, chce se zbavit právě jich.
    @Test("Zahození sundá jen viditelný commit, starší záznamy nechá")
    func keepsOtherRecords() async throws {
        let reviews = reviews()
        let gateway = FakeGitHubGateway(always: .success([]), detail: .success(detail))
        let store = AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: [finding()]),
            reviews: reviews
        )
        await runReview(store)

        // Nový commit a nad ním druhý běh — na disku jsou teď dva záznamy.
        gateway.detailFromNowOn = .success(
            PullRequest(
                id: pr,
                title: "titulek",
                author: "autor",
                headSha: "cccc3333",
                baseSha: "bbbb2222",
                url: URL(string: "https://github.com/cli/cli/pull/42")!,
                updatedAt: Date(timeIntervalSince1970: 200),
                state: .open
            )
        )
        await runReview(store)
        #expect(try await reviews.load().records.count == 2)

        try await store.clearFindings(for: pr)

        let onDisk = try await reviews.load()
        #expect(onDisk.records.map(\.headSha) == ["aaaa1111"])
    }
}
