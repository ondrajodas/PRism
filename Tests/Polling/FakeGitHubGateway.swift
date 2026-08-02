import Foundation

@testable import PRism

/// Gateway, která nic nespouští — vrací předepsané odpovědi v pořadí, jak se jí volající
/// ptá. Poslední odpověď se opakuje, takže test nemusí předepisovat víc, než ho zajímá.
final class FakeGitHubGateway: GitHubGateway, @unchecked Sendable {
    typealias Outcome = Result<[PullRequestSummary], any Error>

    private let outcomes: [Outcome]
    /// Co vrátí `fetchDetail`. Detail se tahá až kvůli review, takže ho většina testů
    /// nepotřebuje a nechá ho `nil`.
    private let detail: Result<PullRequest, any Error>?
    /// Co vrátí `fetchDiff` — v pořadí, poslední se opakuje. Na střídání selhání a
    /// úspěchu stojí test, že „zkusit znovu“ opravdu načte.
    private let diffs: [Result<String, any Error>]
    private let lock = NSLock()
    private var asked: [String] = []
    private var detailsAsked: [PRIdentifier] = []
    private var diffsAsked: [PRIdentifier] = []

    init(
        _ outcomes: [Outcome],
        detail: Result<PullRequest, any Error>? = nil,
        diffs: [Result<String, any Error>] = []
    ) {
        self.outcomes = outcomes
        self.detail = detail
        self.diffs = diffs
    }

    convenience init(
        always outcome: Outcome,
        detail: Result<PullRequest, any Error>? = nil,
        diffs: [Result<String, any Error>] = []
    ) {
        self.init([outcome], detail: detail, diffs: diffs)
    }

    var detailRequests: [PRIdentifier] { lock.withLock { detailsAsked } }

    /// Kolikrát a na co se někdo ptal na diff. Počet je součást kontraktu: načtený diff
    /// se drží, takže druhý výběr téhož PR se ptát nemá.
    var diffRequests: [PRIdentifier] { lock.withLock { diffsAsked } }

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
        lock.withLock { detailsAsked.append(id) }
        guard let detail else { throw GitHubError.notFound("Fake gateway detail nezná.") }
        return try detail.get()
    }

    func fetchDiff(id: PRIdentifier) async throws -> String {
        let index: Int = lock.withLock {
            diffsAsked.append(id)
            return diffsAsked.count - 1
        }
        guard !diffs.isEmpty else { throw GitHubError.notFound("Fake gateway diff nezná.") }
        return try diffs[min(index, diffs.count - 1)].get()
    }
}
