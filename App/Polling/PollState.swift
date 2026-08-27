import Foundation

/// Odvozené otázky nad tím, co polling ví — proč je seznam prázdný a je zastaralý.
///
/// **Není to úložiště, je to hodnota** (#472). Do #472 tenhle typ držel `PollingService` jako
/// jedinou vlastnost `state`, a to znamenalo, že `@Observable` hlásil **jednu** změnu za všech
/// pět polí naráz: zápis `isRefreshing = true` na začátku tiku zneplatnil i každého, kdo četl
/// jen seznam PR — tedy `AppStore.author(of:)`, na kterém visí `ownership`, a s ním celý detail
/// PR. Naměřeno, že jedno takové zneplatnění stojí **33–43 ms** rozvržení okna
/// (`DetailRelayoutMeasurement`), a tik jich vyrábí několik.
///
/// Je to tatáž úvaha jako u `DiffViewport` (#469): `@Observable` sleduje **po vlastnostech**,
/// takže co se mění jinak často a čte jinde, patří do vlastní vlastnosti. `PollingService` proto
/// od #472 drží pět vlastností zvlášť a tenhle typ si skládá jen tam, kde se odpověď opravdu
/// počítá ze všech tří vstupů.
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
