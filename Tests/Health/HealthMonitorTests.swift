import Foundation
import Testing

@testable import PRism

@Suite("HealthMonitor — sledování dostupnosti služeb")
@MainActor
struct HealthMonitorTests {
    private static let operational = StatusPage.watching(["API Requests": "operational"])
    private static let outage = StatusPage.watching(["API Requests": "major_outage"])

    @Test("Kolo kontrol se zeptá obou služeb a stav se propíše do puntíků")
    func refreshFillsReports() async {
        let statusPage = FakeStatusPage(.success(.fetched(Self.outage)))
        let monitor = HealthMonitor(statusPage: statusPage, reachability: FakeReachability(), time: FakeTimeSource())

        await monitor.refresh()

        #expect(Set(statusPage.reads) == Set(MonitoredService.allCases))
        #expect(monitor.reports.map(\.state) == [.incident, .incident])
        #expect(monitor.reports.map(\.service) == MonitoredService.allCases)
    }

    @Test("Skutečná volání si monitor nedrží — bere si je závěrkou")
    func realCallsComeFromOutside() async {
        let time = FakeTimeSource()
        let monitor = HealthMonitor(
            statusPage: FakeStatusPage(.success(.fetched(Self.operational))),
            reachability: FakeReachability(),
            time: time
        )
        monitor.lastCall = { service in
            service == .github ? ServiceCall(since: time.now) : ServiceCall(since: time.now, failure: "spadlo")
        }

        await monitor.refresh()

        #expect(monitor.report(for: .github).state == .operational)
        #expect(monitor.report(for: .claude).state == .failing)
    }

    @Test("Nezměněná stránka (304) nechává poslední známý stav být")
    func unchangedKeepsPage() async {
        let statusPage = FakeStatusPage([
            .github: [.success(.fetched(Self.outage)), .success(.unchanged)],
            .claude: [.success(.unchanged)],
        ])
        let monitor = HealthMonitor(statusPage: statusPage, reachability: FakeReachability(), time: FakeTimeSource())

        await monitor.refresh()
        await monitor.refresh()

        // `304` znamená „platí, co jsi měl“. Kdo si to splete s prázdnou stránkou, ten po
        // prvním nezměněném dotazu zhasne puntík.
        #expect(monitor.report(for: .github).state == .incident)
    }

    @Test("Selhaná kontrola nechá starý stav, ale přizná se")
    func failedCheckKeepsPreviousPage() async {
        let statusPage = FakeStatusPage([
            .github: [.success(.fetched(Self.outage)), .failure(StatusPageError.badStatus(503))],
            .claude: [.success(.unchanged)],
        ])
        let time = FakeTimeSource()
        let monitor = HealthMonitor(statusPage: statusPage, reachability: FakeReachability(), time: time)

        await monitor.refresh()
        let firstCheck = monitor.report(for: .github).checkedAt
        try? await time.sleep(for: .seconds(600))
        await monitor.refresh()

        let report = monitor.report(for: .github)
        // Deset minut starý stav je lepší odpověď než žádná — a `checkedAt` říká, jak starý je.
        #expect(report.state == .incident)
        #expect(report.reason.contains("odpověděla 503"))
        #expect(report.checkedAt != firstCheck)
    }

    @Test("Povedená kontrola smaže hlášku po předchozím selhání")
    func successClearsFailure() async {
        let statusPage = FakeStatusPage([
            .github: [.failure(StatusPageError.unreachable("offline")), .success(.fetched(Self.operational))],
            .claude: [.success(.unchanged)],
        ])
        let monitor = HealthMonitor(statusPage: statusPage, reachability: FakeReachability(), time: FakeTimeSource())

        await monitor.refresh()
        #expect(monitor.signals(for: .github).pageFailure != nil)

        await monitor.refresh()
        #expect(monitor.signals(for: .github).pageFailure == nil)
    }

    @Test("Zrušená kontrola se nezapíše jako selhaná")
    func cancellationIsNotAFailure() async {
        let statusPage = FakeStatusPage(.failure(CancellationError()))
        let monitor = HealthMonitor(statusPage: statusPage, reachability: FakeReachability(), time: FakeTimeSource())

        await monitor.refresh()

        // Jinak by po zavření okna zůstala v nápovědě hláška o nedostupné status page.
        #expect(monitor.signals(for: .github).pageFailure == nil)
        #expect(monitor.signals(for: .github).pageCheckedAt == nil)
    }

    @Test("Stav sítě přiteče z monitoru a přebije všechno ostatní")
    func reachabilityDrivesOffline() async throws {
        let reachability = FakeReachability([false])
        let monitor = HealthMonitor(
            statusPage: FakeStatusPage(.success(.fetched(Self.operational))),
            reachability: reachability,
            time: FakeTimeSource(stopAfter: 1)
        )
        monitor.lastCall = { _ in ServiceCall(since: Date(timeIntervalSince1970: 1_000_000)) }

        let task = Task { await monitor.run() }
        while monitor.isOnline == nil { try await Self.pause() }

        #expect(monitor.reports.allSatisfy { $0.state == .offline })

        reachability.send(true)
        while monitor.isOnline != true { try await Self.pause() }
        // Kolo se dožaduje výslovně, ne přes smyčku monitoru: `FakeTimeSource` neuspává,
        // takže na pořadí, ve kterém plánovač pustí obě větve `run()`, není spoleh.
        await monitor.refresh()
        #expect(monitor.reports.allSatisfy { $0.state == .operational })

        task.cancel()
        await task.value
    }

