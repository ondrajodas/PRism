import Foundation
import Testing

@testable import PRism

/// Checkout, který nic nespouští — pamatuje si, co se po něm chtělo.
final class FakeRepoCheckout: RepoCheckout, @unchecked Sendable {
    private let tracked: [RepoID: [Int]]
    private let outcome: Result<URL, CheckoutError>
    /// Zdrží přípravu, dokud ji test nepustí — na tom se pozná stav „klonuje se“.
    private let gate: AsyncGate?
    private let lock = NSLock()
    private var forgotten: [PRIdentifier] = []
    private var prepared: [RepoID] = []

    /// Co je „už naklonované“ — nastaví se v initu, aby to bylo pod stejným zámkem jako
    /// zbytek stavu.
    private var existing: [RepoID: URL]

    /// Co „leží v pracovním stromě“ — podklad pro detekci jazyka.
    private let files: Result<[String], CheckoutError>

    /// Co pull request „mění“ — podklad pro routing reviewerů (#518).
    ///
    /// **Výchozí prázdno, ne pár cest**: fake nemá `git`, takže o změněných cestách nic neví —
    /// a prázdný seznam nepřeskočí nikoho (`Policy.reviewersToRun`), tedy tatáž bezpečná strana
    /// jako v aplikaci. Testy, které o routing nestojí, tím nic netvrdí.
    private let changed: Result<[String], CheckoutError>

    /// Pracovní strom, který se vydá místo vymyšlené cesty. Potřebuje ho jediný test —
    /// ten, který pouští **skutečný** podproces (#264): `Process` složku, která neexistuje,
    /// odmítne, takže by se běh rozsypal na `launchFailed` místo aby se rozjel.
    private let worktree: URL?

    /// Co fake odpoví na „sdílí ta dvě sha historii“ (#517).
    ///
    /// **Výchozí `.unknown`, ne `.ancestor`**: fake nemá `git`, takže nic neví — a `ancestor` by
    /// znamenal, že každý test, který o přírůstek nestojí, začne mít review nad přírůstkem.
    /// Bezpečná strana je tady tatáž jako v aplikaci: celé review.
    private let ancestry: BranchAncestry

    /// Na která sha se fake ptal — na tom se pozná, že se `git` **nespouštěl** tam, kde neměl.
    private var ancestryQueries: [String] = []

    init(
        tracked: [RepoID: [Int]] = [:],
        outcome: Result<URL, CheckoutError> = .success(URL(filePath: "/tmp/klon")),
        existing: [RepoID: URL] = [:],
        files: Result<[String], CheckoutError> = .success([]),
        changed: Result<[String], CheckoutError> = .success([]),
        worktree: URL? = nil,
        ancestry: BranchAncestry = .unknown,
        gate: AsyncGate? = nil
    ) {
        self.ancestry = ancestry
        self.tracked = tracked
        self.outcome = outcome
        self.existing = existing
        self.files = files
        self.changed = changed
        self.worktree = worktree
        self.gate = gate
    }

    var preparedRepositories: [RepoID] { lock.withLock { prepared } }

    private var pruned: [RepoID] = []

    var forgottenPullRequests: [PRIdentifier] { lock.withLock { forgotten } }
    var prunedRepositories: [RepoID] { lock.withLock { pruned } }

    func prepare(_ repo: RepoID) async throws -> URL {
        lock.withLock { prepared.append(repo) }
        await gate?.wait()
        return try outcome.get()
    }

    /// Stejné selhání jako u přípravy — `worktree` ji volá, takže co položí ji, položí i ho.
    func worktree(for pr: PRIdentifier, at headSha: String) async throws -> URL {
        _ = try outcome.get()
        if let worktree { return worktree }
        return URL(filePath: "/tmp/\(pr)-\(headSha)")
    }

    func trackedFiles(in worktree: URL) async throws -> [String] { try files.get() }

    func changedFiles(in worktree: URL, since base: String) async throws -> [String] {
        lock.withLock { changedQueries.append(base) }
        return try changed.get()
    }

