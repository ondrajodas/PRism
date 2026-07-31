import Foundation

/// Čas a čekání jako závislost, ne jako globální fakt.
///
/// Patří sem, protože hodiny a uspání jsou přístup ke stroji — stejná kategorie jako
/// hledání binárek nebo spouštění podprocesů. Za protokolem proto, že bez toho by testy
/// pollingu musely reálně čekat minuty a backoff by se ověřit nedal vůbec.
///
/// Není to `Swift.Clock`: ten popisuje vlastní typ okamžiku a monotónní čas, kdežto tady
/// jde o dvě věci — razítko, které se ukáže uživateli (`Date`), a uspání, které jde
/// v testu přeskočit.
protocol TimeSource: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

extension Duration {
    /// `Duration` počítá v sekundách a attosekundách, `Date` v `TimeInterval` — tohle je
    /// jediné místo, kde se to převádí.
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
    }
}

/// Skutečné hodiny.
struct SystemTimeSource: TimeSource {
    var now: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
