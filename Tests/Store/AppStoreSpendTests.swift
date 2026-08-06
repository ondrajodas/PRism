import Foundation
import Testing

@testable import PRism

/// Útrata za dnešek (#148). Proti **skutečnému** `SpendLedger`u nad dočasnou složkou, protože
/// celé je to o tom, co na disku zůstane — fake by ověřoval sám sebe.
@Suite("AppStore — útrata")
@MainActor
struct AppStoreSpendTests {
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

    private func store(usage: RunUsage?, spend: SpendLedger) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(usage: usage),
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            spend: spend
        )
    }

    private func ledger() -> SpendLedger {
        SpendLedger(layout: layout, time: FakeTimeSource())
    }

    /// Čeká se točením: zrušený běh musí z čekání vypadnout sám, jinak by test visel místo
    /// aby spadl.
    private func waitUntilIdle(_ store: AppStore) async throws {
        for _ in 0..<100_000 where store.isReviewing(pr) { await Task.yield() }
        #expect(!store.isReviewing(pr))
    }

    @Test("Doběhlé review se propíše do útraty za dnešek")
    func recordsWhatARunCost() async throws {
        let store = store(usage: RunUsage(cost: 0.25, turns: 3), spend: ledger())

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(store.dailySpend?.cost == 0.25)
        #expect(store.dailySpend?.runs == 1)
    }

    /// Součet za den, který vynuluje restart, na otázku „co mě dneska stálo review“
    /// neodpovídá.
    @Test("Útrata přežije restart")
    func survivesARestart() async throws {
        let spend = ledger()
        let store = store(usage: RunUsage(cost: 0.25), spend: spend)

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        let restarted = self.store(usage: nil, spend: ledger())
        await restarted.loadDailySpend()
        #expect(restarted.dailySpend?.cost == 0.25)
    }

    /// Zabitý běh cenu nenahlásí — a nula by tvrdila, že byl zdarma.
    @Test("Běh bez ceny neukáže nulu, ale neznámý běh")
    func aRunWithoutACostIsNotZero() async throws {
        let store = store(usage: nil, spend: ledger())

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(store.dailySpend?.cost == 0)
        #expect(store.dailySpend?.unknown == 1)
        #expect(store.dailySpend?.isEmpty == false)
    }

    /// Bez `SpendLedger`u se nic netvrdí — řádek pak útratu neukazuje vůbec.
    @Test("Bez účetní knihy se útrata nedrží")
    func withoutALedgerThereIsNothingToShow() async throws {
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(usage: RunUsage(cost: 0.25)),
            reviews: ReviewStore(layout: layout, time: FakeTimeSource())
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(store.dailySpend == nil)
    }

    /// Cena patří k běhu, takže musí přežít cestu na disk — jinak se v `Průběhu` po restartu
    /// neukáže nic.
    @Test("Cena se uloží k záznamu běhu")
    func storesTheCostWithTheRun() async throws {
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(usage: RunUsage(cost: 0.25, duration: .seconds(12), turns: 3)),
            reviews: reviews,
            spend: ledger()
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        let loaded = try await reviews.load().records
        let run = try #require(loaded.first?.runs.first)
        #expect(run.usage?.cost == 0.25)
        #expect(run.usage?.duration == .seconds(12))
        #expect(run.usage?.turns == 3)
    }

    /// Osa v tabu `Průběh` cenu ukazuje u revieweera, takže ji musí dostat s koncem běhu.
    @Test("Osa revieweera cenu dostane")
    func theTimelineGetsTheCost() async throws {
        let store = store(usage: RunUsage(cost: 0.25, turns: 3), spend: ledger())

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        let timeline = try #require(store.timelines(for: pr).first)
        #expect(timeline.usage?.cost == 0.25)
        #expect(timeline.usage?.turns == 3)
    }
}