    /// Proti čemu se kdo ptal na změněné cesty. **Na počtu stojí tvrzení, že se `git` nespouštěl**
    /// tam, kde repo žádné pravidlo routingu nemá (#518).
    var askedChangedFilesSince: [String] { lock.withLock { changedQueries } }

    private var changedQueries: [String] = []

    func ancestry(of sha: String, in worktree: URL) async -> BranchAncestry {
        lock.withLock { ancestryQueries.append(sha) }
        return ancestry
    }

    var askedAncestryOf: [String] { lock.withLock { ancestryQueries } }

    func removeWorktree(for pr: PRIdentifier, at headSha: String) async throws {}

    func forgetPullRequest(_ pr: PRIdentifier) async throws {
        lock.withLock { forgotten.append(pr) }
    }

    func trackedPullRequests(in repo: RepoID) async throws -> [Int] { tracked[repo] ?? [] }

    func existingClone(for repo: RepoID) async -> URL? { lock.withLock { existing[repo] } }

    func pruneWorktrees(in repo: RepoID) async throws {
        lock.withLock { pruned.append(repo) }
    }

    // MARK: - Srovnání větve (#466)

    /// Jak dopadne `rebase`. Výchozí je **úspěch bez přehraných commitů**, protože v drtivé
    /// většině testů jde o něco jiného.
    var rebaseOutcome: Result<RebaseOutcome, CheckoutError> = .success(
        .rebased(
            RebasedBranch(
                worktree: URL(filePath: "/tmp/sync"),
                headSha: "rebased",
                rebasedFrom: "puvodni",
                arriving: [],
                replayed: 0
            )
        )
    )
    /// Co „leží“ ve stromě pro srovnání větve. Výchozí je **prázdno**, protože v drtivé většině
    /// testů v cache nic nečeká.
    var syncWorktree: SyncWorktreeState = .empty
    /// Čím spadne `discardSync`. `nil` = povede se.
    var discardFailure: CheckoutError?

    /// Na co se kdo ptal, v pořadí. Na počtu stojí testy, které tvrdí, že se **nerebasovalo**.
    var rebaseRequests: [PRIdentifier] { lock.withLock { rebased } }
    var discardRequests: [PRIdentifier] { lock.withLock { discarded } }

    private var rebased: [PRIdentifier] = []
    private var discarded: [PRIdentifier] = []

    func rebase(
        _ pr: PRIdentifier,
        at headSha: String,
        onto base: String,
        keepingConflict: Bool
    ) async throws -> RebaseOutcome {
        lock.withLock {
            rebased.append(pr)
            keptConflicts.append(keepingConflict)
        }
        return try rebaseOutcome.get()
    }

    /// Zapíše slité soubory a vydá diff (#467). **Vrací připravenou odpověď**, aby se dal
    /// vyzkoušet i ten směr, ve kterém v souborech zůstaly značky.
    func stageResolution(in worktree: URL, paths: [String]) async throws -> ConflictStaging {
        lock.withLock { staged.append((worktree, paths)) }
        if let stageFailure { throw stageFailure }
        return staging
    }

    func continueRebase(
        _ pr: PRIdentifier,
        at headSha: String,
        onto base: String,
        keepingConflict: Bool
    ) async throws -> RebaseOutcome {
        let index = lock.withLock {
            continued.append(pr)
            return continued.count - 1
        }
        // **Výsledky se berou po kolech**, ne jedna hodnota dokola: kolo za kolem je zrovna to,
        // co má u slévání konfliktů smysl testovat (rebase se zastaví u každého kolizního commitu).
        // Když jich je připraveno málo, platí ten poslední — testu, který chce jedno kolo, tak
        // stačí jeden prvek.
        guard !continueOutcomes.isEmpty else { return try rebaseOutcome.get() }
        return try continueOutcomes[min(index, continueOutcomes.count - 1)].get()
    }

    /// Co dostal `stageResolution` (#467) — na tom stojí tvrzení „soubor se značkami se nezapsal“.
    private(set) var staged: [(worktree: URL, paths: [String])] = []
    /// S jakou hodnotou `keepingConflict` se rebase volal. **Tvrdí se oba směry**: s resolverem se
    /// konflikt nechává stát, bez něj se zahazuje.
    private(set) var keptConflicts: [Bool] = []
    /// Kolikrát se dokončoval rebase (#467).
    private(set) var continued: [PRIdentifier] = []
    /// Co vydá `stageResolution`.
    var staging = ConflictStaging()
    var stageFailure: (any Error)?
    /// Výsledky `continueRebase` po kolech. Prázdné = použije se `rebaseOutcome`.
    var continueOutcomes: [Result<RebaseOutcome, any Error>] = []

