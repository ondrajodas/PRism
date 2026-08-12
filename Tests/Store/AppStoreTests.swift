import Foundation
import Testing

@testable import PRism

@Suite("AppStore")
@MainActor
struct AppStoreTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]

    /// Zdroje i sada skillů se berou z konfigurace, takže si ji test postaví.
    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = sources
        return configuration
    }

    private func summary(_ identifier: String) -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(gateway: gateway, configuration: configuration, time: FakeTimeSource())
    }

    @Test("Obnovení se zeptá zdrojů")
    func refreshAsksTheSources() async {
        let gateway = FakeGitHubGateway(always: .success([]))

        await store(gateway).refresh()

        #expect(gateway.queries == sources.map(\.query))
    }

    @Test("Seznam PR se čte z pollingu")
    func pullRequestsComeFromPolling() async {
        let store = store(FakeGitHubGateway(always: .success([summary("cli/cli#1")])))

        await store.refresh()

        #expect(store.pullRequests.map(\.id.description) == ["cli/cli#1"])
    }

    @Test("Než něco doběhne, je stav nenačteno")
    func startsBeforeAnythingHasLoaded() {
        #expect(store(FakeGitHubGateway(always: .success([]))).status == .notStarted)
    }

    @Test("Výběr se drží mezi překreslením")
    func keepsSelection() {
        // Výběr žije ve store, ne ve view — jinak by ho každé přestavění seznamu zahodilo.
        let store = store(FakeGitHubGateway(always: .success([])))

        store.selection = PRIdentifier("cli/cli#1")

        #expect(store.selection == PRIdentifier("cli/cli#1"))
    }
}

extension AppStoreTests {
    @Test("Po každém tiku se pustí úklid cache")
    func tidiesTheCacheAfterEveryTick() async throws {
        // Zavřené PR se poznají jen tím, že v odpovědi chybí — úklid proto musí běžet
        // i po tiku, který nenašel nic.
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)
        let clone = layout.bareClone(for: RepoID(owner: "cli", name: "cli"))
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)

        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            eviction: CacheEviction(layout: layout, budget: .max)
        )
        await store.keepFresh()

        #expect(!FileManager.default.fileExists(atPath: clone.path(percentEncoded: false)))
    }
}

extension AppStoreTests {
    @Test("Selhaný tik cache neuklidí")
    func aFailedTickNeverTouchesTheCache() async throws {
        // Po výpadku sítě zůstane seznam beze změny — a po startu je prázdný. Uklízet
        // po takovém tiku by znamenalo smazat celou cache kvůli chvíli bez sítě.
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)
        let clone = layout.bareClone(for: RepoID(owner: "cli", name: "cli"))
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)

        let store = AppStore(
            gateway: FakeGitHubGateway(always: .failure(GitHubError.network("bez sítě"))),
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            eviction: CacheEviction(layout: layout, budget: .max)
        )
        await store.keepFresh()

        #expect(FileManager.default.fileExists(atPath: clone.path(percentEncoded: false)))
    }
}

extension AppStoreTests {
    @Test("Než se něco spustí, je stav neběželo")
    func stateStartsAsNotStarted() {
        let store = AppStore(gateway: FakeGitHubGateway(always: .success([])), configuration: configuration)

        #expect(store.reviewState(for: PRIdentifier("cli/cli#1")!) == .notStarted)
    }

    @Test("Během přípravy je vidět, že se klonuje")
    func showsCloningWhileTheCheckoutRuns() async throws {
        // První klon velkého repa je citelný — UI to má přiznat, ne se tvářit, že se nic
        // neděje.
        let gate = AsyncGate()
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            checkout: FakeRepoCheckout(gate: gate)
        )
        let pr = PRIdentifier("cli/cli#1")!

        let running = Task { await store.prepareCheckout(for: pr) }
        await gate.waitUntilReached()

        #expect(store.reviewState(for: pr) == .cloning)

        await gate.release()
        await running.value
        #expect(store.reviewState(for: pr) == .notStarted)
    }

    @Test("Selhaný checkout nese text chyby, ne jen příznak")
    func failedCheckoutCarriesTheErrorText() async {
        let stderr = "fatal: repository not found"
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            checkout: FakeRepoCheckout(outcome: .failure(.repositoryNotFound(stderr)))
        )
        let pr = PRIdentifier("cli/cli#1")!

        await store.prepareCheckout(for: pr)

        // Detail nese větu pro člověka **i** text od `gitu` — z toho druhého se pozná,
        // co se vlastně stalo.
        guard case .checkoutFailed(let detail) = store.reviewState(for: pr) else {
            Issue.record("Čekal jsem checkoutFailed, přišlo \(store.reviewState(for: pr))")
            return
        }
        #expect(detail.contains(stderr))
        #expect(detail.contains("nevidíš"))
    }

    @Test("Opakování po selhání zkusí checkout znovu")
    func retryRunsTheCheckoutAgain() async {
        let checkout = FakeRepoCheckout(outcome: .failure(.timedOut))
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            checkout: checkout
        )
        let pr = PRIdentifier("cli/cli#1")!

        await store.prepareCheckout(for: pr)
        await store.prepareCheckout(for: pr)

        #expect(checkout.preparedRepositories.count == 2)
    }

    @Test("Repo s běžícím checkoutem se eviction nedotkne")
    func repositoryBeingPreparedIsProtectedFromEviction() async throws {
        // Smazat klon uprostřed klonování by přípravu rozbilo — proto `busy`.
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)
        let repo = RepoID(owner: "cli", name: "cli")
        let clone = layout.bareClone(for: repo)
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)

        let gate = AsyncGate()
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            eviction: CacheEviction(layout: layout, budget: .max),
            checkout: FakeRepoCheckout(gate: gate)
        )

        let preparing = Task { await store.prepareCheckout(for: PRIdentifier("cli/cli#1")!) }
        await gate.waitUntilReached()
        await store.keepFresh()   // tik s prázdným seznamem by jinak klon smazal

        #expect(FileManager.default.fileExists(atPath: clone.path(percentEncoded: false)))

        await gate.release()
        await preparing.value
    }
}

