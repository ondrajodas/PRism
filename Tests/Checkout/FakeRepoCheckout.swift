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

    /// Pracovní strom, který se vydá místo vymyšlené cesty. Potřebuje ho jediný test —
    /// ten, který pouští **skutečný** podproces (#264): `Process` složku, která neexistuje,
    /// odmítne, takže by se běh rozsypal na `launchFailed` místo aby se rozjel.
    private let worktree: URL?

    init(
        tracked: [RepoID: [Int]] = [:],
        outcome: Result<URL, CheckoutError> = .success(URL(filePath: "/tmp/klon")),
        existing: [RepoID: URL] = [:],
        files: Result<[String], CheckoutError> = .success([]),
        worktree: URL? = nil,
        gate: AsyncGate? = nil
    ) {
        self.tracked = tracked
        self.outcome = outcome
        self.existing = existing
        self.files = files
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
        .rebased(RebasedBranch(worktree: URL(filePath: "/tmp/sync"), headSha: "rebased", replayed: 0))
    )
    /// Leží v cache rozdělaný rebase?
    var unfinishedRebase = false
    /// Čím spadne `discardRebase`. `nil` = povede se.
    var discardFailure: CheckoutError?

    /// Na co se kdo ptal, v pořadí. Na počtu stojí testy, které tvrdí, že se **nerebasovalo**.
    var rebaseRequests: [PRIdentifier] { lock.withLock { rebased } }
    var discardRequests: [PRIdentifier] { lock.withLock { discarded } }

    private var rebased: [PRIdentifier] = []
    private var discarded: [PRIdentifier] = []

    func rebase(_ pr: PRIdentifier, at headSha: String, onto base: String) async throws -> RebaseOutcome {
        lock.withLock { rebased.append(pr) }
        return try rebaseOutcome.get()
    }

    func discardRebase(for pr: PRIdentifier) async throws {
        lock.withLock { discarded.append(pr) }
        if let discardFailure { throw discardFailure }
        unfinishedRebase = false
    }

    func rebaseInProgress(for pr: PRIdentifier) async -> Bool { unfinishedRebase }
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
