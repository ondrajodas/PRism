import Foundation
import Observation

/// Drží seznam PR aktuální — v intervalu se ptá všech zdrojů a publikuje výsledek.
///
/// `@MainActor` a `@Observable`, protože jeho stav je to, co kreslí okno; síťová práce
/// stejně probíhá v podprocesech `gh`, takže na hlavním vlákně nic nedrží.
@MainActor
@Observable
final class PollingService {
    private(set) var state = PollState()

    private let gateway: any GitHubGateway
    private let sources: [Source]
    private let interval: Duration
    private let time: any TimeSource

    /// Kolikátý rate limit v řadě to je. Nula znamená, že poslední pokus prošel.
    private var rateLimitStreak = 0

    /// Zavolá se po **úspěšném** tiku, i po tom, který nic nevrátil. Věší se sem úklid
    /// cache: prázdná odpověď je informace (PR zmizelo ze seznamu), ale **selhaná není** —
    /// po výpadku sítě zůstane `pullRequests` beze změny, a při prvním tiku po startu je
    /// prázdný. Uklízet po něm by znamenalo smazat celou cache kvůli chvíli bez sítě.
    var afterSuccessfulTick: (@Sendable ([PullRequestSummary]) async -> Void)?

    init(
        gateway: any GitHubGateway,
        sources: [Source] = [.reviewRequested],
        interval: Duration = .seconds(60),
        time: any TimeSource = SystemTimeSource()
    ) {
        self.gateway = gateway
        self.sources = sources
        self.interval = interval
        self.time = time
    }

    /// Obnovit, počkat, opakovat. Končí zrušením tasku — `sleep` na něj vyhodí chybu.
    func run() async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await time.sleep(for: waitBeforeNextPoll())
            } catch {
                return
            }
        }
    }

    /// Jeden cyklus. Volá se i z tlačítka „obnovit teď“ — ruční obnovení není nic jiného
    /// než tik mimo pořadí.
    func refresh() async {
        do {
            let results = try await resultsBySource()
            state.pullRequests = PullRequestList.merged(from: results)
            state.status = .upToDate
            state.lastSuccess = time.now
            rateLimitStreak = 0
            // Uvnitř `refresh()` schválně, ne ve smyčce: ruční obnovení je tik mimo
            // pořadí a má uklidit stejně jako ten pravidelný.
            await afterSuccessfulTick?(state.pullRequests)
        } catch is CancellationError {
            // Zrušení není chyba GitHubu. Publikovat ho jako selhání by uživateli tvrdilo,
            // že něco spadlo, zatímco jsme jen skončili.
        } catch {
            guard !Task.isCancelled else { return }
            recordFailure(error)
        }
    }

    /// Zdroje se ptají postupně a **selhání kteréhokoli zahodí celý tik**. Publikovat jen
    /// to, co prošlo, by z okna nechalo zmizet PR ze zbylých zdrojů — a zmizelý PR vypadá
    /// jako vyřízený.
    private func resultsBySource() async throws -> [[PullRequestSummary]] {
        var results: [[PullRequestSummary]] = []
        for source in sources {
            results.append(try await gateway.searchPullRequests(query: source.query))
        }
        return results
    }

    private func recordFailure(_ error: any Error) {
        let reason = error as? GitHubError ?? .commandFailed(exitCode: -1, message: "\(error)")

        if case .rateLimited = reason {
            rateLimitStreak += 1
            state.status = .rateLimited(
                since: failingSince,
                retryAt: time.now.addingTimeInterval(backoff().seconds)
            )
        } else {
            rateLimitStreak = 0
            state.status = .failing(since: failingSince, reason: reason)
        }
    }

    /// Odkdy se to nedaří. Při opakovaném selhání se razítko drží — jinak by v UI pořád
    /// stálo „neaktuální od teď“ a nešlo by poznat, jak dlouho výpadek trvá.
    private var failingSince: Date {
        switch state.status {
        case .failing(let since, _), .rateLimited(let since, _): since
        case .notStarted, .upToDate: time.now
        }
    }

    private func waitBeforeNextPoll() -> Duration {
        rateLimitStreak > 0 ? backoff() : interval
    }

    /// Zdvojnásobení za každý rate limit v řadě, se stropem.
    ///
    /// Backoff je jen pro rate limit: ten si aplikace způsobila sama tím, že se ptá moc.
    /// Za výpadek sítě nemůže, a čekat kvůli němu déle by jen oddálilo zotavení.
    private func backoff() -> Duration {
        let multiplier = 1 << min(rateLimitStreak, Self.maxBackoffDoublings)
        return min(interval * multiplier, Self.maxBackoff)
    }

    private static let maxBackoff = Duration.seconds(900)
    private static let maxBackoffDoublings = 16
}
