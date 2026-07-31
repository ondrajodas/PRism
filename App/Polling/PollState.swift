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

    /// Proč je seznam prázdný — `nil`, když prázdný není.
    ///
    /// Rozhodnutí patří sem, ne do view: „prázdno, protože nic není“ a „prázdno, protože
    /// se to nepovedlo načíst“ vypadají v okně stejně, ale znamenají opak. Bez tohohle
    /// místa by se u chybové hlášky svítilo zelené „Žádné PR k review“.
    var emptyReason: PollEmptyReason? {
        guard pullRequests.isEmpty else { return nil }

        // Když už se to jednou povedlo, je prázdno prostě prázdno — že se obnovení
        // zrovna nedaří, říká banner nad seznamem.
        guard lastSuccess == nil else {
            return status == .notStarted ? .loading : .noPullRequests
        }

        return switch status {
        case .notStarted: .loading
        case .upToDate: .noPullRequests
        case .failing(_, let reason): .failure(reason)
        case .rateLimited(_, let retryAt): .rateLimited(retryAt: retryAt)
        }
    }
}

/// Co ukázat místo seznamu, když v něm nic není.
enum PollEmptyReason: Sendable, Equatable {
    case loading
    case noPullRequests
    case failure(GitHubError)
    case rateLimited(retryAt: Date)
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
