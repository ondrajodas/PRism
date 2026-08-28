import Foundation
import Observation

/// Drží seznam PR aktuální — v intervalu se ptá všech zdrojů a publikuje výsledek.
///
/// `@MainActor` a `@Observable`, protože jeho stav je to, co kreslí okno; síťová práce
/// stejně probíhá v podprocesech `gh`, takže na hlavním vlákně nic nedrží.
@MainActor
@Observable
final class PollingService {
    // **Pět vlastností, ne jeden `PollState`** (#472). `@Observable` sleduje po vlastnostech,
    // takže jedna hrubá vlastnost znamená jedno zneplatnění za všech pět hodnot — a `isRefreshing`
    // se mění dvakrát za tik, kdežto seznam skoro nikdy. Rozbor a čísla jsou v `PollState`.

    /// Seznam PR z posledního úspěšného tiku. Čte ho okno i `AppStore.author(of:)`, na kterém
    /// visí `ownership(of:)` — tedy i to, čí PR detail kreslí.
    private(set) var pullRequests: [PullRequestSummary] = []

    /// Jak dopadl poslední pokus o obnovení.
    private(set) var status: PollStatus = .notStarted

    /// Kdy naposledy dotaz prošel. `nil` znamená „ještě nikdy“ — seznam pak není starý,
    /// jen prázdný, a to je pro uživatele něco jiného.
    private(set) var lastSuccess: Date?

    /// Kdy se smyčka zeptá znovu (#181). `nil`, dokud poprvé neusne.
    ///
    /// Ukládá to **smyčka**, ne odhad ve view: interval se dá změnit v nastavení a při rate
    /// limitu ho přebíjí backoff, takže `lastSuccess + interval` by po prvním odmítnutí lhalo.
    /// Ruční obnovení tuhle hodnotu **neposouvá** — tik mimo pořadí smyčku nepřeplánuje.
    private(set) var nextPoll: Date?

    /// Ptáme se právě teď? (#237)
    ///
    /// Drží to **odpočet na dashboardu**: `nextPoll` zůstává v minulosti po celou dobu dotazu
    /// (zapisuje ho smyčka až po `refresh()`), takže by odpočet došel na nulu a šel dál —
    /// a samotné srovnání s hodinami to nezachrání, protože odpočet tiká **bez přepočtu view**.
    /// Změna tohohle příznaku je naopak observovatelná, takže okno na ni sáhne ve chvíli, kdy
    /// se to stane, a napíše, co se děje, místo čísla, které už neplatí.
    private(set) var isRefreshing = false

    /// Ukazujeme data, o kterých víme, že už nemusí platit?
    ///
    /// **Bez seznamu**, ačkoli by se `PollState` dal složit celý: čtenář téhle otázky by se tím
    /// svázal i s `pullRequests`, a to je přesně ta hrubost, kterou #472 odstraňovalo.
    var isStale: Bool { PollState(status: status, lastSuccess: lastSuccess).isStale }

    /// Proč je seznam prázdný — `nil`, když prázdný není. Tady se seznam čte, protože otázka
    /// na něm doopravdy stojí.
    var emptyReason: PollEmptyReason? {
        PollState(pullRequests: pullRequests, status: status, lastSuccess: lastSuccess).emptyReason
    }

    private let gateway: any GitHubGateway
    /// Mění je reload konfigurace, takže nejsou `let`.
    var sources: [Source]
    var interval: Duration
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
            let wait = waitBeforeNextPoll()
            // Zapisuje se **tady**, ne v `refresh()`: rozhoduje o tom čekání, které se právě
            // spočítalo, a to zná jenom smyčka.
            nextPoll = time.now.addingTimeInterval(wait.seconds)
            do {
                try await time.sleep(for: wait)
            } catch {
                return
            }
        }
    }

    /// Jeden cyklus. Volá se i z tlačítka „obnovit teď“ — ruční obnovení není nic jiného
    /// než tik mimo pořadí.
    ///
    /// Po celou dobu dotazu hlásí `isRefreshing` (#237). Klidně by to šlo spočítat
    /// z `nextPoll` a hodin, ale jen ve chvíli, kdy se view přepočítává — a odpočet na
    /// dashboardu tiká právě bez toho.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let results = try await resultsBySource()
            // **Bez `if` na rovnost, a je to změřené** (#472). Nabízí se psát
            // `if pullRequests != merged { … }`, jenže `@Observable` **sám nehlásí zápis téže
            // hodnoty** (ověřeno vloženou regresí i tvrzením v `PollObservationTests`), takže by
            // to bylo porovnání navíc, které nic nemění. Co tichý tik doopravdy zneplatňovalo,
            // byla **hrubost** sledované vlastnosti: do #472 bylo všech pět hodnot jedním
            // `PollState`em, takže `isRefreshing = true` probudilo i čtenáře seznamu.
            pullRequests = PullRequestList.merged(from: results)
            status = .upToDate
            lastSuccess = time.now
            rateLimitStreak = 0
            // Uvnitř `refresh()` schválně, ne ve smyčce: ruční obnovení je tik mimo
            // pořadí a má uklidit stejně jako ten pravidelný.
            await afterSuccessfulTick?(pullRequests)
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
            status = .rateLimited(
                since: failingSince,
                retryAt: time.now.addingTimeInterval(backoff().seconds)
            )
        } else {
            rateLimitStreak = 0
            status = .failing(since: failingSince, reason: reason)
        }
    }

    /// Odkdy se to nedaří. Při opakovaném selhání se razítko drží — jinak by v UI pořád
    /// stálo „neaktuální od teď“ a nešlo by poznat, jak dlouho výpadek trvá.
    private var failingSince: Date {
        switch status {
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
