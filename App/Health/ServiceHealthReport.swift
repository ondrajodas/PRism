import Foundation

/// Puntík u jedné služby a všechno, co k němu patří do nápovědy.
///
/// Skládá ho `Policy.health(of:from:)` jako čistou funkci, takže se texty testují bez UI.
/// View z toho jen udělá barvu a odstavec — časy formátuje samo, protože formát závisí na
/// locale a ten do `Policy` nepatří.
struct ServiceHealthReport: Sendable, Equatable, Identifiable {
    let service: MonitoredService
    let state: ServiceHealth

    /// Co se děje, celou větou. **Nikdy prázdné** — puntík, který po hoveru nic neřekne,
    /// je dekorace; je na to test.
    let reason: String

    /// Poslední skutečné volání, ať se v nápovědě ukáže, odkdy ten výsledek platí.
    let call: ServiceCall?

    /// Kdy se naposledy zjišťoval stav služby. `nil` = ještě nikdy.
    let checkedAt: Date?

    var id: MonitoredService { service }
}
