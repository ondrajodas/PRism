import Foundation

/// Proč se nepovedlo mluvit s GitHubem.
///
/// Typované, ne řetězec: každý případ vede v UI jinam. `notAuthenticated` chce
/// `gh auth login`, `network` se sám spraví, `rateLimited` chce počkat a `commandFailed`
/// je něco, co jsme nečekali a je potřeba to ukázat celé.
enum GitHubError: Error, Equatable, Sendable {
    /// `gh` není přihlášený, nebo mu GitHub token odmítl.
    case notAuthenticated
    /// Vyčerpaný rate limit — primární i sekundární.
    case rateLimited(String)
    /// Na GitHub nešlo dosáhnout: síť, DNS, TLS, výpadek.
    case network(String)
    /// Repozitář nebo PR neexistuje, nebo na něj nevidíme.
    case notFound(String)
    /// `gh` nedoběhl v limitu.
    case timedOut
    /// Podproces `gh` se nepodařilo spustit ani doběhnout.
    case toolUnavailable(String)
    /// `gh` skončil nenulově z důvodu, který neumíme zařadit.
    case commandFailed(exitCode: Int32, message: String)
    /// `gh` doběhl v pořádku, ale jeho výstup nedává smysl.
    case malformedOutput(String)
}

extension GitHubError {
    /// Věta pro uživatele, i s detailem z `gh`.
    ///
    /// Text patří k typu ze stejného důvodu jako u `Tool`: kdo chybu vyrábí, ví nejlíp,
    /// co se stalo — a view pak nemá co skládat. Detail se drží u věty, protože bez něj
    /// se u poloviny případů nedá poznat, co dělat dál.
    var userDescription: String {
        switch self {
        case .notAuthenticated: "gh není přihlášený — spusť gh auth login."
        case .rateLimited(let detail): "GitHub omezuje dotazy. \(detail)"
        case .network(let detail): "GitHub není dostupný. \(detail)"
        case .notFound(let detail): "GitHub o tom neví. \(detail)"
        case .timedOut: "gh nedoběhl v limitu."
        case .toolUnavailable(let detail): "gh se nepodařilo spustit. \(detail)"
        case .commandFailed(let exitCode, let message): "gh skončil s kódem \(exitCode). \(message)"
        case .malformedOutput(let detail): "Výstupu gh nerozumím. \(detail)"
        }
    }

    /// Zařadí nenulový výsledek `gh` podle exit kódu a toho, co napsal na výstup.
    ///
    /// Exit kód rozliší jen chybějící přihlášení (`gh` na ně má vlastní čtyřku), zbytek se
    /// pozná z textu. Je to křehké — `gh` znění hlášek měnit může — ale je to jediné, co
    /// nabízí; proto je klasifikace čistá funkce a testuje se tabulkou skutečných výstupů.
    init(failure result: ProcessResult) {
        let message = result.failureText.isEmpty
            ? "gh skončil s kódem \(result.exitCode)."
            : result.failureText

        if result.exitCode == Self.authRequiredExitCode || Self.mentions(message, Self.authSignals) {
            self = .notAuthenticated
        } else if Self.mentions(message, Self.rateLimitSignals) {
            self = .rateLimited(message)
        } else if Self.mentions(message, Self.networkSignals) {
            self = .network(message)
        } else if Self.mentions(message, Self.notFoundSignals) {
            self = .notFound(message)
        } else {
            self = .commandFailed(exitCode: result.exitCode, message: message)
        }
    }

    /// `gh` končí čtyřkou, když příkaz potřebuje přihlášení a žádné není.
    private static let authRequiredExitCode: Int32 = 4

    private static let authSignals = ["gh auth login", "bad credentials", "http 401", "requires authentication"]
    private static let rateLimitSignals = ["rate limit"]
    private static let networkSignals = [
        "error connecting to",
        "check your internet connection",
        "no such host",
        "dial tcp",
        "connection refused",
        "network is unreachable",
        "tls handshake",
    ]
    private static let notFoundSignals = ["could not resolve to", "http 404", "not found"]

    private static func mentions(_ message: String, _ signals: [String]) -> Bool {
        let lowered = message.lowercased()
        return signals.contains { lowered.contains($0) }
    }
}
