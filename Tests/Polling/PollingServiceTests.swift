import Foundation
import Testing

@testable import PRism

@Suite("PollingService")
@MainActor
struct PollingServiceTests {
    private let interval = Duration.seconds(60)
    private let sources = [
        Source(name: "Moje", query: "review-requested:@me is:open"),
        Source(name: "Tým", query: "team-review-requested:keboola/backend is:open"),
    ]

    private func summary(_ identifier: String, updatedAt: TimeInterval) -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    private func service(
        gateway: FakeGitHubGateway,
        time: FakeTimeSource,
        sources: [Source]? = nil
    ) -> PollingService {
        PollingService(
            gateway: gateway,
            sources: sources ?? self.sources,
            interval: interval,
            time: time
        )
    }

    // MARK: - Normální tik

    @Test("Tik se zeptá všech zdrojů a výsledky sloučí")
    func asksEverySourceAndMergesResults() async {
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1", updatedAt: 100)]),
            .success([summary("cli/go-gh#2", updatedAt: 200)]),
        ])
        let service = service(gateway: gateway, time: FakeTimeSource())

        await service.refresh()

        #expect(gateway.queries == sources.map(\.query))
        #expect(service.state.pullRequests.map(\.id.description) == ["cli/go-gh#2", "cli/cli#1"])
    }

    @Test("Po úspěchu je stav aktuální a nese čas")
    func successMarksStateUpToDate() async {
        let time = FakeTimeSource()
        let service = service(gateway: FakeGitHubGateway(always: .success([])), time: time)

        await service.refresh()

        #expect(service.state.status == .upToDate)
        #expect(service.state.lastSuccess == time.now)
        #expect(service.state.isStale == false)
    }

    @Test("Bez zdrojů je seznam prázdný, ne rozbitý")
    func noSourcesGiveEmptyList() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1", updatedAt: 100)]))
        let service = service(gateway: gateway, time: FakeTimeSource(), sources: [])

        await service.refresh()

        #expect(gateway.searchCount == 0)
        #expect(service.state.pullRequests.isEmpty)
        #expect(service.state.status == .upToDate)
    }

    @Test("Smyčka pollí v zadaném intervalu")
    func loopPollsOnInterval() async {
        let time = FakeTimeSource(stopAfter: 3)
        let gateway = FakeGitHubGateway(always: .success([]))

        await service(gateway: gateway, time: time).run()

        #expect(time.requestedSleeps == [interval, interval, interval])
        #expect(gateway.searchCount == sources.count * 3)
    }

    /// Kdy se zeptáme znovu, ukazuje dashboard (#181). Odhad `lastSuccess + interval` by po
    /// prvním rate limitu lhal, proto to zapisuje ta smyčka, která o čekání rozhodla.
    @Test("Smyčka řekne, kdy se zeptá znovu")
    func loopPublishesTheNextPoll() async {
        let time = FakeTimeSource(stopAfter: 1)
        let started = time.now

        let service = service(gateway: FakeGitHubGateway(always: .success([])), time: time)
        await service.run()

        #expect(service.state.nextPoll == started.addingTimeInterval(interval.seconds))
    }

    /// Před prvním usnutím se nemá co ukázat — a nula ani „za chvíli“ by o příštím tiku tvrdily
    /// něco, co se ještě nerozhodlo.
    @Test("Ruční obnovení příští tik neplánuje")
    func manualRefreshDoesNotScheduleTheNextPoll() async {
        let service = service(gateway: FakeGitHubGateway(always: .success([])), time: FakeTimeSource())

        await service.refresh()

        #expect(service.state.nextPoll == nil)
    }

    // MARK: - Probíhající dotaz

    /// Po dobu dotazu je `nextPoll` v minulosti, takže odpočet na dashboardu (#237) potřebuje
    /// vědět, že se ptáme — jinak by počítal přes nulu. Pozoruje se to zvenčí přes
    /// `afterSuccessfulTick`, který se volá **uvnitř** `refresh()`.
    @Test("Po dobu dotazu polling hlásí, že se ptá")
    func refreshAnnouncesItselfWhileAsking() async {
        let probe = FlagProbe()
        let service = service(gateway: FakeGitHubGateway(always: .success([])), time: FakeTimeSource())
        service.afterSuccessfulTick = { [weak service] _ in
            await MainActor.run { probe.duringTick = service?.state.isRefreshing }
        }

        await service.refresh()

        #expect(probe.duringTick == true)
        #expect(service.state.isRefreshing == false)
    }

    /// **Zaseknutý příznak je to horší selhání**: dashboard by pak psal „ptám se…“ navždycky
    /// a odpočet by se nikdy nevrátil — a to na obrazovce vypadá jako zaseknutá aplikace, ne
    /// jako chyba v pollingu. Proto se hlídají i větve, které do stavu nic nezapíšou.
    @Test("Po selhání ani po zrušení příznak nezůstane")
    func flagIsClearedOnEveryPath() async {
        let failing = service(
            gateway: FakeGitHubGateway(always: .failure(GitHubError.network("error connecting"))),
            time: FakeTimeSource()
        )
        await failing.refresh()
        #expect(failing.state.isRefreshing == false)

        let cancelled = service(
            gateway: FakeGitHubGateway(always: .failure(CancellationError())),
            time: FakeTimeSource()
        )
        await cancelled.refresh()
        #expect(cancelled.state.isRefreshing == false)
    }

    /// Mezi dvěma tiky se aplikace neptá, takže se dashboard vrátí k odpočtu.
    @Test("Mezi tiky se polling neptá")
    func flagIsClearedBetweenTicks() async {
        let time = FakeTimeSource(stopAfter: 2)
        let service = service(gateway: FakeGitHubGateway(always: .success([])), time: time)

        await service.run()

        #expect(service.state.isRefreshing == false)
    }

    // MARK: - Výpadek sítě

    @Test("Síťová chyba nezahodí poslední známá data")
    func networkFailureKeepsLastKnownData() async {
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1", updatedAt: 100)]),
            .success([]),
            .failure(GitHubError.network("error connecting to api.github.com")),
        ])
        let time = FakeTimeSource(stopAfter: 2)

        let service = service(gateway: gateway, time: time)
        await service.run()

        #expect(service.state.pullRequests.map(\.id.description) == ["cli/cli#1"])
        #expect(service.state.isStale)
    }

    @Test("Neaktuální stav řekne, odkdy se to nedaří a proč")
    func failureRecordsWhenAndWhy() async {
        let failure = GitHubError.network("error connecting to api.github.com")
        let time = FakeTimeSource()
        let service = service(gateway: FakeGitHubGateway(always: .failure(failure)), time: time)

        await service.refresh()

        #expect(service.state.status == .failing(since: time.now, reason: failure))
        #expect(service.state.lastSuccess == nil)
    }

    @Test("Opakované selhání nepřepíše čas, odkdy se to nedaří")
    func repeatedFailureKeepsTheOriginalTimestamp() async {
        let failure = GitHubError.network("error connecting to api.github.com")
        let time = FakeTimeSource(stopAfter: 3)
        let service = service(gateway: FakeGitHubGateway(always: .failure(failure)), time: time)
        let started = time.now

        await service.run()

        // Kdyby se `since` přepisovalo, ukazovalo by se pořád „neaktuální od teď“.
        #expect(service.state.status == .failing(since: started, reason: failure))
    }

    @Test("Po zotavení je stav zase aktuální")
    func recoversAfterFailure() async {
        // Selhávající tik spotřebuje jen jednu odpověď — u prvního zdroje se přeruší.
        let gateway = FakeGitHubGateway([
            .failure(GitHubError.network("error connecting to api.github.com")),
            .success([summary("cli/cli#1", updatedAt: 100)]),
            .success([]),
        ])
        let time = FakeTimeSource(stopAfter: 2)

        let service = service(gateway: gateway, time: time)
        await service.run()

        #expect(service.state.status == .upToDate)
        #expect(service.state.pullRequests.map(\.id.description) == ["cli/cli#1"])
        #expect(service.state.isStale == false)
    }

    @Test("Síťová chyba nespouští backoff")
    func networkFailureDoesNotBackOff() async {
        // Za výpadek sítě si aplikace nemůže — čekat déle by jen oddálilo zotavení.
        let failure = GitHubError.network("error connecting to api.github.com")
        let time = FakeTimeSource(stopAfter: 3)

        await service(gateway: FakeGitHubGateway(always: .failure(failure)), time: time).run()

        #expect(time.requestedSleeps == [interval, interval, interval])
    }

    @Test("Selhání jednoho zdroje zahodí celý tik")
    func partialFailureDiscardsTheWholeTick() async {
        // Publikovat jen to, co prošlo, by z okna nechalo zmizet PR z druhého zdroje —
        // vypadalo by to, že review už není potřeba.
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1", updatedAt: 100)]),
            .success([summary("cli/cli#2", updatedAt: 200)]),
            .success([summary("cli/cli#1", updatedAt: 100)]),
            .failure(GitHubError.network("error connecting to api.github.com")),
        ])
        let time = FakeTimeSource(stopAfter: 2)

        let service = service(gateway: gateway, time: time)
        await service.run()

        #expect(service.state.pullRequests.map(\.id.description) == ["cli/cli#2", "cli/cli#1"])
    }

    // MARK: - Rate limit

    @Test("Rate limit řekne, kdy se to zkusí znovu")
    func rateLimitPublishesRetryTime() async {
        let limited = GitHubError.rateLimited("HTTP 403: API rate limit exceeded")
        let time = FakeTimeSource()
        let service = service(gateway: FakeGitHubGateway(always: .failure(limited)), time: time)
        let hit = time.now

        await service.refresh()

        #expect(service.state.status == .rateLimited(since: hit, retryAt: hit.addingTimeInterval(120)))
    }

    @Test("Opakovaný rate limit čeká pokaždé déle")
    func rateLimitBacksOffExponentially() async {
        let limited = GitHubError.rateLimited("HTTP 403: API rate limit exceeded")
        let time = FakeTimeSource(stopAfter: 3)

        await service(gateway: FakeGitHubGateway(always: .failure(limited)), time: time).run()

        #expect(time.requestedSleeps == [.seconds(120), .seconds(240), .seconds(480)])
    }

    /// Příští tik musí ctít backoff, ne nastavený interval — jinak by dashboard slíbil dotaz
    /// za minutu ve chvíli, kdy se aplikace dvě minuty schválně neptá.
    @Test("Příští tik po rate limitu počítá s backoffem")
    func nextPollFollowsTheBackoff() async {
        let limited = GitHubError.rateLimited("HTTP 403: API rate limit exceeded")
        let time = FakeTimeSource(stopAfter: 1)
        let hit = time.now

        let service = service(gateway: FakeGitHubGateway(always: .failure(limited)), time: time)
        await service.run()

        #expect(service.state.nextPoll == hit.addingTimeInterval(120))
    }

    @Test("Backoff má strop, aby se polling neuspal na hodiny")
    func backoffIsCapped() async {
        let limited = GitHubError.rateLimited("HTTP 403: API rate limit exceeded")
        let time = FakeTimeSource(stopAfter: 8)

        await service(gateway: FakeGitHubGateway(always: .failure(limited)), time: time).run()

        #expect(time.requestedSleeps.last == .seconds(900))
    }

    @Test("Úspěch backoff zahodí")
    func successResetsBackoff() async {
        let limited = GitHubError.rateLimited("HTTP 403: API rate limit exceeded")
        let gateway = FakeGitHubGateway([
            .failure(limited),
            .success([]), .success([]),
            .failure(limited),
        ])
        let time = FakeTimeSource(stopAfter: 3)

        await service(gateway: gateway, time: time).run()

        // Třetí tik je zase první rate limit v řadě, ne pokračování toho prvního.
        #expect(time.requestedSleeps == [.seconds(120), interval, .seconds(120)])
    }

    // MARK: - Ruční obnovení a zrušení

    @Test("Ruční obnovení se nečeká na tik")
    func manualRefreshDoesNotWaitForTheNextTick() async {
        let gateway = FakeGitHubGateway(always: .success([]))
        let time = FakeTimeSource()

        await service(gateway: gateway, time: time).refresh()

        #expect(gateway.searchCount == sources.count)
        #expect(time.requestedSleeps.isEmpty)
    }

    @Test("Zrušení není chyba GitHubu a stav nepřepíše")
    func cancellationLeavesStateAlone() async {
        let gateway = FakeGitHubGateway(always: .failure(CancellationError()))
        let service = service(gateway: gateway, time: FakeTimeSource())

        await service.refresh()

        #expect(service.state.status == .notStarted)
    }
}

/// Kam si test odloží, co viděl **uprostřed** dotazu. Vlastní typ proto, že `@Sendable` closure
/// do lokální proměnné zapisovat nesmí; `@MainActor` proto, že stav pollingu je na hlavním
/// aktoru a bez toho by se z něj nedalo synchronně přečíst.
@MainActor
private final class FlagProbe {
    var duringTick: Bool?
}
