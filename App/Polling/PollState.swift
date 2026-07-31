import Foundation

/// Co polling ví — seznam PR a jak si stojí jeho čerstvost.
struct PollState: Sendable, Equatable {
    var pullRequests: [PullRequestSummary] = []
    var status: PollStatus = .notStarted
    /// Kdy naposledy dotaz prošel. `nil` znamená „ještě nikdy“ — seznam pak není starý,
    /// jen prázdný, a to je pro uživatele něco jiného.
    var lastSuccess: Date?

    /// Ukazujeme data, o kterých víme, že už nemusí platit?
    var isStale: Bool { lastSuccess != nil && status != .upToDate }
}

/// Jak dopadl poslední pokus o obnovení.
///
/// Rate limit je vlastní případ, ne obyčejné selhání: vede k jinému chování (backoff)
/// i k jiné větě v UI — „zkusím to v 14:32“ místo „nedaří se od 14:28“.
enum PollStatus: Sendable, Equatable {
    case notStarted
    case upToDate
    /// Od `since` se obnovení nedaří. Data mohou být starší, nebo žádná — to říká
    /// `lastSuccess`.
    case failing(since: Date, reason: GitHubError)
    /// GitHub nás odmítá kvůli rate limitu; dřív než v `retryAt` nemá smysl se ptát.
    case rateLimited(since: Date, retryAt: Date)
}
