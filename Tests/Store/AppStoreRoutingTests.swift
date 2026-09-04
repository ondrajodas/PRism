import Foundation
import Testing

@testable import PRism

/// Routing reviewerů podle změněných cest (#518) — od konfigurace po dráhu v tabu `Průběh`.
///
/// **Nejcennější tvrzení jsou tady negativní**: že přeskočený reviewer **nespustil session**, že
/// se z něj **nekreslí čisto** a že se `git` na změněné cesty **neptá** na repu, které routing
/// nenastavilo. Každé z nich se rozbije potichu — chybějící review vypadá v okně stejně jako
/// review, které nic nenašlo.
@Suite("AppStore — routing reviewerů")
@MainActor
struct AppStoreRoutingTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let auth = ["src/Auth/**", "*.env*"]

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private var summary: PullRequestSummary { summary(updatedAt: 100) }

    private func summary(updatedAt: TimeInterval) -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    private var detail: PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "head1111",
            baseSha: "base0000",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    /// Dva reviewery v sadě, routing **vyjmenovaný** v parametru: test, který se na něj ptá, nemá
    /// stát na tom, co je zrovna v `Configuration.standard`.
    private func configuration(routing: [String: [String]]?) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.skills = ["php-review", "security-review"]
        var repository = RepositoryConfig()
        repository.reviewerPaths = routing
        configuration.setRepository(repository, for: pr.repo)
        return configuration
    }

    private func store(
        routing: [String: [String]]?,
        changed: [String],
        reviewer: FakeReviewRunner,
        checkout: FakeRepoCheckout? = nil,
        reviews: ReviewStore? = nil
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([summary]), detail: .success(detail)),
            configuration: configuration(routing: routing),
            time: FakeTimeSource(),
            checkout: checkout ?? FakeRepoCheckout(changed: .success(changed)),
            reviewer: reviewer,
            reviews: reviews ?? ReviewStore(layout: layout, time: FakeTimeSource()),
            cacheLayout: layout
        )
    }

    private func waitUntilIdle(_ store: AppStore) async throws {
        await waitUntil("review doběhne") { !store.isReviewing(pr) }
        #expect(!store.isReviewing(pr))
    }

    private func lane(_ store: AppStore, of skill: String) -> ReviewerLane? {
        Policy.lanes(
            of: store.timelines(for: pr),
            skills: store.reviewSkills(for: pr.repo),
            record: store.reviewRecord(for: pr),
            running: store.runningReviewers(for: pr),
            // Tou samou cestou, jakou to čte okno — dvě cesty by znamenaly, že test tvrdí něco
            // o mapě a okno kreslí z něčeho jiného.
            skipped: store.skippedReviewers(for: pr)
        ).first { $0.skill == skill }
    }

    // MARK: - Přeskočený reviewer nespustil session

    @Test("Reviewer, jehož cesty se nezměnily, session nespustí")
    func aSkippedReviewerStartsNoSession() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            routing: ["security-review": auth],
            changed: ["README.md", "docs/navrh.html"],
            reviewer: reviewer
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        // **To hlavní tvrzení**: běžel jeden reviewer, ne dva.
        #expect(reviewer.requests.map(\.key.skillID) == ["php-review"])
        #expect(store.routingSkips[pr]?.skipped == ["security-review": auth])
        #expect(store.routingSkips[pr]?.headSha == detail.headSha)
    }

    /// Přeskočený reviewer o kódu neřekl **nic**, takže se nesmí kreslit ani jako čisto, ani jako
    /// spadlý, ani jako „ještě neběžel“. Je to tatáž hranice, jakou #383 zavedlo u `inconclusive`.
    @Test("Přeskočená dráha není čistá ani spadlá — je přeskočená")
    func aSkippedLaneIsNeitherCleanNorFailed() async throws {
        let store = store(
            routing: ["security-review": auth],
            changed: ["README.md"],
            reviewer: FakeReviewRunner()
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        let skipped = try #require(lane(store, of: "security-review"))
        #expect(skipped.state == .skipped(patterns: auth))
        #expect(skipped.state != .finished)
        #expect(skipped.state != .notStarted)
        #expect(skipped.failure == nil)
        // Nenahlásil nic — a `nil` není nula: nula by znamenala prázdný seznam, tedy tvrzení
        // o kódu.
        #expect(skipped.reportedFindings == nil)
        #expect(skipped.usage == nil)
        #expect(ReviewerLaneText.state(skipped.state) == "přeskočeno")
        #expect(ReviewerLaneText.last(of: skipped) == nil)
        // Ten druhý doběhl, takže je z čeho poznat, že se nezastavilo review celé.
        #expect(lane(store, of: "php-review")?.state == .finished)
        // A v uloženém záznamu je jen ten, co běžel — běh, který se nestal, nic neuložil.
        #expect(store.reviewRecord(for: pr)?.runs.map(\.skillID) == ["php-review"])
    }

    /// Bez pravidla se pouští všechno, jako do #518 — a **`git` se na cesty vůbec neptá**: repo,
    /// které si routing nenastavilo, se má chovat do posledního podprocesu jako dřív.
    @Test("Repo bez pravidla pustí celou sadu a na změněné cesty se neptá")
    func withoutRulesNothingChanges() async throws {
        let reviewer = FakeReviewRunner()
        let checkout = FakeRepoCheckout(changed: .success(["README.md"]))
        let store = store(routing: nil, changed: [], reviewer: reviewer, checkout: checkout)

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(Set(reviewer.requests.map(\.key.skillID)) == ["php-review", "security-review"])
        #expect(checkout.askedChangedFilesSince.isEmpty)
        #expect(store.routingSkips[pr] == nil)
    }

    /// Selhání výpisu cest routing **vypne**, nepoloží review: `git`, který neodpověděl, znamená
    /// „cesty neznáme“ — a přeskočit revieweera kvůli tomu je tichá ztráta review.
    @Test("Když se změněné cesty nezjistí, pustí se celá sada a řekne se to")
    func aFailedFileListRunsEverything() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            routing: ["security-review": auth],
            changed: [],
            reviewer: reviewer,
            checkout: FakeRepoCheckout(changed: .failure(.timedOut))
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(Set(reviewer.requests.map(\.key.skillID)) == ["php-review", "security-review"])
        #expect(store.routingSkips[pr] == nil)
        #expect(store.configurationFailure?.contains("bez routingu") == true)
        // **Věta pro člověka, ne `localizedDescription`** (nález Copilota): `CheckoutError` není
        // `LocalizedError`, takže by v hlášce stálo `The operation couldn’t be completed.
        // (PRism.CheckoutError error 5.)`. Tvrdí se to na obou stranách — že tam je věta z
        // `userDescription` a že tam **není** ta systémová.
        #expect(store.configurationFailure?.contains(CheckoutError.timedOut.userDescription) == true)
        #expect(store.configurationFailure?.contains("couldn") != true)
    }

    // MARK: - Ruční spuštění routing nefiltruje

    /// `Pustit přesto` je výslovný pokyn na konkrétního revieweera, takže se pravidlo neuplatní —
    /// jinak by tlačítko na dráze nedělalo nic a nebylo by z čeho poznat proč.
    @Test("Vyžádaný reviewer se pustí, i když na jeho vzory nic nesedí")
    func anExplicitSubsetIgnoresRouting() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            routing: ["security-review": auth],
            changed: ["README.md"],
            reviewer: reviewer
        )

        store.startReview(for: pr, skills: ["security-review"])
        try await waitUntilIdle(store)

        #expect(reviewer.requests.map(\.key.skillID) == ["security-review"])
    }

    // MARK: - Automat nezaplatí review podruhé

    /// **Tohle je ta drahá chyba** (a je to celý důvod, proč se přeskočení pamatuje): přeskočený
    /// reviewer doběhlý běh nemá a nikdy mít nebude, takže by hotové review vypadalo jako
    /// nedokončené — a stačil by komentář pod PR (mění `updatedAt`), aby automat zaplatil celé
    /// review znovu nad tou samou hlavou.
    @Test("Komentář nad hlavou s přeskočeným revieweerem session neutratí")
    func aCommentDoesNotPayForTheSameHeadAgain() async throws {
        let reviewer = FakeReviewRunner()
        var configuration = configuration(routing: ["security-review": auth])
        // Jeden zdroj, ne výchozí dva: fake gateway spotřebovává odpovědi po dotazech, takže by
        // se s druhým zdrojem posunula celá sekvence (tatáž úvaha jako v `AppStoreAutomaticTests`).
        configuration.global.sources = [.reviewRequested]
        var repository = try #require(configuration.repositories[pr.repo])
        repository.mode = .automatic
        configuration.setRepository(repository, for: pr.repo)

        let gateway = FakeGitHubGateway(
            [.success([summary]), .success([summary(updatedAt: 200)])],
            detail: .success(detail)
        )
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(changed: .success(["README.md"])),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            autoRuns: AutoRunLedger(layout: layout, time: FakeTimeSource()),
            cacheLayout: layout
        )

        await store.refresh()
        await waitUntil("první tik doběhne") { store.busyRepositories.isEmpty }
        await store.refresh()
        await waitUntil("druhý tik doběhne") { store.busyRepositories.isEmpty }

        // Detail se dotáhl dvakrát — to je jedno `gh pr view`, ne session.
        #expect(gateway.detailRequests.count == 2)
        #expect(reviewer.requests.map(\.key.skillID) == ["php-review"])
    }

    // MARK: - Sada přeskočená celá

    /// Nezůstalo koho pustit: **nic se neutratí a nic se neuloží**. Uložený záznam by tu byl na
    /// škodu — běh, který se nestal, nemá čím přepsat nálezy z předchozí hlavy.
    @Test("Když se nepustí nikdo, neutratí se session ani nevznikne záznam")
    func skippingEverybodySpendsNothing() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            routing: ["php-review": ["src/**"], "security-review": auth],
            changed: ["README.md"],
            reviewer: reviewer
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(reviewer.requests.isEmpty)
        #expect(store.reviewRecord(for: pr) == nil)
        // Řádek PR se z toho **netváří jako čistý**: nic neběželo, takže `neběželo`.
        #expect(store.reviewState(for: pr) == .notStarted)
        #expect(store.routingSkips[pr]?.skipped.count == 2)
        // Dráhy přesto **stojí** a nesou důvod — jinak by tab `Průběh` vypadal, jako by se
        // tlačítko nezmáčklo.
        #expect(lane(store, of: "php-review")?.state == .skipped(patterns: ["src/**"]))
        #expect(lane(store, of: "security-review")?.state == .skipped(patterns: auth))
    }
}
