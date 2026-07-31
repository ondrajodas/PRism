import Foundation

/// Výsledek doběhnutého podprocesu.
struct ProcessResult: Sendable, Equatable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

enum ProcessError: Error, Equatable {
    /// Binárku se nepodařilo spustit — chybí, není spustitelná, nebo ji odmítl systém.
    case launchFailed(String)
    /// Proces nedoběhl v limitu a byl zabit.
    case timedOut
}

/// Spuštění podprocesu. Za protokolem, aby preflight i moduly nad ním šly testovat bez
/// skutečných binárek.
///
/// Umí jen „spusť, počkej, seber výstup". `ReviewRunner` bude potřebovat výstup po řádcích
/// tak, jak vzniká (`stream-json`) — to přijde jako samostatná metoda, tahle se tím
/// nemění.
protocol ProcessRunning: Sendable {
    func run(_ executable: URL, arguments: [String], timeout: Duration) async throws -> ProcessResult
}
