import Foundation

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

    init(
        tracked: [RepoID: [Int]] = [:],
        outcome: Result<URL, CheckoutError> = .success(URL(filePath: "/tmp/klon")),
        existing: [RepoID: URL] = [:],
        gate: AsyncGate? = nil
    ) {
        self.tracked = tracked
        self.outcome = outcome
        self.existing = existing
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

    func worktree(for pr: PRIdentifier, at headSha: String) async throws -> URL {
        URL(filePath: "/tmp/\(pr)-\(headSha)")
    }

    func removeWorktree(for pr: PRIdentifier, at headSha: String) async throws {}

    func forgetPullRequest(_ pr: PRIdentifier) async throws {
        lock.withLock { forgotten.append(pr) }
    }

    func trackedPullRequests(in repo: RepoID) async throws -> [Int] { tracked[repo] ?? [] }

    func existingClone(for repo: RepoID) async -> URL? { lock.withLock { existing[repo] } }

    func pruneWorktrees(in repo: RepoID) async throws {
        lock.withLock { pruned.append(repo) }
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
    func waitUntilReached() async throws {
        for _ in 0..<100_000 where !arrived { await Task.yield() }
        guard arrived else {
            throw NSError(domain: "AsyncGate", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Práce se k závoře nedostala.",
            ])
        }
    }

    func release() {
        open = true
        for continuation in waiting { continuation.resume() }
        waiting.removeAll()
    }
}
