import Foundation
import Testing

@testable import PRism

/// Tiché hodiny ze strany store (#519) — celá cesta: tik → plánovač → brána → zápis → vyzvednutí.
///
/// **Cenná polovina jsou tvrzení o tom, co se nestane**: že se odložený běh nespustí dřív, že
/// nezaplatí checkout ani session, že otevřený PR se **neodloží vůbec** (a už odložený se
/// otevřením záložky **nespustí**) a že se denním limitem neprojde jen proto, že je noc. Ani jedno
/// není z obrazovky poznat — odložený běh vypadá jako běh, na který ještě nedošlo.
///
/// **Hodiny okna se počítají z fake času, ne z literálu.** `AppStore` bere `Calendar.current`,
/// tedy zónu stroje, takže napsané `22`–`6` by dělalo test zeleným jen v některých zónách
/// a v některých hodinách — tentýž kořen jako globální stav procesu v `Tests/` (#367).
@Suite("AppStore — tiché hodiny (#519)")
@MainActor
struct AppStoreQuietHoursTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let repo = RepoID(owner: "cli", name: "cli")
    private let pr = PRIdentifier("cli/cli#42")!
    /// Fake hodiny startují tady; okno se z toho odvozuje, viz `awayFromNow` a `aroundNow`.
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    /// Hodina, ve které fake hodiny stojí — **v zóně stroje**, tedy v té, kterou uvidí i store.
    private func hour(of moment: Date) -> Int {
        Calendar.current.component(.hour, from: moment)
    }

    /// Okno, ve kterém `moment` **není**. Dvě hodiny za ním, aby se do něj nevešel ani začátek.
    private func awayFromNow(_ moment: Date, threshold: Int = 1500) -> QuietHours {
        let now = hour(of: moment)
        return QuietHours(
            isEnabled: true,
            lineThreshold: threshold,
            startHour: (now + 2) % 24,
            endHour: (now + 4) % 24
        )
    }

    /// Okno, ve kterém `moment` **je**.
    private func aroundNow(_ moment: Date, threshold: Int = 1500) -> QuietHours {
        let now = hour(of: moment)
        return QuietHours(
            isEnabled: true,
            lineThreshold: threshold,
            startHour: now,
            endHour: (now + 2) % 24
        )
    }

    private func summary(_ number: Int = 42, updatedAt: Date? = nil) -> PullRequestSummary {
        let id = PRIdentifier(repo: repo, number: number)
        return PullRequestSummary(
            id: id,
            title: "chore: modernize dependencies",
            author: "odinuv",
            url: URL(string: "https://github.com/cli/cli/pull/\(number)")!,
            updatedAt: updatedAt ?? start,
            state: .open
        )
    }

    private func detail(_ number: Int = 42, lines: Int?, headSha: String = "aaaa1111") -> PullRequest {
        PullRequest(
            id: PRIdentifier(repo: repo, number: number),
            title: "chore: modernize dependencies",
            author: "odinuv",
            headSha: headSha,
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/\(number)")!,
            updatedAt: start,
            state: .open,
            changedLines: lines
        )
    }

    private func store(
        gateway: FakeGitHubGateway,
        reviewer: FakeReviewRunner = FakeReviewRunner(),
        quietHours: QuietHours,
        limit: Int = 20,
        clock: FakeTimeSource? = nil,
        ledger: AutoRunLedger? = nil,
        deferrals: DeferredRunStore? = nil,
        snoozes: SnoozeStore? = nil
    ) -> AppStore {
        let time = clock ?? FakeTimeSource(start: start)
        var configuration = Configuration.standard
        // **Jeden zdroj, ne výchozí dva** (#330): fake gateway spotřebovává odpovědi po dotazech,
        // takže by se s druhým zdrojem posunula celá sekvence.
        configuration.global.sources = [.reviewRequested]
        configuration.global.ownLogins = ["ondrajodas"]
        configuration.global.autoRunsPerDay = limit
        configuration.global.quietHours = quietHours
        configuration.repositories = [repo: RepositoryConfig(mode: .automatic)]
        return AppStore(
            gateway: gateway,
            configuration: configuration,
            time: time,
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: time),
            autoRuns: ledger ?? AutoRunLedger(layout: layout, time: time),
            snoozeStore: snoozes,
            deferredRuns: deferrals ?? DeferredRunStore(layout: layout, time: time)
        )
    }

    private func settle(_ store: AppStore) async {
        await waitUntil("tik doběhne") { store.busyRepositories.isEmpty }
    }
}

// MARK: - Co se nestane

