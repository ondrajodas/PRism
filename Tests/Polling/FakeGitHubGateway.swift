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
    /// Co vrátí `fetchFile` — v pořadí, poslední se opakuje.
    private let files: [Result<String, any Error>]
    /// Co vrátí `fetchConversation` — v pořadí, poslední se opakuje.
    private let conversations: [Result<Conversation, any Error>]
    private let lock = NSLock()
    private var asked: [String] = []
    private var detailsAsked: [PRIdentifier] = []
    private var overriddenDetail: Result<PullRequest, any Error>?
    private var diffsAsked: [PRIdentifier] = []
    private var filesAsked: [(id: PRIdentifier, path: String)] = []
    private var conversationsAsked: [PRIdentifier] = []

    init(
        _ outcomes: [Outcome],
        detail: Result<PullRequest, any Error>? = nil,
        diffs: [Result<String, any Error>] = [],
        files: [Result<String, any Error>] = [],
        conversations: [Result<Conversation, any Error>] = []
    ) {
        self.outcomes = outcomes
        self.detail = detail
        self.diffs = diffs
        self.files = files
        self.conversations = conversations
    }

    convenience init(
        always outcome: Outcome,
        detail: Result<PullRequest, any Error>? = nil,
        diffs: [Result<String, any Error>] = [],
        files: [Result<String, any Error>] = [],
        conversations: [Result<Conversation, any Error>] = []
    ) {
        self.init(
            [outcome],
            detail: detail,
            diffs: diffs,
            files: files,
            conversations: conversations
        )
    }

    /// Čím se `detail` přebije **od teď dál** — nespotřebuje se, platí pro všechna další
    /// volání. Na tom stojí testy, ve kterých PR mezi dvěma tiky dostane nový commit.
    var detailFromNowOn: Result<PullRequest, any Error>? {
        get { lock.withLock { overriddenDetail } }
        set { lock.withLock { overriddenDetail = newValue } }
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
        let answer: Result<PullRequest, any Error>? = lock.withLock {
            detailsAsked.append(id)
            return overriddenDetail ?? detail
        }
        guard let answer else { throw GitHubError.notFound("Fake gateway detail nezná.") }
        return try answer.get()
    }

    /// Na co se někdo ptal, v pořadí. Na počtu stojí test, že se obsah souboru dotahuje
    /// jednou, ne při každém rozbalení.
    var fileRequests: [(id: PRIdentifier, path: String)] { lock.withLock { filesAsked } }

    func fetchFile(id: PRIdentifier, path: String) async throws -> String {
        let index: Int = lock.withLock {
            filesAsked.append((id, path))
            return filesAsked.count - 1
        }
        guard !files.isEmpty else { throw GitHubError.notFound("Fake gateway soubor nezná.") }
        return try files[min(index, files.count - 1)].get()
    }

    func fetchDiff(id: PRIdentifier) async throws -> String {
        let index: Int = lock.withLock {
            diffsAsked.append(id)
            return diffsAsked.count - 1
        }
        guard !diffs.isEmpty else { throw GitHubError.notFound("Fake gateway diff nezná.") }
        return try diffs[min(index, diffs.count - 1)].get()
    }

    /// Na co se někdo ptal, v pořadí.
    var conversationRequests: [PRIdentifier] { lock.withLock { conversationsAsked } }

    func fetchConversation(id: PRIdentifier) async throws -> Conversation {
        let index: Int = lock.withLock {
            conversationsAsked.append(id)
            return conversationsAsked.count - 1
        }
        guard !conversations.isEmpty else {
            throw GitHubError.notFound("Fake gateway konverzaci nezná.")
        }
        return try conversations[min(index, conversations.count - 1)].get()
    }
}
