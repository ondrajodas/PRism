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
        let arguments = ["search", "prs"] + GhSearchQuery.arguments(from: query) + [
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

    /// `gh pr checks` končí **nenulovým kódem, když něco spadlo** — a to není chyba volání,
    /// ale výsledek, kvůli kterému se ptáme. Selhání se proto rozlišuje podle toho, jestli
    /// dorazil rozumný JSON; prázdný výstup u PR bez checků taky není chyba.
    func fetchChecks(id: PRIdentifier) async throws -> [PullRequestCheck] {
        let arguments = [
            "pr", "checks", String(id.number),
            "--repo", id.repo.description,
            "--json", "name,state,bucket,link,startedAt,completedAt",
        ]
        // Nenulový kód znamená „něco spadlo“, ne selhání volání — a `gh` v tu chvíli JSON
        // **na stdout stejně vypíše**. Rozlišuje se tedy podle výstupu, ne podle kódu.
        let output = (try? await run(arguments)) ?? ""
        guard !output.isEmpty else { return [] }
        do {
            return try GhOutput.decoder.decode([GhCheck].self, from: Data(output.utf8)).map(\.check)
        } catch {
            throw GitHubError.malformedOutput("Výstupu gh pr checks nerozumím: \(error)")
        }
    }

    func fetchDiff(id: PRIdentifier) async throws -> String {
        // `--color never` je pojistka proti defaultu `auto`: kdyby `gh` usoudil, že píše
        // na terminál, přišly by v diffu ANSI escape sekvence.
        try await run([
            "pr", "diff", String(id.number),
            "--repo", id.repo.description,
            "--color", "never",
        ])
    }

    func fetchFile(id: PRIdentifier, path: String) async throws -> String {
        // `refs/pull/<n>/head` má na GitHubu každý PR včetně forků, takže se `headSha`
        // shánět nemusí — ověřeno na živém API. Cesta se procentuje: mezera v názvu
        // souboru by jinak URL rozbila.
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return try await run([
            "api", "repos/\(id.repo)/contents/\(encoded)?ref=refs/pull/\(id.number)/head",
            "--header", "Accept: application/vnd.github.raw",
        ])
    }

    func fetchConversation(id: PRIdentifier) async throws -> Conversation {
        let response = try await run(
            ConversationQuery.arguments(for: id),
            decodedAs: GhConversationResponse.self
        )
        return try response.conversation(id: id)
    }

    func fetchReleases() async throws -> [Release] {
        // Jedna stránka na celou historii. `per_page=100` je strop GitHubu; kdyby jich
        // někdy bylo víc, přidá se `--paginate` — dokud jich je 69, je to volání navíc za nic.
        //
        // Rozdělané (`draft`) vydání se zahazuje až v mapování: REST je nefiltruje a nám
        // je vidí, protože do vlastního repa máme zápis.
        let items = try await run([
            "api", "repos/\(Release.repository)/releases?per_page=100",
        ], decodedAs: [GhRelease].self)

        // **Neřadí se tady.** Pořadí je rozhodnutí (`Policy.sortedReleases`), ne tvar
        // odpovědi — gateway vrací, co přišlo.
        return items.compactMap { $0.release() }
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