extension AppStoreQuietHoursTests {
    /// **Základní tvrzení celého issue** — a k němu to, co odklad stát nesmí: žádný checkout,
    /// žádná session, žádný sáhnutý rozpočet. Zaplatí se jedině `gh pr view`, bez kterého se
    /// velikost PR zjistit nedá.
    @Test("Velké PR se mimo tiché hodiny nepustí a nic nestojí")
    func defersALargePullRequest() async throws {
        let reviewer = FakeReviewRunner()
        let ledger = AutoRunLedger(layout: layout, time: FakeTimeSource(start: start))
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail(lines: 2790))),
            reviewer: reviewer,
            quietHours: awayFromNow(start),
            ledger: ledger
        )

        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.isEmpty)
        #expect(await ledger.used() == 0)
        // Checkout se ani nezačal připravovat — brána stojí před ním.
        #expect(store.checkoutStates[repo] == nil)
        #expect(store.deferral(of: pr) != nil)
    }

    /// **Kontrolní měření** (#478): kdyby brána zastavovala všechno, vyšel by test výš zeleně
    /// i nad rozbitou aplikací. Malé PR musí projít toutéž cestou.
    @Test("Malé PR se pustí i mimo tiché hodiny")
    func runsASmallPullRequest() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail(lines: 12))),
            reviewer: reviewer,
            quietHours: awayFromNow(start)
        )

        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.map(\.key.pullRequest) == [pr])
        #expect(store.deferral(of: pr) == nil)
    }

    /// V noci je **tohle** ta chvíle, na kterou se odkládá.
    @Test("V tichých hodinách se velké PR pustí hned")
    func runsInsideTheWindow() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail(lines: 2790))),
            reviewer: reviewer,
            quietHours: aroundNow(start)
        )

        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.map(\.key.pullRequest) == [pr])
        #expect(store.deferral(of: pr) == nil)
    }

    /// **PR, který mám otevřený, se neodkládá** — člověk na něj čeká, takže se pustí hned.
    @Test("Otevřený PR se neodkládá a review se pustí")
    func anOpenPullRequestIsNeverDeferred() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail(lines: 2790))),
            reviewer: reviewer,
            quietHours: awayFromNow(start)
        )
        store.openTabs = [pr]

        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.map(\.key.pullRequest) == [pr])
        #expect(store.deferral(of: pr) == nil)
    }

    /// **Odklad, který už padl, otevření záložky nespustí — a je to vědomá odchylka od věty
    /// v zadání issue.** Dráha `odloženo na noc` se kreslí jedině v otevřené záložce, takže by se
    /// pod pravidlem „otevření pouští“ nedala vidět vůbec: `poběží 23:00` ani `Pustit teď` by se
    /// na obrazovku nikdy nedostaly. Cesta ven je proto tlačítko, ne vedlejšek otevření.
    @Test("Otevření už odloženého PR běh sám nespustí")
    func openingADeferredPullRequestDoesNotStartIt() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail(lines: 2790))),
            reviewer: reviewer,
            quietHours: awayFromNow(start)
        )
        await store.refresh()
        await settle(store)
        #expect(store.deferral(of: pr) != nil)

        store.openTabs = [pr]
        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.isEmpty)
        #expect(store.deferral(of: pr) != nil)
    }

    /// **Odklad není obejití limitu.** Rozpočet se strhává až v okamžiku, kdy se session utrácí —
    /// a to platí v noci stejně jako ve dne.
    @Test("Denním limitem se neprojde jen proto, že je noc")
    func theDailyLimitStillApplies() async throws {
        let reviewer = FakeReviewRunner()
        let ledger = AutoRunLedger(layout: layout, time: FakeTimeSource(start: start))
        let store = store(
            gateway: FakeGitHubGateway(
                always: .success([summary(1), summary(2)]),
                detail: .success(detail(lines: 2790))
            ),
            reviewer: reviewer,
            quietHours: aroundNow(start),
            limit: 1,
            ledger: ledger
        )

        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.count == 1)
        #expect(await ledger.used() == 1)
        #expect(store.isAutomaticStopped)
    }
}

// MARK: - Vyzvednutí a restart

