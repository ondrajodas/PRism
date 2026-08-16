import Foundation
import Testing

@testable import PRism

/// Cesta časového limitu z nastavení do běhu (#320).
///
/// Tři tvrzení, a **dvě z nich jsou o tom, co se nestane**: limit se v runneru nečte znovu (putuje
/// s požadavkem, takže rozjetý běh doběhne s tím svým), a hodnota mimo meze se dovnitř nedostane
/// ani oklikou přes override u repa.
@Suite("AppStore — časový limit běhu")
@MainActor
struct AppStoreTimeoutTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let repo = RepoID(owner: "cli", name: "cli")
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let time = FakeTimeSource()

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

    private func store(
        _ configuration: Configuration,
        reviewer: FakeReviewRunner
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            configuration: configuration,
            time: time,
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: time)
        )
    }

    private func configuration(global: Int, repository: Int? = nil) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.reviewTimeoutMinutes = global
        if let repository {
            configuration.setRepository(
                RepositoryConfig(reviewTimeoutMinutes: repository),
                for: repo
            )
        }
        return configuration
    }

    private func runReview(_ configuration: Configuration) async throws -> ReviewRequest {
        let reviewer = FakeReviewRunner()
        let store = store(configuration, reviewer: reviewer)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        return try #require(reviewer.requests.first)
    }

    // MARK: - Globální hodnota a override

    @Test("Limit z nastavení dojede až k běhu")
    func theConfiguredTimeoutReachesTheRun() async throws {
        let request = try await runReview(configuration(global: 40))

        #expect(request.timeout == .seconds(2400))
    }

    /// Nedotčená konfigurace znamená patnáct minut — chování před #320.
    @Test("Výchozí konfigurace pouští běh s patnácti minutami")
    func theDefaultConfigurationRunsWithFifteenMinutes() async throws {
        let request = try await runReview(.standard)

        #expect(request.timeout == .seconds(900))
    }

    @Test("Vlastní limit repa přebije globální")
    func aRepositoryOverrideWins() async throws {
        let request = try await runReview(configuration(global: 10, repository: 45))

        #expect(request.timeout == .seconds(2700))
    }

    /// Meze platí i na cestě do běhu, ne jen v poli v nastavení — jinak by se strop dal obejít
    /// ručním zápisem do `config.json`, tedy zrovna tou cestou, kterou se do něj píše.
    @Test(
        "Hodnota mimo meze se do běhu dostane sražená",
        arguments: [(600, Duration.seconds(3600)), (0, .seconds(300))]
    )
    func outOfRangeValuesReachTheRunClamped(
        configured: Int,
        expected: Duration
    ) async throws {
        let request = try await runReview(configuration(global: configured))

        #expect(request.timeout == expected)
    }

    // MARK: - Běh si drží svůj limit

    /// **Změna nastavení nesmí sáhnout na rozjetý běh.** Kdyby si limit četl runner, poběží
    /// session s hodnotou, se kterou nezačala — a hláška o timeoutu by mluvila o jiném limitu než
    /// ten, který session zabil.
    @Test("Rozjeté review doběhne s limitem, se kterým začalo")
    func aRunningReviewKeepsItsOwnTimeout() async throws {
        let workspace = try TemporaryDirectory()
        let configStore = ConfigStore(layout: CacheLayout(root: workspace.url))
        try await configStore.save(configuration(global: 20))
        let reviewer = FakeReviewRunner(holdsUntilRelease: true)
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            configStore: configStore,
            time: time,
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: time)
        )
        await store.reloadConfiguration()

        store.startReview(for: pr)
        await reviewer.waitForStarts(1)
        // Soubor se přepíše, zatímco session běží — tedy přesně to, co dělá okno nastavení.
        try await configStore.save(configuration(global: 55))
        await store.reloadConfiguration()
        #expect(store.resolved(for: repo).reviewTimeout == .seconds(3300))
        reviewer.releaseAll()
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        let request = try #require(reviewer.requests.first)
        #expect(request.timeout == .seconds(1200))
    }

    // MARK: - Kontrola nálezů (#150)

    /// Kontrola jde **toutéž cestou** a má **tentýž limit** — je to tatáž session a tytéž peníze.
    /// Vlastní kratší strop by z pomalé kontroly udělal `timedOut`.
    @Test("Kontrola nálezů běží s tímtéž limitem jako review")
    func theRecheckSharesTheReviewTimeout() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        var stream = StreamSummary()
        stream.calledReportFindings = true
        stream.findings = [makeReported(file: "Cart.swift", line: 13)]
        try await reviews.save(ReviewRun(
            key: ReviewRunKey(pullRequest: pr, headSha: "old1111", skillID: "code-review"),
            summary: stream,
            outcome: .finished
        ))

        let reviewer = FakeReviewRunner(resultText: "[]")
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            configuration: configuration(global: 35),
            time: time,
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: reviews
        )
        await store.loadStoredReviews()
        // Hlavu PR zná jenom detail — bez něj se kontrola vůbec nenabídne.
        await store.loadDetail(for: PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        ))

        store.startRecheck(for: pr)
        await waitUntil("kontrola doběhne") { !store.isRechecking(self.pr) }

        let request = try #require(reviewer.requests.first)
        #expect(request.recheck != nil)
        #expect(request.timeout == .seconds(2100))
    }
}
