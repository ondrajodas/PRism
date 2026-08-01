import Foundation

@testable import PRism

/// Checkout, který nic nespouští — pamatuje si, co se po něm chtělo.
final class FakeRepoCheckout: RepoCheckout, @unchecked Sendable {
    private let tracked: [RepoID: [Int]]
    private let lock = NSLock()
    private var forgotten: [PRIdentifier] = []

    init(tracked: [RepoID: [Int]] = [:]) {
        self.tracked = tracked
    }

    private var pruned: [RepoID] = []

    var forgottenPullRequests: [PRIdentifier] { lock.withLock { forgotten } }
    var prunedRepositories: [RepoID] { lock.withLock { pruned } }

    func prepare(_ repo: RepoID) async throws -> URL { URL(filePath: "/tmp/\(repo)") }

    func worktree(for pr: PRIdentifier, at headSha: String) async throws -> URL {
        URL(filePath: "/tmp/\(pr)-\(headSha)")
    }

    func removeWorktree(for pr: PRIdentifier, at headSha: String) async throws {}

    func forgetPullRequest(_ pr: PRIdentifier) async throws {
        lock.withLock { forgotten.append(pr) }
    }

    func trackedPullRequests(in repo: RepoID) async throws -> [Int] { tracked[repo] ?? [] }

    func pruneWorktrees(in repo: RepoID) async throws {
        lock.withLock { pruned.append(repo) }
    }
}