extension AppStoreQuietHoursTests {
    /// Odložený běh se pustí, **jakmile hodiny dojdou** — a ani o tik dřív.
    @Test("Odložený běh se pustí až v tichých hodinách")
    func releasesWhenTheClockArrives() async throws {
        let reviewer = FakeReviewRunner()
        let clock = FakeTimeSource(start: start)
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail(lines: 2790))),
            reviewer: reviewer,
            quietHours: awayFromNow(start),
            clock: clock
        )
        await store.refresh()
        await settle(store)
        let deferral = try #require(store.deferral(of: pr))
        #expect(reviewer.requests.isEmpty)

        // Vteřinu před slíbeným časem se pořád nepouští — hranice, ne okolí.
        clock.advance(by: deferral.runAt.timeIntervalSince(start) - 1)
        await store.refresh()
        await settle(store)
        #expect(reviewer.requests.isEmpty)

        clock.advance(by: 1)
        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.map(\.key.pullRequest) == [pr])
        #expect(store.deferral(of: pr) == nil)
    }

    /// **Slib přežije restart, jinak by noc bez aplikace nepustila nic.** A protože se ta noc
    /// mohla celá prospat, běh se **nesmí odložit znovu** — vyzvednutý odklad jde přes bránu
    /// s `honoringQuietHours: false`.
    @Test("Odložený běh přežije restart a zmeškanou noc dožene ráno")
    func survivesARestartAndCatchesUp() async throws {
        let clock = FakeTimeSource(start: start)
        let deferrals = DeferredRunStore(layout: layout, time: clock)
        let gateway = FakeGitHubGateway(always: .success([summary()]), detail: .success(detail(lines: 2790)))
        let first = store(gateway: gateway, quietHours: awayFromNow(start), clock: clock, deferrals: deferrals)
        await first.refresh()
        await settle(first)
        let deferral = try #require(first.deferral(of: pr))

        // Restart o den později: aplikace celou noc neběžela, `runAt` je v minulosti — a hodiny
        // stojí zase mimo okno, takže by druhá brána běh odložila na další noc.
        let later = FakeTimeSource(start: deferral.runAt.addingTimeInterval(10 * 3600))
        let reviewer = FakeReviewRunner()
        let restarted = store(
            gateway: gateway,
            reviewer: reviewer,
            quietHours: awayFromNow(deferral.runAt.addingTimeInterval(10 * 3600)),
            clock: later,
            ledger: AutoRunLedger(layout: layout, time: later),
            deferrals: DeferredRunStore(layout: layout, time: later)
        )
        await restarted.loadDeferredRuns()
        #expect(restarted.deferral(of: pr) != nil)

        await restarted.refresh()
        await settle(restarted)

        #expect(reviewer.requests.map(\.key.pullRequest) == [pr])
        #expect(restarted.deferral(of: pr) == nil)
    }

    /// **Odložení PR (#512) přebíjí odložený běh** — a je to ta tichá díra, kvůli které tenhle test
    /// existuje: „tenhle teď vidět nechci“ platí i ve dvacet dva večer. Vyzvednutí proto bere
    /// **frontu** (bez odložených a jen cizí), ne holý seznam z tiku.
    @Test("Odložený PR se v tichých hodinách nepustí")
    func aSnoozedPullRequestIsNotReleased() async throws {
        let reviewer = FakeReviewRunner()
        let clock = FakeTimeSource(start: start)
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail(lines: 2790))),
            reviewer: reviewer,
            quietHours: awayFromNow(start),
            clock: clock,
            snoozes: SnoozeStore(layout: layout, time: clock)
        )
        await store.refresh()
        await settle(store)
        let deferral = try #require(store.deferral(of: pr))

        await store.snooze(pr, .until(deferral.runAt.addingTimeInterval(24 * 3600)))
        clock.advance(by: deferral.runAt.timeIntervalSince(start) + 60)
        await store.refresh()
        await settle(store)

        #expect(reviewer.requests.isEmpty)
    }

    /// `Pustit teď` je **ruční** běh, takže si nesáhne o denní rozpočet — za tím stojí člověk.
    @Test("Pustit teď spustí review a rozpočet nesáhne")
    func runNowSpendsNoBudget() async throws {
        let reviewer = FakeReviewRunner()
        let ledger = AutoRunLedger(layout: layout, time: FakeTimeSource(start: start))
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail(lines: 2790))),
            reviewer: reviewer,
            quietHours: awayFromNow(start),
            ledger: ledger
        )
        await store.refresh()
        await settle(store)
        #expect(store.deferral(of: pr) != nil)

        await store.runDeferredNow(pr)
        await settle(store)

        #expect(reviewer.requests.map(\.key.pullRequest) == [pr])
        #expect(await ledger.used() == 0)
        #expect(store.deferral(of: pr) == nil)
    }

    /// Dráha v tabu `Průběh` je jediné místo, kde se o odkladu dá dozvědět — bez ní by odložený
    /// běh vypadal k nerozeznání od toho, na který ještě nedošlo.
    @Test("Odložený běh je v Průběhu vidět jako vlastní stav dráhy")
    func theProgressTabShowsTheDeferral() async throws {
        let store = store(
            gateway: FakeGitHubGateway(always: .success([summary()]), detail: .success(detail(lines: 2790))),
            quietHours: awayFromNow(start)
        )
        await store.refresh()
        await settle(store)

        let lanes = Policy.lanes(
            of: store.timelines(for: pr),
            skills: store.reviewSkills(for: repo),
            deferred: store.deferral(of: pr)
        )
        let lane = try #require(lanes.first)
        #expect(lane.isDeferred)
        #expect(ReviewerLaneText.state(lane.state) == "odloženo na noc")
        #expect(lane.phases.map(\.title) == [ReviewerLane.Title.quiet])
    }
}