    func discardSync(for pr: PRIdentifier) async throws {
        lock.withLock { discarded.append(pr) }
        if let discardFailure { throw discardFailure }
        syncWorktree = .empty
    }

    func syncWorktreeState(
        for pr: PRIdentifier,
        at headSha: String,
        onto base: String
    ) async -> SyncWorktreeState { syncWorktree }

    // MARK: - Agent na vlastním PR (#510)

    /// Strom, ve kterém agent pracuje. `nil` = vydá se vymyšlená cesta.
    var agentWorktree: URL?
    /// Čím spadne příprava stromu. `nil` = povede se.
    var agentWorktreeFailure: CheckoutError?
    /// Co vydá commit. **Výchozí `nil`, tedy „ve stromě se nic nezměnilo“** — testu, který
    /// o commit nestojí, tím v cache nic nevznikne; kdo commit chce, si ho nastaví.
    var agentCommit: Result<RebasedBranch?, CheckoutError> = .success(nil)

    /// Komu se připravoval strom a **s jakou zprávou se commitovalo**. Na počtu commitů stojí
    /// tvrzení „necommitlo se nic“, které je z celého #510 to nejcennější.
    var agentWorktreeRequests: [PRIdentifier] { lock.withLock { agentWorktrees } }
    var agentCommitRequests: [(pr: PRIdentifier, message: String)] { lock.withLock { agentCommits } }

    private var agentWorktrees: [PRIdentifier] = []
    private var agentCommits: [(pr: PRIdentifier, message: String)] = []

    func agentFixWorktree(for pr: PRIdentifier, at headSha: String) async throws -> URL {
        lock.withLock { agentWorktrees.append(pr) }
        if let agentWorktreeFailure { throw agentWorktreeFailure }
        return agentWorktree ?? URL(filePath: "/tmp/\(pr.number)-sync")
    }

    func commitAgentFix(
        for pr: PRIdentifier,
        in worktree: URL,
        at headSha: String,
        message: String
    ) async throws -> RebasedBranch? {
        lock.withLock { agentCommits.append((pr, message)) }
        return try agentCommit.get()
    }
}


/// Závora pro testy: práce se zastaví, dokud ji test nepustí dál.
actor AsyncGate {
    private var open = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var arrived = false

    func wait() async {
        arrived = true
        guard !open else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Počká, až práce dorazí k závoře — ale ne donekonečna. Bez stropu by se test při
    /// chybě zasekl místo aby spadl.
    ///
    /// **Strop je čas, ne počet `yield`ů** (#292; do té doby `for _ in 0..<100_000`). Rozpočet
    /// yieldů je pevný okamžik v přestrojení: pod zátěží (druhý paralelní build na stroji) se
    /// vyčerpá dřív, než se čekaná práce vůbec dostane na procesor — závora pak hlásila „práce se
    /// k závoře nedostala“ u **tří** suit naráz, přitom samostatně proběhly za 0,094 s. Je to tatáž
    /// chyba, jakou #269 vyndalo ze sondy odpočtu: kdo čeká na jev, čeká **na jev se stropem** —
    /// a spánek k tomu na rozdíl od `yield`ování pustí procesor jinam.
    ///
    /// Od #296 je z toho `waitUntil` v `TestWaiting.swift`, protože týž strop potřebovala i pětice
    /// dalších míst a každé si ho psalo po svém. Vlastní implementace by tady znamenala, že se
    /// příští oprava udělá jen v jedné z nich.
    nonisolated func waitUntilReached() async {
        await waitUntil("práce dorazí k závoře") { await self.hasArrived }
    }

    private var hasArrived: Bool { arrived }

    func release() {
        open = true
        for continuation in waiting { continuation.resume() }
        waiting.removeAll()
    }
}
