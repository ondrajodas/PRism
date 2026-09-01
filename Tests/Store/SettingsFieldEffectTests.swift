import Foundation
import Testing

@testable import PRism

/// Dvě pole, která se od #389 dají nastavit z okna — a co z nich doopravdy plyne.
///
/// **Nejcennější tvrzení téhle sady je to první: prázdné `issueTextTool` z okna dotažení textu
/// nespustí.** Je to tvrzení o tom, že se něco NEstalo, a rozbije se potichu: prázdný pokus by
/// session pustil, session by doběhla `success` a v okně by nic nekřičelo — jen by se za každé
/// review platil boot za nic. Vedle něj stojí protějšek s vyplněným polem, protože sám o sobě by
/// první test prošel i tehdy, kdyby se pole do konfigurace nepropisovalo vůbec.
///
/// **Cesta je ta skutečná**: hodnota jde přes `SettingsModel` (to, co drží formulář) a
/// `AppStore.updateConfiguration` (to, co ho ukládá) — ne přímým zápisem do `Configuration`.
@Suite("Nastavení — co z polí #389 plyne")
@MainActor
struct SettingsFieldEffectTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let headSha = "aaaa1111"

    /// Popis PR s odkazem na zadání — bez něj se text netahá tak jako tak a test by netvrdil nic.
    private static let linkbackBody = "Řeší https://linear.app/keboola/issue/AJDA-3003/atomicky-zapis"

    private func detail() -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: headSha,
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open,
            body: Self.linkbackBody
        )
    }

    private func store(
        in workspace: TemporaryDirectory,
        configuration: Configuration,
        gateway: FakeGitHubGateway,
        reviewer: FakeReviewRunner = FakeReviewRunner(),
        intentText: (any IntentTextFetching)? = nil
    ) -> AppStore {
        let layout = CacheLayout(root: workspace.url)
        return AppStore(
            gateway: gateway,
            configuration: configuration,
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            intents: ReviewIntentStore(layout: layout),
            intentText: intentText
        )
    }

    /// Formulář z okna nastavení nad tímhle store — přesně jak ho staví `SettingsView`.
    private func settings(over store: AppStore) -> SettingsModel {
        SettingsModel(configuration: store.configuration, time: FakeTimeSource()) { configuration in
            try await store.updateConfiguration(configuration)
        }
    }

    /// Dráhy z tabu `Průběh` — tam se příznak zadání kreslí.
    private func lanes(of store: AppStore) -> [ReviewerLane] {
        Policy.lanes(
            of: store.timelines(for: pr),
            skills: store.reviewSkills(for: pr.repo),
            record: store.reviewRecords[pr]
        )
    }

    private func run(_ store: AppStore) async {
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }
    }

    // MARK: - Prázdné pole nespustí session

    /// **Vymazané pole v okně znamená „netahat“, ne prázdný pokus.** Session, která nemá co
    /// zavolat, stojí boot (~$0,2) a nevrátí nic — a v okně po ní zůstane odznak, který tvrdí, že
    /// se něco nedotáhlo, i když se o to nikdo nepokusil.
    @Test("Vymazané pole v okně dotažení textu nespustí")
    func anEmptiedFieldFetchesNothing() async throws {
        let workspace = try TemporaryDirectory()
        var configuration = Configuration.standard
        configuration.global.issueTextTool = "mcp__claude_ai_Linear__get_issue"
        let fetcher = FakeIntentTextFetcher()
        let store = store(
            in: workspace,
            configuration: configuration,
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail())),
            intentText: fetcher
        )

        // Člověk v okně pole vymazal — tedy přesně to, co udělá `IssueTextToolField`.
        let settings = settings(over: store)
        settings.draft.global.issueTextTool = Policy.issueTextToolEdit(typed: "")
        await settings.flush()
        #expect(store.configuration.global.issueTextTool == nil)

        await run(store)

        // Nic se nezavolalo…
        #expect(fetcher.calls.isEmpty)
        // …a v okně je vidět, že se netahalo, ne že se to nepovedlo.
        #expect(lanes(of: store).map(\.intentGap) == [.toolNotConfigured])
        // Review přitom doběhlo — chybějící text zadání ho nepokládá.
        #expect(store.reviewRecords[pr] != nil)
    }

    /// Protějšek předchozího testu. Bez něj by první test prošel i nad kódem, který pole
    /// z okna do konfigurace nepropisuje vůbec — tedy nad rozbitým #389.
    @Test("Vyplněné pole v okně se dostane až k session")
    func aFilledFieldReachesTheSession() async throws {
        let workspace = try TemporaryDirectory()
        let fetcher = FakeIntentTextFetcher()
        let store = store(
            in: workspace,
            configuration: .standard,
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail())),
            intentText: fetcher
        )
        #expect(store.configuration.global.issueTextTool == nil)

        let settings = settings(over: store)
        settings.draft.global.issueTextTool = Policy.issueTextToolEdit(typed: "mcp__jira__get_issue")
        await settings.flush()

        await run(store)

        #expect(fetcher.calls.map(\.tool) == ["mcp__jira__get_issue"])
        #expect(fetcher.calls.map { $0.links.map(\.id) } == [["AJDA-3003"]])
    }

    /// Bílé znaky se z pole ukládají, jak jsou napsané (kurzor se pod rukou nehýbe), ale session
    /// se s nimi **nepustí** — měřítko je jedno, `Policy.issueTextTool(from:)`.
    @Test("Pole s bílými znaky session nepustí")
    func aWhitespaceOnlyFieldFetchesNothing() async throws {
        let workspace = try TemporaryDirectory()
        let fetcher = FakeIntentTextFetcher()
        let store = store(
            in: workspace,
            configuration: .standard,
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail())),
            intentText: fetcher
        )

        let settings = settings(over: store)
        settings.draft.global.issueTextTool = Policy.issueTextToolEdit(typed: "   ")
        await settings.flush()
        // V souboru zůstalo, co člověk napsal…
        #expect(store.configuration.global.issueTextTool == "   ")

        await run(store)

        // …a přesto se nic nepustilo.
        #expect(fetcher.calls.isEmpty)
        #expect(lanes(of: store).map(\.intentGap) == [.toolNotConfigured])
    }

    // MARK: - Loginy z okna rozřazují frontu

    /// Druhé pole z #389. Bez něj se PR agenta s vlastním účtem počítá jako **cizí**, tedy do
    /// fronty k review, o kterou nikdo nepožádal.
    @Test("Login přidaný v okně přehodí PR z fronty do vlastních")
    func aLoginAddedInTheWindowMovesThePullRequest() async throws {
        let workspace = try TemporaryDirectory()
        let bot = PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "github-actions[bot]",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
        let gateway = FakeGitHubGateway(always: .success([bot]))
        gateway.viewer = "ondrajodas"
        let store = store(in: workspace, configuration: .standard, gateway: gateway)

        await store.loadViewer()
        await store.refresh()
        // Bez vypsaného loginu je to cizí PR, tedy řádek ve frontě.
        #expect(store.queuePullRequests.map(\.author) == ["github-actions[bot]"])
        #expect(store.visibleOwnPullRequests.isEmpty)

        let settings = settings(over: store)
        settings.draft.global.ownLogins = ["github-actions[bot]"]
        await settings.flush()

        // A po vyplnění je to moje práce, ne cizí fronta — bez dalšího tiku pollingu.
        #expect(store.queuePullRequests.isEmpty)
        #expect(store.visibleOwnPullRequests.map(\.author) == ["github-actions[bot]"])
    }

    /// Prázdný seznam je **běžný stav**, ne nedodělek: rozřazení pak stojí na přihlášeném účtu,
    /// který se bere z `gh` a v okně se jen ukazuje.
    @Test("Prázdný seznam loginů se opře o přihlášený účet")
    func anEmptyListFallsBackToTheSignedInAccount() async throws {
        let workspace = try TemporaryDirectory()
        let mine = PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "OndraJodas",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
        let gateway = FakeGitHubGateway(always: .success([mine]))
        gateway.viewer = "ondrajodas"
        let store = store(in: workspace, configuration: .standard, gateway: gateway)

        await store.loadViewer()
        await store.refresh()

        #expect(store.configuration.global.ownLogins.isEmpty)
        #expect(store.visibleOwnPullRequests.map(\.author) == ["OndraJodas"])
        #expect(Policy.viewerAccount(login: store.viewer) == .known(login: "ondrajodas"))
    }

    /// Vrátí, co si test předepsal, a pamatuje si, na co se ho ptali. Počet volání je součást
    /// kontraktu — proto vlastní fake a ne prázdná implementace.
    final class FakeIntentTextFetcher: IntentTextFetching, @unchecked Sendable {
        private let answer: IntentTextResult
        private let lock = NSLock()
        private var recorded: [(links: [IntentLink], tool: String)] = []

        init(_ answer: IntentTextResult = IntentTextResult()) {
            self.answer = answer
        }

        var calls: [(links: [IntentLink], tool: String)] { lock.withLock { recorded } }

        func fetchText(of links: [IntentLink], using tool: String) async throws -> IntentTextResult {
            lock.withLock { recorded.append((links, tool)) }
            return answer
        }
    }
}