extension AppStoreTests {
    @Test("Druhé PR ze stejného repa vidí, že je klon hotový")
    func aSecondPullRequestOfTheSameRepositorySeesTheClone() async {
        // Klon je jeden pro celé repo. Kdyby se evidoval per PR, druhé PR by nabízelo
        // přípravu něčeho, co už na disku leží.
        let checkout = FakeRepoCheckout(outcome: .success(URL(filePath: "/tmp/cli.git")))
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            checkout: checkout
        )

        await store.prepareCheckout(for: PRIdentifier("cli/cli#1")!)

        #expect(store.checkoutPath(for: PRIdentifier("cli/cli#2")!) == URL(filePath: "/tmp/cli.git"))
    }

    @Test("Klon z minulého spuštění se pozná bez stahování")
    func noticesACloneLeftFromAnEarlierRun() async throws {
        let checkout = FakeRepoCheckout(existing: [RepoID(owner: "cli", name: "cli"): URL(filePath: "/tmp/cli.git")])
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            checkout: checkout
        )
        let pr = PRIdentifier("cli/cli#1")!

        await store.noteExistingCheckout(for: pr)

        #expect(store.checkoutPath(for: pr) == URL(filePath: "/tmp/cli.git"))
        #expect(checkout.preparedRepositories.isEmpty)
    }
}

extension AppStoreTests {
    private var cli: RepoID { RepoID(owner: "cli", name: "cli") }

    @Test("Úspěch na druhém PR spraví stav i tomu prvnímu")
    func successOnOnePullRequestFixesTheOtherOfTheSameRepository() async {
        // Klon je společný, takže si dvě PR nesmí odporovat: jedno hlásit selhání nad
        // klonem, který pro druhé v pořádku vznikl.
        let checkout = FakeRepoCheckout(outcome: .failure(.timedOut))
        let store = AppStore(gateway: FakeGitHubGateway(always: .success([])), configuration: configuration, checkout: checkout)

        await store.prepareCheckout(for: PRIdentifier("cli/cli#1")!)
        #expect(store.reviewState(for: PRIdentifier("cli/cli#2")!) == .checkoutFailed(detail: "git nedoběhl v limitu."))

        let working = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            checkout: FakeRepoCheckout(outcome: .success(URL(filePath: "/tmp/cli.git")))
        )
        await working.prepareCheckout(for: PRIdentifier("cli/cli#2")!)

        #expect(working.reviewState(for: PRIdentifier("cli/cli#1")!) == .notStarted)
        #expect(working.checkoutPath(for: PRIdentifier("cli/cli#1")!) == URL(filePath: "/tmp/cli.git"))
    }

    @Test("Klon, který mezitím zmizel, se přestane hlásit jako připravený")
    func stopsClaimingReadyWhenTheCloneIsGone() async {
        // Eviction umí klon sebrat i repu s otevřeným PR. Zapsaná cesta by pak ukazovala
        // na složku, která neexistuje.
        let checkout = FakeRepoCheckout(outcome: .success(URL(filePath: "/tmp/cli.git")))
        let store = AppStore(gateway: FakeGitHubGateway(always: .success([])), configuration: configuration, checkout: checkout)
        let pr = PRIdentifier("cli/cli#1")!

        await store.prepareCheckout(for: pr)
        #expect(store.checkoutPath(for: pr) != nil)

        await store.noteExistingCheckout(for: pr)   // fake nic „existujícího“ nemá

        #expect(store.checkoutPath(for: pr) == nil)
    }

    @Test("Chyba zůstane, dokud si člověk neřekne o opakování")
    func failureSurvivesReselection() async {
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            checkout: FakeRepoCheckout(outcome: .failure(.timedOut))
        )
        let pr = PRIdentifier("cli/cli#1")!

        await store.prepareCheckout(for: pr)
        await store.noteExistingCheckout(for: pr)

        #expect(store.reviewState(for: pr) == .checkoutFailed(detail: "git nedoběhl v limitu."))
    }

    @Test("Stav repa, o které už není zájem, se zahodí")
    func forgetsRepositoriesThatLeftTheList() async {
        // Bez toho by mapa rostla donekonečna a PR, které se za týden vrátí, by přivítala
        // chyba z minula.
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            checkout: FakeRepoCheckout(outcome: .failure(.timedOut))
        )
        let pr = PRIdentifier("cli/cli#1")!

        await store.prepareCheckout(for: pr)
        #expect(store.checkoutState(for: cli) != .absent)

        await store.keepFresh()   // tik, ve kterém to PR není

        #expect(store.checkoutState(for: cli) == .absent)
    }

    @Test("Běžící příprava se nezahodí ani tikem, ve kterém PR není")
    func aRunningPreparationSurvivesATickWithoutIt() async throws {
        let gate = AsyncGate()
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            checkout: FakeRepoCheckout(gate: gate)
        )

        let preparing = Task { await store.prepareCheckout(for: PRIdentifier("cli/cli#1")!) }
        await gate.waitUntilReached()
        await store.keepFresh()

        #expect(store.checkoutState(for: cli) == .preparing)

        await gate.release()
        await preparing.value
    }
}
