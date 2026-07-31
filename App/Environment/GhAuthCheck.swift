import Foundation

/// Stav přihlášení `gh`.
enum GhAuthState: Sendable, Equatable {
    case loggedIn
    /// `gh` běží, ale není přihlášený. Řeší `gh auth login`.
    case loggedOut
    /// Stav se nepodařilo zjistit — `gh` nešlo spustit, spadlo jinak, nebo nedoběhlo.
    /// Drží text chyby, aby bylo co ukázat.
    case checkFailed(String)
}

/// Zjistí, jestli je `gh` přihlášený.
///
/// Aplikace nikdy nedrží GitHub token — jen se `gh` zeptá, jak si stojí; credential zůstává
/// v jeho keychainu. `gh auth status` vrací 0 když přihlášený, 1 když ne.
struct GhAuthCheck: Sendable {
    private let runner: ProcessRunning
    private let timeout: Duration

    init(runner: ProcessRunning, timeout: Duration = .seconds(15)) {
        self.runner = runner
        self.timeout = timeout
    }

    func check(gh: URL) async -> GhAuthState {
        let result: ProcessResult
        do {
            result = try await runner.run(gh, arguments: ["auth", "status"], timeout: timeout)
        } catch ProcessError.timedOut {
            return .checkFailed("gh auth status nedoběhl do \(timeout.components.seconds) s.")
        } catch ProcessError.launchFailed(let detail) {
            return .checkFailed(detail)
        } catch {
            return .checkFailed(error.localizedDescription)
        }

        switch result.exitCode {
        case 0: return .loggedIn
        case 1: return .loggedOut
        default: return .checkFailed(Self.message(from: result))
        }
    }

    private static func message(from result: ProcessResult) -> String {
        let text = result.failureText
        return text.isEmpty ? "gh auth status skončil s kódem \(result.exitCode)." : text
    }
}
