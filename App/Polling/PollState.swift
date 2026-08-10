import Foundation

/// Co polling ví — seznam PR a jak si stojí jeho čerstvost.
struct PollState: Sendable, Equatable {
    var pullRequests: [PullRequestSummary] = []
    var status: PollStatus = .notStarted
    /// Kdy naposledy dotaz prošel. `nil` znamená „ještě nikdy“ — seznam pak není starý,
    /// jen prázdný, a to je pro uživatele něco jiného.
    var lastSuccess: Date?
    /// Kdy se smyčka zeptá znovu (#181). `nil`, dokud poprvé neusne.
    ///
    /// Ukládá to **smyčka**, ne odhad ve view: interval se dá změnit v nastavení a při rate
    /// limitu ho přebíjí backoff, takže `lastSuccess + interval` by po prvním odmítnutí lhalo.
    /// Ruční obnovení tuhle hodnotu **neposouvá** — tik mimo pořadí smyčku nepřeplánuje.
    var nextPoll: Date?
    /// Ptáme se právě teď? (#237)
    ///
    /// Drží to **odpočet na dashboardu**: `nextPoll` zůstává v minulosti po celou dobu dotazu
    /// (zapisuje ho smyčka až po `refresh()`), takže by odpočet došel na nulu a šel dál —
    /// a samotné srovnání s hodinami to nezachrání, protože odpočet tiká **bez přepočtu view**.
    /// Změna tohohle příznaku je naopak observovatelná, takže okno na ni sáhne ve chvíli, kdy
    /// se to stane, a napíše, co se děje, místo čísla, které už neplatí.
    var isRefreshing = false

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
