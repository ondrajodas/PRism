import Foundation
import Observation

/// Stav aplikace, který kreslí okno.
///
/// Drží polling seznamu PR, výběr řádku a stav pracovních kopií. Výběr žije tady, ne ve
/// view — jinak by ho každé přestavění seznamu zahodilo. Postupně sem přibude stav
/// běžících review a limit souběžných session.
@MainActor
@Observable
final class AppStore {
    /// Který řádek je vybraný.
    var selection: PRIdentifier?

    /// Stav pracovní kopie **per repo**. Co v mapě není, v cache není.
    ///
    /// Jediný zdroj pravdy o checkoutu: `ReviewState` pro řádek se z něj odvozuje
    /// (`Policy.reviewState(for:)`) a `busy` pro eviction taky. Dvě mapy s různými klíči
    /// si dokázaly odporovat — jedno PR hlásilo selhání nad klonem, který mezitím pro
    /// druhé PR téhož repa v pořádku vznikl.
    private(set) var checkoutStates: [RepoID: CheckoutState] = [:]

    private let polling: PollingService
    private let checkout: (any RepoCheckout)?

    init(
        gateway: any GitHubGateway,
        sources: [Source] = [.reviewRequested],
        interval: Duration = .seconds(60),
        time: any TimeSource = SystemTimeSource(),
        eviction: CacheEviction? = nil,
        checkout: (any RepoCheckout)? = nil
    ) {
        polling = PollingService(gateway: gateway, sources: sources, interval: interval, time: time)
        self.checkout = checkout
        polling.afterSuccessfulTick = { [weak self] summaries in
            await self?.forget(whatIsNotIn: summaries)
            // `busy` se nepředává jako snímek, ale jako dotaz: eviction je dlouhá disková
            // operace a příprava, která začne uprostřed ní, by jinak přišla o ochranu.
            let busy: @Sendable () async -> Set<RepoID> = { [weak self] in
                await self?.busyRepositories ?? []
            }
            try? await eviction?.run(openPullRequests: summaries.map(\.id), busy: busy)
        }
    }

    /// Sestavení z toho, co našel preflight. Absolutní cesta k `gh` je jediné, co gateway
    /// potřebuje — token si drží `gh` sám.
    convenience init(toolPaths: ToolPaths) {
        let runner = SubprocessRunner()
        let checkout = GitRepoCheckout(git: toolPaths.git, gh: toolPaths.gh, runner: runner)
        self.init(
            gateway: GhGateway(gh: toolPaths.gh, runner: runner),
            eviction: CacheEviction(checkout: checkout),
            checkout: checkout
        )
    }

    var pullRequests: [PullRequestSummary] { polling.state.pullRequests }
    var status: PollStatus { polling.state.status }
    var lastSuccess: Date? { polling.state.lastSuccess }
    var isStale: Bool { polling.state.isStale }
    var emptyReason: PollEmptyReason? { polling.state.emptyReason }

    /// Drží seznam aktuální, dokud okno žije. Zrušení tasku smyčku ukončí.
    func keepFresh() async {
        await polling.run()
    }

    /// Tlačítko „obnovit teď“ — tik mimo pořadí.
    func refresh() async {
        await polling.refresh()
    }

    /// Repa, se kterými se právě pracuje — odvozeno ze stavu, ne vedené zvlášť. Množina
    /// s ručním `insert`/`remove` by u dvou souběžných příprav téhož repa sundala ochranu
    /// při první, která doběhne.
    var busyRepositories: Set<RepoID> {
        Set(checkoutStates.filter { $0.value == .preparing }.keys)
    }

    func checkoutState(for repo: RepoID) -> CheckoutState {
        checkoutStates[repo] ?? .absent
    }

    func reviewState(for pr: PRIdentifier) -> ReviewState {
        Policy.reviewState(for: checkoutState(for: pr.repo))
    }

    /// Připraví pracovní kopii repa. Slouží i jako „zkusit znovu“ po selhání — příprava
    /// je idempotentní, takže opakování je totéž volání.
    ///
    /// Po úspěchu se stav vrací na `notStarted`: `ReviewState` popisuje **review**, a to
    /// se ještě nespustilo. Že je kopie připravená, ukazuje detail, ne odznak v řádku.
    func prepareCheckout(for pr: PRIdentifier) async {
        guard let checkout else { return }
        let previous = checkoutState(for: pr.repo)
        checkoutStates[pr.repo] = .preparing

        do {
            checkoutStates[pr.repo] = .ready(try await checkout.prepare(pr.repo))
        } catch is CancellationError {
            // Zrušení není selhání checkoutu — a `localizedDescription` by z něj udělalo
            // anglickou systémovou hlášku v české aplikaci.
            checkoutStates[pr.repo] = previous
        } catch let error as CheckoutError {
            checkoutStates[pr.repo] = .failed(error.userDescription)
        } catch {
            checkoutStates[pr.repo] = .failed(error.localizedDescription)
        }
    }

    func checkoutPath(for pr: PRIdentifier) -> URL? {
        guard case .ready(let url) = checkoutState(for: pr.repo) else { return nil }
        return url
    }

    /// Srovná stav podle toho, co je **teď** v cache. Volá se při výběru řádku, nic
    /// nestahuje.
    ///
    /// Nejde jen o doplnění chybějícího: klon mohla mezitím sebrat eviction, takže se
    /// zapsaná cesta musí ověřit znovu — jinak by detail ukazoval „připraveno“ na složku,
    /// která už neexistuje. Běžící přípravu to nepřepisuje.
    func noteExistingCheckout(for pr: PRIdentifier) async {
        guard checkoutState(for: pr.repo) != .preparing else { return }
        if let clone = await checkout?.existingClone(for: pr.repo) {
            checkoutStates[pr.repo] = .ready(clone)
        } else if case .failed = checkoutState(for: pr.repo) {
            return // Chybu drž, dokud si uživatel neřekne o opakování.
        } else {
            checkoutStates[pr.repo] = .absent
        }
    }

    /// Zahodí stav rep, o která už není zájem. Bez toho by mapa rostla donekonečna a PR,
    /// které se po týdnu vrátí do seznamu, by přivítala chyba z minula.
    private func forget(whatIsNotIn summaries: [PullRequestSummary]) {
        let wanted = Set(summaries.map(\.id.repo))
        checkoutStates = checkoutStates.filter { wanted.contains($0.key) || $0.value == .preparing }
    }
}
