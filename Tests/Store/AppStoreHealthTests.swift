import Foundation
import Testing

@testable import PRism

/// Signály, které do stavového řádku dodává `AppStore`.
///
/// To hlavní tady není, jak se puntík skládá (to je `Policy`), ale **odkud bere skutečná
/// volání**: řádek jede na provozu, který se děje tak jako tak, a rozejít se s pollingem
/// znamená svítit červeně nad funkčním GitHubem.
@Suite("AppStore — dostupnost služeb")
@MainActor
struct AppStoreHealthTests {
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

    private func monitor() -> HealthMonitor {
        // Status page se odsud neptáme vůbec: jde o skutečná volání, ne o incidenty.
        HealthMonitor(
            statusPage: FakeStatusPage(.success(.unchanged)),
            reachability: FakeReachability(),
            time: FakeTimeSource()
        )
    }

    private func store(
        gateway: FakeGitHubGateway,
        health: HealthMonitor,
        reviewer: FakeReviewRunner = FakeReviewRunner()
    ) -> AppStore {
        AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            health: health
        )
    }

    private func waitUntilIdle(_ store: AppStore) async {
        for _ in 0..<100_000 where store.isReviewing(pr) { await Task.yield() }
        #expect(!store.isReviewing(pr))
    }

    @Test("Bez monitoru řádek žádné puntíky neukazuje")
    func withoutMonitorThereAreNoDots() {
        let store = AppStore(gateway: FakeGitHubGateway(always: .success([])), time: FakeTimeSource())

        #expect(store.healthReports.isEmpty)
    }

    @Test("Dokud se nic nezeptalo GitHubu, je jeho stav nezjištěný")
    func gitHubIsUnknownBeforeTheFirstTick() {
        let store = store(gateway: FakeGitHubGateway(always: .success([])), health: monitor())

        #expect(store.healthReports.map(\.state) == [.unknown, .unknown])
    }

    @Test("Prošlý tik pollingu rozsvítí GitHub zeleně")
    func aSuccessfulTickTurnsGitHubGreen() async {
        let store = store(gateway: FakeGitHubGateway(always: .success([])), health: monitor())

        await store.refresh()

        // Polling se ptá každou minutu a je to **totéž volání**, na kterém stojí zbytek
        // aplikace — lepší zdravotní signál se nedá koupit a nestojí nic navíc.
        let report = try? #require(store.healthReports.first { $0.service == .github })
        #expect(report?.state == .operational)
        #expect(report?.call?.since == store.lastSuccess)
    }

    @Test("Selhaný tik rozsvítí GitHub červeně a řekne proč")
    func aFailedTickTurnsGitHubRed() async throws {
        let store = store(gateway: FakeGitHubGateway(always: .failure(GitHubError.notAuthenticated)), health: monitor())

        await store.refresh()

        let report = try #require(store.healthReports.first { $0.service == .github })
        #expect(report.state == .failing)
        #expect(report.reason.contains("gh auth login"))
    }

    @Test("Rate limit je taky selhané volání — zelená znamená „funguje mi to“")
    func rateLimitIsAFailedCall() async throws {
        let gateway = FakeGitHubGateway(always: .failure(GitHubError.rateLimited("API rate limit exceeded")))
        let store = store(gateway: gateway, health: monitor())

        await store.refresh()

        let report = try #require(store.healthReports.first { $0.service == .github })
        // Že za to GitHub nemůže, řekne věta — ale funkční to není.
        #expect(report.state == .failing)
        #expect(report.reason.contains("omezuje dotazy"))
    }

    @Test("Doběhlá session rozsvítí Claude zeleně")
    func aFinishedSessionTurnsClaudeGreen() async throws {
        let store = store(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            health: monitor()
        )

        store.startReview(for: pr)
        await waitUntilIdle(store)

        let report = try #require(store.healthReports.first { $0.service == .claude })
        #expect(report.state == .operational)
    }

    @Test("Spadlá session rozsvítí Claude červeně s tím, co přišlo na stderr")
    func aFailedSessionTurnsClaudeRed() async throws {
        let store = store(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            health: monitor(),
            reviewer: FakeReviewRunner(outcome: .failed(detail: "claude: command not found"))
        )

        store.startReview(for: pr)
        await waitUntilIdle(store)

        let report = try #require(store.healthReports.first { $0.service == .claude })
        #expect(report.state == .failing)
        #expect(report.reason.contains("command not found"))
    }

    @Test("Vytimeoutovaná session není zdravotní signál")
    func aTimedOutSessionSaysNothing() async throws {
        let store = store(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            health: monitor(),
            reviewer: FakeReviewRunner(outcome: .timedOut)
        )

        store.startReview(for: pr)
        await waitUntilIdle(store)

        // Session jsme po patnácti minutách zabili sami — z toho nejde vyvodit ani
        // „funguje“, ani „nefunguje“, a dlouhé review je běžná věc.
        let report = try #require(store.healthReports.first { $0.service == .claude })
        #expect(report.state == .unknown)
        #expect(store.lastReviewCall == nil)
    }

    @Test("Skryté okno se propíše do monitoru")
    func hidingTheWindowStopsTheChecks() {
        let health = monitor()
        let store = store(gateway: FakeGitHubGateway(always: .success([])), health: health)

        store.windowVisibilityChanged(false)
        #expect(!health.isWindowVisible)

        store.windowVisibilityChanged(true)
        #expect(health.isWindowVisible)
    }
}
