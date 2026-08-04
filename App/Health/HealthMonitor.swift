import Foundation
import Observation

/// Sleduje, jak se vede službám, na kterých aplikace stojí.
///
/// `@MainActor` a `@Observable` ze stejného důvodu jako `PollingService`: jeho stav je to,
/// co kreslí stavový řádek. Vlastní práce je jeden malý HTTP dotaz na službu za interval.
///
/// **Skutečná volání si nedrží sám** — bere si je závěrkou `lastCall`, kterou plní
/// `AppStore`. Držet je tady by znamenalo druhé místo, které se s `PollState` může rozejít,
/// a rozejít se v tomhle znamená svítit červeně nad funkčním GitHubem.
@MainActor
@Observable
final class HealthMonitor {
    /// Poslední kontrola stavu jedné služby.
    struct PageSignal: Sendable, Equatable {
        /// Naposledy přečtený stav komponent. Drží se i po selhané kontrole — deset minut
        /// starý stav je lepší odpověď než žádná, a `checkedAt` říká, jak starý je.
        var page: StatusPage?
        /// Proč se kontrola nepovedla. `nil` = povedla se.
        var failure: String?
        var checkedAt: Date
    }

    private(set) var pages: [MonitoredService: PageSignal] = [:]

    /// Má stroj cestu do sítě? `nil`, dokud se monitor sítě neozve.
    private(set) var isOnline: Bool?

    /// Je okno vidět?
    ///
    /// Když ne, **nekontroluje se nic** — aplikace na pozadí nemá komu svítit puntíkem.
    /// Nastavuje to okno, protože jinak by monitor musel znát `NSApplication`.
    var isWindowVisible = true

    /// Poslední skutečné volání služby. Plní `AppStore`; `nil` závěrka = nic o voláních nevíme.
    var lastCall: (@MainActor (MonitoredService) -> ServiceCall?)?

    private let statusPage: any StatusPageReading
    private let reachability: any NetworkReachability
    private let time: any TimeSource
    private let interval: Duration
    private let quickInterval: Duration

    /// Kdy skončilo poslední kolo kontrol. `nil` = žádné ještě neproběhlo.
    private var lastRound: Date?

    init(
        statusPage: any StatusPageReading = StatusPageClient(),
        reachability: any NetworkReachability = PathMonitorReachability(),
        time: any TimeSource = SystemTimeSource(),
        interval: Duration = .seconds(600),
        quickInterval: Duration = .seconds(60)
    ) {
        self.statusPage = statusPage
        self.reachability = reachability
        self.time = time
        self.interval = interval
        self.quickInterval = quickInterval
    }

    /// Signály jedné služby — složené z toho, co ví monitor, a z toho, co ví `AppStore`.
    func signals(for service: MonitoredService) -> HealthSignals {
        let signal = pages[service]
        return HealthSignals(
            lastCall: lastCall?(service),
            page: signal?.page,
            pageCheckedAt: signal?.checkedAt,
            pageFailure: signal?.failure,
            isOnline: isOnline
        )
    }

    func report(for service: MonitoredService) -> ServiceHealthReport {
        Policy.health(of: service, from: signals(for: service))
    }

    /// Puntíky v pořadí, ve kterém se kreslí.
    var reports: [ServiceHealthReport] {
        MonitoredService.allCases.map(report(for:))
    }

    /// Hlídá síť a v intervalu kontroluje stav služeb. Končí zrušením tasku.
    func run() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.watchNetwork() }
            group.addTask { await self.checkPeriodically() }
        }
    }

    /// Jedno kolo kontrol.
    func refresh() async {
        for service in MonitoredService.allCases {
            await check(service)
        }
        // Zrušené kolo se za proběhlé nevydává — jinak by po něm interval odtikával od
        // okamžiku, ve kterém se nic nezjistilo. Stejné pravidlo jako u `check(_:)`.
        guard !Task.isCancelled else { return }
        lastRound = time.now
    }

    private func watchNetwork() async {
        for await online in reachability.updates() {
            isOnline = online
        }
    }

    /// Budí se v krátkém taktu a kontroluje, až když je co kontrolovat.
    ///
    /// Uspat se rovnou na deset minut nejde: interval se **mění za běhu** (po selhaném
    /// volání se zkracuje) a okno se mezitím může vrátit do popředí. Uspání, které začalo,
    /// když bylo všechno v pořádku, by se o obojí nedozvědělo a puntík by nad selhaným
    /// voláním ukazoval deset minut starý stav služby. Alternativa — probudit spáče zvenčí
    /// — je continuation držená mezi voláními, nebo nestrukturovaný `Task`, který přežije
    /// zavření okna; probuzení jednou za takt nestojí nic a `refresh()` z něj vypadne hned.
    private func checkPeriodically() async {
        while !Task.isCancelled {
            if isDue { await refresh() }
            do {
                try await time.sleep(for: Self.tick)
            } catch {
                return
            }
        }
    }

    private var isDue: Bool {
        // Na pozadí se nekontroluje nic — a `lastRound` se proto neposouvá, takže se po
        // návratu do popředí zkontroluje hned.
        guard isWindowVisible else { return false }
        guard let lastRound else { return true }
        return time.now.timeIntervalSince(lastRound) >= currentInterval.seconds
    }

    /// Po selhaném skutečném volání se kontroluje častěji — právě tehdy chce člověk vědět,
    /// jestli je to na jeho straně.
    private var currentInterval: Duration {
        let failing = MonitoredService.allCases.contains { lastCall?($0)?.succeeded == false }
        return failing ? quickInterval : interval
    }

    private func check(_ service: MonitoredService) async {
        var signal = pages[service] ?? PageSignal(checkedAt: time.now)
        do {
            // `unchanged` (`304`) nechává `page` být — je to „platí, co jsi měl“, ne
            // „nic tam není“.
            if case .fetched(let page) = try await statusPage.read(service) {
                signal.page = page
            }
            signal.failure = nil
        } catch is CancellationError {
            // Zrušení není zjištění. Zapsat ho jako selhanou kontrolu by po zavření okna
            // nechalo v nápovědě hlášku o nedostupné status page.
            return
        } catch let error as StatusPageError {
            signal.failure = error.userDescription
        } catch {
            signal.failure = StatusPageError.unreachable(error.localizedDescription).userDescription
        }
        signal.checkedAt = time.now
        pages[service] = signal
    }

    /// Jak často se monitor probouzí. Nezaměňovat s intervalem kontroly — viz
    /// `checkPeriodically()`.
    private static let tick = Duration.seconds(30)
}
