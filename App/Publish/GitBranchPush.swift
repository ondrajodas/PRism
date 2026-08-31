import Foundation

/// `BranchPushing` nad `git` (#466).
///
/// **Dva nezávislé guardy, oba povinné** — chrání proti dvěma různým omylům a ani jeden
/// nenahrazuje druhý:
///
/// 1. **Cílem smí být jedině hlava vlastního pull requestu**, a posuzuje se to proti **datům pull
///    requestu** (pre-flight přes read-only gateway), ne proti jménu větve. Jméno se dá nastavit
///    na cokoli, takže shoda jména by byla kontrola, která jenom vypadá jako kontrola.
/// 2. **`--force-with-lease=<větev>:<sha>`, nikdy holé `--force`.** Když se remote mezi pre-flightem
///    a pushem pohnul, server push **odmítne** místo aby přepsal cizí commit. Změřeno (ne přečteno
///    v dokumentaci): po pushnutí cizího commitu do větve skončil push `! [rejected] HEAD -> feature
///    (stale info)`, návratový kód 1, a hlava na remote **zůstala ta cizí**.
///
/// **Lease se posílá s vypsanou hodnotou, ne holý** — a je to nutnost, ne opatrnost. Holý
/// `--force-with-lease` si bere očekávanou hodnotu z **remote-tracking refu**, a ten v klonu
/// aplikace neexistuje: `git clone --bare` si `remote.origin.fetch` nenastavuje a fetch v `#4` míří
/// na `+refs/heads/*:refs/heads/*`. Změřeno: holý lease v takovém klonu skončí `(stale info)`
/// **vždycky**, tedy i tam, kde se nic nepohnulo. Vypsaná hodnota je navíc ta jediná, která
/// znamená „co jsem viděl v okně“ — remote-tracking ref by se dal aktualizovat fetchem, který
/// děláme před rebasem, takže by lease chránil proti ničemu.
///
/// **Pracuje se výhradně v cache** (tvrdá podmínka č. 3): strom, ze kterého se pushuje, musí ležet
/// pod kořenem cache a nesmí to být symlink. Kontrola je **tatáž jako jinde v repu**
/// (`CacheFile.refusal`), ne opsaná potřetí.
struct GitBranchPush: BranchPushing {
    private let git: URL
    private let gh: URL
    private let layout: CacheLayout
    private let runner: ProcessRunning
    private let gateway: any GitHubGateway
    /// Brána bez výchozí hodnoty: pusher se bez ní nedá složit, takže se nedá zapomenout.
    private let scope: PublishScope
    /// Loginy, které se počítají za moje (#330). Bez nich by se první guard neměl s čím porovnat.
    private let mine: Set<String>
    private let timeout: Duration

    /// **Sto osmdesát sekund**, ne třicet jako u `gh`: klon je partial (`--filter=blob:none`),
    /// takže si `git` při pushi umí dotáhnout chybějící objekty z promisor remote — a to je práce
    /// po síti navíc, kterou u volání API nikdo neplatí.
    init(
        git: URL,
        gh: URL,
        /// **Bez výchozí hodnoty**, jako brána: kontrola hranice cache má mluvit o té cache, ve
        /// které rebase proběhl, a dvě výchozí hodnoty na dvou místech by v provozu vyšly stejně
        /// a v testu se rozešly.
        layout: CacheLayout,
        runner: ProcessRunning,
        gateway: any GitHubGateway,
        scope: PublishScope,
        mine: Set<String>,
        timeout: Duration = .seconds(180)
    ) {
        self.git = git
        self.gh = gh
        self.layout = layout
        self.runner = runner
        self.gateway = gateway
        self.scope = scope
        self.mine = mine
        self.timeout = timeout
    }

    func push(_ plan: BranchPushPlan) async throws -> String {
        // Brána je **první**, ještě před sítí: na repo, které povolené není, se nemá ani ptát na
        // detail. Tatáž konstrukce jako u `GhReviewPublisher`.
        guard scope.allows(plan.pullRequest.repo) else {
            throw BranchSyncError.notAllowed(
                PublishError.publishingNotAllowed(plan.pullRequest.repo).userDescription
            )
        }
        try checkInsideCache(plan.worktree)
        try await preflight(plan)

        let result = try await run(arguments(for: plan))
        guard result.exitCode == 0 else { throw Self.failure(from: result) }
        return plan.sha
    }