    @Test("Když okno není vidět, nekontroluje se nic")
    func nothingIsCheckedWhileHidden() async throws {
        let statusPage = FakeStatusPage(.success(.fetched(Self.operational)))
        let time = FakeTimeSource(stopAfter: 4)
        let monitor = HealthMonitor(statusPage: statusPage, reachability: FakeReachability(), time: time)
        monitor.isWindowVisible = false

        try await run(monitor, until: time, sleeps: 4)

        // Aplikace na pozadí nemá komu svítit puntíkem — a HTTP dotaz za nic je zbytečný.
        #expect(statusPage.reads.isEmpty)
    }

    @Test("Skryté okno interval neposouvá, takže po návratu se zkontroluje hned")
    func hiddenWindowDoesNotSpendTheInterval() async throws {
        let statusPage = FakeStatusPage(.success(.fetched(Self.operational)))
        // Tři takty naslepo (90 s) a pak jeden po návratu okna. Kdyby skryté okno interval
        // posouvalo, druhá smyčka by se dívala na uplynulých 90 s z deseti minut a nesáhla
        // by na status page vůbec.
        let time = FakeTimeSource(stopAfter: 3)
        let monitor = HealthMonitor(statusPage: statusPage, reachability: FakeReachability(), time: time)
        monitor.isWindowVisible = false

        // Dvě smyčky za sebou, ne přepnutí za běhu: `FakeTimeSource` neuspává, takže smyčka
        // dojede celá při první odmlce testu a přepnout ji uprostřed by byl závod.
        try await run(monitor, until: time, sleeps: 3)
        #expect(statusPage.reads.isEmpty)

        monitor.isWindowVisible = true
        // Čtvrté uspání je to, na kterém `FakeTimeSource` smyčku ukončí — takže druhý běh
        // je právě jedno kolo.
        try await run(monitor, until: time, sleeps: 4)

        #expect(statusPage.reads == MonitoredService.allCases)
    }

    /// Pustí smyčku, počká na daný počet uspání a uklidí ji.
    ///
    /// Zrušení je potřeba i po vyčerpaných uspáních: kontrola stavu skončí sama, ale hlídání
    /// sítě běží dál, takže `run()` bez něj nevrátí. Čeká se v smyčce bez horní hranice —
    /// test, který se nedočká, uvízne, a to je srozumitelnější než náhodné padání.
    private func run(_ monitor: HealthMonitor, until time: FakeTimeSource, sleeps: Int) async throws {
        let task = Task { await monitor.run() }
        while time.requestedSleeps.count < sleeps { try await Self.pause() }
        task.cancel()
        await task.value
    }

    /// Krátká odmlka, **ne `Task.yield()`**.
    ///
    /// Suita je `@MainActor` a Swift Testing pouští suity paralelně, takže spin bez odmlky
    /// vyhladoví testy, které čekají na skutečné procesy — změřeno na `SubprocessStreamerTests`,
    /// kde se zabíjený proces nestihl zabít dřív, než mu doběhl `sleep 1`. Tatáž lekce jako
    /// u `ReviewSubmission`.
    private static func pause() async throws {
        try await Task.sleep(for: .milliseconds(1))
    }

    @Test("Ve výchozím stavu se kontroluje po deseti minutách")
    func defaultIntervalIsTenMinutes() async throws {
        let statusPage = FakeStatusPage(.success(.fetched(Self.operational)))
        // Takt je 30 s, takže 21 uspání je 630 s — právě tak, aby druhé kolo padlo dovnitř.
        let time = FakeTimeSource(stopAfter: 21)
        let monitor = HealthMonitor(statusPage: statusPage, reachability: FakeReachability(), time: time)

        try await run(monitor, until: time, sleeps: 21)

        #expect(statusPage.reads.count == 2 * MonitoredService.allCases.count)
    }

    @Test("Po selhaném volání se kontroluje častěji")
    func failedCallShortensTheInterval() async throws {
        let statusPage = FakeStatusPage(.success(.fetched(Self.operational)))
        let time = FakeTimeSource(stopAfter: 5)
        let monitor = HealthMonitor(statusPage: statusPage, reachability: FakeReachability(), time: time)
        // Právě tehdy chce člověk vědět, jestli je to na jeho straně — čekat deset minut
        // s odpovědí „oni, nebo já?“ je to nejmíň užitečné, co může řádek udělat.
        monitor.lastCall = { _ in ServiceCall(since: Date(timeIntervalSince1970: 1_000_000), failure: "spadlo") }

        try await run(monitor, until: time, sleeps: 5)

        // 150 s při zkráceném intervalu 60 s = tři kola; s desetiminutovým by bylo jedno.
        #expect(statusPage.reads.count == 3 * MonitoredService.allCases.count)
    }

    @Test("Kontrola jde jen do sledovaných služeb a v jejich pořadí")
    func checksEveryServiceOnce() async {
        let statusPage = FakeStatusPage(.success(.unchanged))
        let monitor = HealthMonitor(statusPage: statusPage, reachability: FakeReachability(), time: FakeTimeSource())

        await monitor.refresh()

        #expect(statusPage.reads == MonitoredService.allCases)
    }
}
