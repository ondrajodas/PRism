import Foundation

/// Proč se nepovedlo připravit pracovní kopii.
///
/// Typované ze stejného důvodu jako u `GitHubError`: každý případ vede jinam.
/// `notAuthenticated` chce `gh auth login`, `network` se spraví sám. Text `gitu` se drží
/// u chyby, protože právě on je to, co se v řádku PR ukáže u stavu `checkoutFailed`.
enum CheckoutError: Error, Equatable, Sendable {
    case notAuthenticated(String)
    case network(String)
    /// Repozitář neexistuje — **nebo na něj nevidíme**. GitHub obojí schválně slévá do
    /// „Repository not found“, aby neprozradil, že privátní repo existuje. Není to tedy
    /// konečný stav: může znamenat chybějící oprávnění, se kterým se dá něco dělat.
    case repositoryNotFound(String)
    case timedOut
    case toolUnavailable(String)
    case gitFailed(exitCode: Int32, message: String)
}

extension CheckoutError {
    init(failure result: ProcessResult) {
        let message = result.failureText.isEmpty
            ? "git skončil s kódem \(result.exitCode)."
            : result.failureText

        if Self.mentions(message, Self.authSignals) {
            self = .notAuthenticated(message)
        } else if Self.mentions(message, Self.networkSignals) {
            self = .network(message)
        } else if Self.mentions(message, Self.notFoundSignals) {
            self = .repositoryNotFound(message)
        } else {
            self = .gitFailed(exitCode: result.exitCode, message: message)
        }
    }

    private static let authSignals = [
        "authentication failed",
        "could not read username",
        "could not read password",
        "terminal prompts disabled",
        "permission denied (publickey)",
        "403 forbidden",
    ]
    private static let networkSignals = [
        "could not resolve host",
        "failed to connect",
        "connection timed out",
        "network is unreachable",
        "connection refused",
        "ssl",
    ]
    private static let notFoundSignals = ["repository not found", "not found", "does not exist"]

    private static func mentions(_ message: String, _ signals: [String]) -> Bool {
        let lowered = message.lowercased()
        return signals.contains { lowered.contains($0) }
    }
}