    /// Příkaz, který se doopravdy spouští. **Zdrojová strana je `sha`, ne `HEAD`**: pushuje se
    /// přesně ten commit, který vypadl z rebase a o kterém se rozhodovalo — `HEAD` by se mezitím
    /// mohl pohnout (třeba tím, že si člověk ve stromě něco zkusil z terminálu).
    static func arguments(for plan: BranchPushPlan, gh: URL) -> [String] {
        ["-C", plan.worktree.path(percentEncoded: false)]
            + GitCredentials.configuration(gh: gh)
            + [
                "push",
                "--force-with-lease=refs/heads/\(plan.branch):\(plan.expectedRemoteSha)",
                "origin",
                "\(plan.sha):refs/heads/\(plan.branch)",
            ]
    }

    private func arguments(for plan: BranchPushPlan) -> [String] {
        Self.arguments(for: plan, gh: gh)
    }

    /// Hranice cache — **tentýž verdikt jako všude jinde v repu** (`CacheFile.refusal`), ne třetí
    /// opis.
    ///
    /// Je to ta přísnější z obou podob: `contains` rozbaluje symlinky v rodičích, `isSymbolicLink`
    /// odchytí odkaz na poslední komponentě. Strom, který je odkazem ven, by `git` použil na svém
    /// cíli — tedy v uživatelově klonu, a to je tvrdá podmínka č. 3.
    private func checkInsideCache(_ worktree: URL) throws {
        guard CacheFile.refusal(for: worktree, in: layout) == nil else {
            throw BranchSyncError.outsideCache(worktree.path(percentEncoded: false))
        }
    }

    /// **První guard**: cílem smí být jedině hlava pull requestu, jehož autorem jsem já.
    ///
    /// Ptá se **dat pull requestu**, ne jména větve — a ověřuje pět věcí, protože každá z nich
    /// znamená něco jiného, co se mezitím mohlo změnit: autora, repozitář hlavy (fork), stav PR,
    /// jméno větve a hlavu. Čtení jde přes read-only gateway, takže se tím nic neotvírá.
    private func preflight(_ plan: BranchPushPlan) async throws {
        let pullRequest: PullRequest
        do {
            pullRequest = try await gateway.fetchDetail(id: plan.pullRequest)
        } catch let error as GitHubError {
            throw BranchSyncError.failed(error.userDescription)
        }

        guard Policy.ownership(ofAuthor: pullRequest.author, mine: mine) == .mine else {
            throw BranchSyncError.notMine(author: pullRequest.author)
        }
        switch pullRequest.isCrossRepository {
        // `origin` je základní repozitář, takže by push u PR z forku mířil **jinam, než na co se
        // člověk dívá** — a v tom repozitáři by větev toho jména klidně mohl vyrobit.
        case .some(true): throw BranchSyncError.foreignBranch
        // „Nevím“ je zákaz, ne povolení: je to jediná odpověď, ze které neplyne, kam se píše.
        case .none: throw BranchSyncError.unknownBranchOrigin
        case .some(false): break
        }
        guard pullRequest.state == .open || pullRequest.state == .draft else {
            throw BranchSyncError.pullRequestNotOpen(pullRequest.state)
        }
        guard pullRequest.headRef == plan.branch else {
            throw BranchSyncError.branchChanged(expected: plan.branch, actual: pullRequest.headRef)
        }
        guard pullRequest.headSha == plan.expectedRemoteSha else {
            throw BranchSyncError.headMoved(
                expected: plan.expectedRemoteSha,
                actual: pullRequest.headSha
            )
        }
    }

    /// Co `git` řekl, když push neprošel.
    ///
    /// **Odmítnutý lease se pozná podle `stale info`** — to je věta, kterou `git` vypíše právě
    /// tehdy, když očekávaná hodnota nesedí (změřeno). Ostatní selhání jdou přes tutéž
    /// klasifikaci jako u checkoutu (`CheckoutError(failure:)`), takže se z nich pozná odmítnuté
    /// přihlášení i nedostupná síť; nová klasifikace by byla druhý seznam frází, který se
    /// s prvním rozejde.
    private static func failure(from result: ProcessResult) -> BranchSyncError {
        let text = result.failureText
        guard !text.lowercased().contains("stale info") else { return .leaseRejected }
        return .failed(CheckoutError(failure: result).userDescription)
    }

    private func run(_ arguments: [String]) async throws -> ProcessResult {
        do {
            return try await runner.run(
                git,
                arguments: arguments,
                environment: GitCredentials.environment,
                timeout: timeout
            )
        } catch ProcessError.timedOut {
            throw BranchSyncError.timedOut
        } catch ProcessError.launchFailed(let detail) {
            throw BranchSyncError.toolUnavailable(detail)
        } catch is CancellationError {
            // Zrušení **není chyba nástroje** a musí projít jako zrušení — jinak by okno hlásilo
            // „nepodařilo se spustit git“ nad akcí, kterou si člověk sám zrušil.
            throw CancellationError()
        } catch {
            throw BranchSyncError.toolUnavailable(error.localizedDescription)
        }
    }
}
