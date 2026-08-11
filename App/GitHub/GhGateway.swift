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
        // **Nenulový kód tady není chyba volání.** `gh pr checks` jím hlásí „něco spadlo“ —
        // a JSON přesto vypíše na stdout. Kdyby se šlo přes `run(_:)`, které na nenulový kód
        // vyhazuje, zahodil by se výstup **právě tehdy, když nějaký check spadl**, a blok by
        // tvrdil „žádné kontroly“ ve chvíli, kdy na nich nejvíc záleží. Nález Copilota na #209.
        let result: ProcessResult
        do {
            result = try await runner.run(gh, arguments: arguments, timeout: timeout)
        } catch ProcessError.timedOut {
            throw GitHubError.timedOut
        } catch {
            throw GitHubError.toolUnavailable(error.localizedDescription)
        }

        let output = result.standardOutput
        // Prázdný výstup = PR bez checků. To je běžný stav, ne chyba; teprve když `gh` skončí
        // nenulově **a** nic nevypíše, je to selhání, o kterém nemá smysl mlčet.
        guard !output.isEmpty else {
            guard result.exitCode == 0 else { throw GitHubError(failure: result) }
            return []
        }
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

    func fetchAnnotations(repo: RepoID, checkRunID: Int) async throws -> CheckAnnotations {
        // `per_page=100` je strop GitHubu. Bere se **jedna stránka**: víc než sto anotací na jeden
        // check nikdo nečte a stránkování by bylo volání navíc za nic — z plné stránky se místo
        // toho pozná, že jich může být víc (`mayHaveMore`).
        let page = 100
        let items = try await run([
            "api", "repos/\(repo)/check-runs/\(checkRunID)/annotations?per_page=\(page)",
        ], decodedAs: [GhAnnotation].self)

        return CheckAnnotations(
            fetched: items.map(\.annotation),
            pageWasFull: items.count >= page
        )
    }

    func fetchJobLogSize(repo: RepoID, jobID: Int) async throws -> Int {
        // `-X HEAD -i` vypíše **jen hlavičky**, takže se velikost zjistí bez stažení těla —
        // a `gh` přitom následuje redirect do Azure blobu, odkud `Content-Length` doopravdy je.
        let headers = try await run([
            "api", "-X", "HEAD", "-i", "repos/\(repo)/actions/jobs/\(jobID)/logs",
        ])
        guard let size = Self.contentLength(in: headers) else {
            // **Nehádá se.** Bez velikosti se nedá rozhodnout o stropu, a tvářit se, že log je
            // malý, znamená stáhnout osm mega na pozadí okna.
            throw GitHubError.malformedOutput("Odpověď na velikost logu neobsahuje Content-Length.")
        }
        return size
    }

    func fetchJobLog(repo: RepoID, jobID: Int) async throws -> String {
        // Přímé API, ne `gh run view --job --log` — změřeno 1,50 s proti 4,77 s za tentýž obsah
        // (#214). Bez dekódování: odpověď je **plain text**, ne JSON.
        try await run(["api", "repos/\(repo)/actions/jobs/\(jobID)/logs"])
    }

    /// `Content-Length` z vypsaných hlaviček.
    ///
    /// Bere se **poslední nenulová**: `gh -i` u redirectu vypíše hlavičky obou odpovědí a ta první
    /// (z GitHub API) má `Content-Length: 0`. Kdyby se brala první, vyšel by každý log jako prázdný
    /// — a strop by ho pustil ke stažení bez ohledu na velikost.
    static func contentLength(in headers: String) -> Int? {
        headers
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
                else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .last { $0 > 0 }
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
