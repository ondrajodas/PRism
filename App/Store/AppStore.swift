import Foundation
import Observation

/// Stav aplikace, který kreslí okno.
///
/// Zatím drží dvě věci: polling seznamu PR a výběr řádku. Výběr žije tady, ne ve view —
/// jinak by ho každé přestavění seznamu zahodilo. Postupně sem přibude stav review na
/// jednotlivých PR a limit souběžných session.
@MainActor
@Observable
final class AppStore {
    /// Který řádek je vybraný. Detail k němu přijde v M4.
    var selection: PRIdentifier?

    private let polling: PollingService

    init(
        gateway: any GitHubGateway,
        sources: [Source] = [.reviewRequested],
        interval: Duration = .seconds(60),
        time: any TimeSource = SystemTimeSource(),
        eviction: CacheEviction? = nil
    ) {
        polling = PollingService(gateway: gateway, sources: sources, interval: interval, time: time)
        polling.afterSuccessfulTick = { [eviction] summaries in
            // `busy` je zatím prázdné — review se ještě nespouští. Až se začne, musí sem
            // přijít repa s běžícím během, jinak jim eviction sebere klon pod rukama.
            try? await eviction?.run(openPullRequests: summaries.map(\.id), busy: [])
        }
    }

    /// Sestavení z toho, co našel preflight. Absolutní cesta k `gh` je jediné, co gateway
    /// potřebuje — token si drží `gh` sám.
    convenience init(toolPaths: ToolPaths) {
        let runner = SubprocessRunner()
        let checkout = GitRepoCheckout(git: toolPaths.git, gh: toolPaths.gh, runner: runner)
        self.init(
            gateway: GhGateway(gh: toolPaths.gh, runner: runner),
            eviction: CacheEviction(checkout: checkout)
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
}
