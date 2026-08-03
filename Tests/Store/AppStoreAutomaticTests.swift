import Foundation
import Testing

@testable import PRism

/// Automatický režim celou cestou: tik → plánovač → rozpočet → session. Fake gateway,
/// fake checkout, fake reviewer a **skutečný** `ReviewStore` i `AutoRunLedger` nad dočasnou
/// složkou — na obou stojí to, co se stane po restartu.
@Suite("AppStore — automatický režim")
@MainActor
struct AppStoreAutomaticTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let repo = RepoID(owner: "cli", name: "cli")
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func summary(_ number: Int = 42, updatedAt: TimeInterval = 100) -> PullRequestSummary {
        let id = PRIdentifier(repo: repo, number: number)
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    private func detail(headSha: String = "aaaa1111") -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: headSha,
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(
        gateway: FakeGitHubGateway,
        reviewer: FakeReviewRunner = FakeReviewRunner(),
        mode: ReviewMode = .automatic,
        limit: Int = 20
    ) -> AppStore {
        var configuration = Configuration.standard
        configuration.global.autoRunsPerDay = limit
        configuration.repositories = [repo: RepositoryConfig(mode: mode)]
        return AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            autoRuns: AutoRunLedger(layout: layout, time: FakeTimeSource())
        )
    }

    /// Počká, až doběhne všechno, co tik rozjel.
    private func settle(_ store: AppStore) async {
        for _ in 0..<100_000 where !store.busyRepositories.isEmpty { await Task.yield() }
    }

    @Test("PR z automatického repa se zreviduje bez kliknutí")
    func reviewsAutomatically() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail())),
            reviewer: reviewer
        )

        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.map(\.key.pullRequest) == [pr])
    }

    @Test("Manuální repo se samo nespustí")
    func leavesManualRepositoriesAlone() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail())),
            reviewer: reviewer,
            mode: .manual
        )

        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.isEmpty)
    }

    /// Tohle je ta drahá chyba: každý tik by jinak utratil session za totéž.
    @Test("Druhý tik nad stejným commitem session neutratí")
    func doesNotSpendASessionTwiceOnTheSameCommit() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail())),
            reviewer: reviewer
        )

        await store.refresh()
        await settle(store)
        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.count == 1)
    }

    /// `updatedAt` se mění i po komentáři, takže plánovač PR pustí dál — session se ale
    /// utratit nesmí, protože `headSha` je stejný.
    @Test("Změna updatedAt bez nového commitu session neutratí")
    func aCommentDoesNotSpendASession() async throws {
        let reviewer = FakeReviewRunner()
        let gateway = FakeGitHubGateway(
            [.success([summary(updatedAt: 100)]), .success([summary(updatedAt: 200)])],
            detail: .success(detail())
        )
        let store = store(gateway: gateway, reviewer: reviewer)

        await store.refresh()
        await settle(store)
        await store.refresh()
        await settle(store)

        // Detail se dotáhl dvakrát — to je jedno `gh pr view`, ne session.
        #expect(gateway.detailRequests.count == 2)
        #expect(reviewer.requests.count == 1)
    }

    @Test("Nový commit spustí review znovu")
    func aNewCommitRunsAgain() async throws {
        let reviewer = FakeReviewRunner()
        let gateway = FakeGitHubGateway(
            [.success([summary(updatedAt: 100)]), .success([summary(updatedAt: 200)])],
            detail: .success(detail())
        )
        let store = store(gateway: gateway, reviewer: reviewer)
        await store.refresh()
        await settle(store)

        // Druhý tik vidí jiný head commit.
        gateway.detailFromNowOn = .success(detail(headSha: "cccc3333"))
        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.map(\.key.headSha) == ["aaaa1111", "cccc3333"])
    }

    /// Pojistka proti překvapení na účtu. Ruční spouštění limit nezná.
    @Test("Denní limit automat pozastaví")
    func stopsAtTheDailyLimit() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            gateway: FakeGitHubGateway(
                always: .success([summary(1), summary(2), summary(3)]),
                detail: .success(detail())
            ),
            reviewer: reviewer,
            limit: 2
        )

        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.count == 2)
        #expect(store.remainingAutomaticRuns == 0)
    }

    @Test("Bez automatického repa se o limitu nemluví")
    func saysNothingAboutTheLimitWithoutAutomaticRepositories() async throws {
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail())),
            mode: .manual
        )

        await store.refresh()
        await settle(store)

        #expect(store.remainingAutomaticRuns == nil)
    }
}
