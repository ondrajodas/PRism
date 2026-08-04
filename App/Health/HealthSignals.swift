import Foundation

/// Co o službě víme. Tři nezávislé signály, ze kterých `Policy` složí puntík.
///
/// Klíčové rozhodnutí #31: **nepollovat na to, co aplikace ví sama.** Polling se ptá `gh`
/// každou minutu a review pouští `claude` — každé takové volání je pravdivý zdravotní signál
/// a nestojí nic navíc. Syntetická sonda (`gh auth status` na timeru) je proti tomu *méně*
/// pravdivá: projde i tehdy, když skutečné volání selže na rate limitu nebo chybějícím scope
/// — a stojí spawn procesu a přístup do keychainu.
///
/// Status page je proti tomu druhý, doplňkový signál: sama o sobě nedokáže říct „funguje mi
/// to“, ale umí říct „oni mají incident“ — a to je právě ta informace, kterou z volání
/// nedostaneme.
struct HealthSignals: Sendable, Equatable {
    /// Jak dopadlo poslední **skutečné** volání služby. `nil` = žádné ještě neproběhlo.
    var lastCall: ServiceCall?
    /// Stav sledovaných komponent. `nil` = nezjištěno.
    var page: StatusPage?
    /// Kdy se stav služby naposledy zjišťoval — i tehdy, když to selhalo. Jde do nápovědy,
    /// protože puntík bez času kontroly neříká, jak stará ta odpověď je.
    var pageCheckedAt: Date?
    /// Proč se stav služby nepodařilo zjistit. `nil` = podařilo, nebo se to ještě nezkoušelo.
    ///
    /// Puntík to **nepřebíjí** — když skutečná volání procházejí, je zelená pravdivější než
    /// šedá. Zmlčet to ale nejde: bez téhle věty se „o incidentech nevíme“ nepozná od
    /// „žádný incident není“.
    var pageFailure: String?
    /// Má stroj cestu do sítě? `nil` = ještě nevíme.
    var isOnline: Bool?
}

/// Poslední skutečné volání služby.
struct ServiceCall: Sendable, Equatable {
    /// Odkdy tenhle výsledek platí — u úspěchu čas posledního povedeného volání,
    /// u selhání okamžik, **od kterého** se to nedaří.
    ///
    /// Je to schválně jedno pole se dvěma významy: druhý je to, co člověk potřebuje vědět
    /// („nedaří se od 14:12“, ne „naposledy zkoušeno ve 14:31“), a `PollState` ho drží
    /// z téhož důvodu.
    let since: Date
    /// Proč selhalo. `nil` = prošlo.
    let failure: String?

    var succeeded: Bool { failure == nil }

    init(since: Date, failure: String? = nil) {
        self.since = since
        self.failure = failure
    }
}
