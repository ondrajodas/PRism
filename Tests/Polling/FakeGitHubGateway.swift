import Foundation

@testable import PRism

/// Gateway, která nic nespouští — vrací předepsané odpovědi v pořadí, jak se jí volající
/// ptá. Poslední odpověď se opakuje, takže test nemusí předepisovat víc, než ho zajímá.
final class FakeGitHubGateway: GitHubGateway, @unchecked Sendable {
    typealias Outcome = Result<[PullRequestSummary], any Error>

    private let outcomes: [Outcome]
    private let lock = NSLock()
    private var asked: [String] = []

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    convenience init(always outcome: Outcome) {
        self.init([outcome])
    }

    /// Dotazy v pořadí, jak přišly — na nich se pozná, že se prošly všechny zdroje.
    var queries: [String] { lock.withLock { asked } }

    var searchCount: Int { queries.count }

    func checkAuth() async -> GhAuthState { .loggedIn }

    func searchPullRequests(query: String) async throws -> [PullRequestSummary] {
        let index: Int = lock.withLock {
            asked.append(query)
            return asked.count - 1
        }
        return try (outcomes[min(index, outcomes.count - 1)]).get()
    }

    /// Polling detail netahá — SHA potřebuje až review, ne seznam.
    func fetchDetail(id: PRIdentifier) async throws -> PullRequest {
        throw GitHubError.notFound("Fake gateway detail nezná.")
    }
}
