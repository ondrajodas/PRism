import Foundation

/// `GitHubGateway` nad `gh` CLI.
///
/// Aplikace nikdy nedrží GitHub token — `gh` už credential má v keychainu a my se ho jen
/// ptáme. Proto tu není nic o autentizaci kromě `checkAuth()`, který se ptá `gh`.
struct GhGateway: GitHubGateway {
    private let gh: URL
    private let runner: ProcessRunning
    private let timeout: Duration
    private let searchLimit: Int

    /// `searchLimit` je jedna stránka `gh search prs`. Sto review requestů naráz je řádově
    /// víc, než kolik jich reálně vzniká, takže stránkování by byl kód navíc bez užitku.
    init(
        gh: URL,
        runner: ProcessRunning,
        timeout: Duration = .seconds(30),
        searchLimit: Int = 100
    ) {
        self.gh = gh
        self.runner = runner
        self.timeout = timeout
        self.searchLimit = searchLimit
    }

    func checkAuth() async -> GhAuthState {
        await GhAuthCheck(runner: runner, timeout: timeout).check(gh: gh)
    }

    func searchPullRequests(query: String) async throws -> [PullRequestSummary] {
        let arguments = ["search", "prs"] + Self.tokens(of: query) + [
            "--limit", String(searchLimit),
            "--json", GhSearchItem.jsonFields,
        ]

        let items = try await run(arguments, decodedAs: [GhSearchItem].self)
        return try items.map { try $0.summary() }
    }

    func fetchDetail(id: PRIdentifier) async throws -> PullRequest {
        let arguments = [
            "pr", "view", String(id.number),
            "--repo", id.repo.description,
            "--json", GhPullRequestDetail.jsonFields,
        ]

        return try await run(arguments, decodedAs: GhPullRequestDetail.self).pullRequest(id: id)
    }

    /// Dotaz se posílá po tokenech, ne jako jeden argument. `gh search prs` bere každý
    /// argument jako jeden výraz — celý dotaz v jednom by z `review-requested:@me is:open`
    /// udělal `review-requested:"@me is:open"` a GitHub ho odmítne.
    private static func tokens(of query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func run<T: Decodable>(_ arguments: [String], decodedAs type: T.Type) async throws -> T {
        let output = try await run(arguments)
        do {
            return try GhOutput.decoder.decode(type, from: Data(output.utf8))
        } catch {
            throw GitHubError.malformedOutput("Výstupu gh nerozumím: \(error)")
        }
    }

    private func run(_ arguments: [String]) async throws -> String {
        let result: ProcessResult
        do {
            result = try await runner.run(gh, arguments: arguments, timeout: timeout)
        } catch ProcessError.timedOut {
            throw GitHubError.timedOut
        } catch ProcessError.launchFailed(let detail) {
            throw GitHubError.toolUnavailable(detail)
        } catch {
            throw GitHubError.toolUnavailable(error.localizedDescription)
        }

        guard result.exitCode == 0 else { throw GitHubError(failure: result) }
        return result.standardOutput
    }
}
