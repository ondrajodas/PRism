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

    func fetchViewer() async throws -> String {
        // **Dekóduje se JSON, nepoužívá se `--jq .login`** (#330). `--jq` na pole, které
        // v odpovědi není, vypíše **prázdný řádek s nulovým návratovým kódem** — tedy prázdný
        // login, což je zrovna ta hodnota, která v aplikaci znamená „nevím, kdo jsem“. Takhle
        // to skončí `malformedOutput` a je z hlášky vidět, co se zkoušelo.
        let user = try await run(["api", "user"], phase: "Přihlášený účet", decodedAs: GhUser.self)
        let login = user.login.trimmingCharacters(in: .whitespacesAndNewlines)
        // Prázdný login se **nevrací**, ani když ho tak API pošle: „nevím“ se od loginu musí
        // poznat, a tady je poslední místo, kde se to dá rozlišit.
        //
        // Hláška mluví o **prázdné hodnotě**, ne o chybějícím poli: `login` je v `GhUser`
        // neoptional, takže odpověď bez něj se sem nedostane — položí ji dekodér a hláška z něj
        // nese `keyNotFound`. Sem tedy vede jedině `""` nebo samé mezery.
        guard !login.isEmpty else {
            throw GitHubError.malformedOutput("Přihlášený účet: login v odpovědi je prázdný.")
        }
        return login
    }

    func searchPullRequests(query: String) async throws -> [PullRequestSummary] {
        let arguments = ["search", "prs"] + GhSearchQuery.arguments(from: query) + [
            "--limit", String(searchLimit),
            "--json", GhSearchItem.jsonFields,
        ]

        let items = try await run(
            arguments,
            phase: "Vyhledávání pull requestů",
            decodedAs: [GhSearchItem].self
        )
        return try items.map { try $0.summary() }
    }

    func fetchDetail(id: PRIdentifier) async throws -> PullRequest {
        let arguments = [
            "pr", "view", String(id.number),
            "--repo", id.repo.description,
            "--json", GhPullRequestDetail.jsonFields,
        ]

        return try await run(arguments, phase: "Metadata pull requestu", decodedAs: GhPullRequestDetail.self)
            .pullRequest(id: id)
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
            throw GitHubError.malformedOutput("Kontroly pull requestu: \(error)")
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

    func fetchDiff(repo: RepoID, from base: String, to head: String) async throws -> String {
        // **Trojtečka schválně** — dvojtečkový rozsah `compare` nezná a vrací 404 (změřeno).
        // Proti hlavě, která je potomkem té viděné, dá trojtečka přesně to, co se pushnulo;
        // po přepsané historii by dala víc, a tam se `Ukázat, co přibylo` nenabízí
        // (`Policy.incrementalDiff`).
        try await diffText(at: "repos/\(repo)/compare/\(base)...\(head)")
    }

    func fetchDiff(repo: RepoID, commit sha: String) async throws -> String {
        // **`commits/<sha>`, ne `compare/<sha>^...<sha>`** — proč, stojí u protokolu: trojtečka
        // počítá od společného předka, takže by u sloučení ukázala i přisloučenou větev.
        try await diffText(at: "repos/\(repo)/commits/\(sha)")
    }

    /// Syrový unified diff z `gh api`. Jediný rozdíl mezi rozsahem (#284) a commitem (#317) je
    /// cesta, takže hlavička i způsob spuštění bydlí na jednom místě — dvě kopie by se rozešly
    /// při první úpravě (třeba kdyby přibyl parametr proti přejmenováním).
    private func diffText(at path: String) async throws -> String {
        try await run(["api", path, "--header", "Accept: application/vnd.github.diff"])
    }

    func fetchFile(id: PRIdentifier, path: String) async throws -> String {
        // `refs/pull/<n>/head` má na GitHubu každý PR včetně forků, takže se `headSha`
        // shánět nemusí — ověřeno na živém API.
        try await fileText(repo: id.repo, path: path, ref: "refs/pull/\(id.number)/head")
    }

    func fetchFile(repo: RepoID, path: String, at commit: String) async throws -> String {
        // Sha je platná hodnota `ref` u `contents` (ověřeno na živém API), takže se soubor dá
        // přečíst tak, jak vypadal v tom commitu — a rozbalený kontext pak sedí na čísla řádků
        // z jeho hunků.
        try await fileText(repo: repo, path: path, ref: commit)
    }

    /// Obsah souboru na dané referenci. Cesta se procentuje: mezera v názvu souboru by jinak
    /// URL rozbila.
    private func fileText(repo: RepoID, path: String, ref: String) async throws -> String {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return try await run([
            "api", "repos/\(repo)/contents/\(encoded)?ref=\(ref)",
            "--header", "Accept: application/vnd.github.raw",
        ])
    }

    func fetchConversation(id: PRIdentifier) async throws -> Conversation {
        let response = try await run(
            ConversationQuery.arguments(for: id),
            phase: "Konverzace pod pull requestem",
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
        ], phase: "Seznam vydání", decodedAs: [GhRelease].self)

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
        ], phase: "Anotace check-runu", decodedAs: [GhAnnotation].self)

        return CheckAnnotations(
            fetched: items.map(\.annotation),
            pageWasFull: items.count >= page
        )
    }

    func fetchJobLogSize(repo: RepoID, jobID: Int) async throws -> Int? {
        // `-X HEAD -i` vypíše **jen hlavičky**, takže se velikost zjistí bez stažení těla —
        // a `gh` přitom následuje redirect do Azure blobu, odkud `Content-Length` doopravdy je.
        // Bez `-i` nepřijde nic: `HEAD` nemá tělo, takže hlavičky jsou celý výstup.
        let output = try await run([
            "api", "-X", "HEAD", "-i", "repos/\(repo)/actions/jobs/\(jobID)/logs",
        ])
        switch GhResponseHeaders(output: output).contentLength {
        case .bytes(let size):
            return size
        // **„Nevím“ není chyba** (#292). Všechny čtyři důvody, proč velikost nevyšla, končí
        // stejně: velikost neznáme a rozhodne se ze stahování. Vyhodit tady chybu znamenalo, že
        // jedna hlavička vypnula konec logu u **všech** checků — a rozborem hlaviček se to dá
        // spíš minout než dotazem samotným, protože se na něm nic nespustí ani nespadne.
        case .noOutput, .httpFailure, .missingHeader, .unreadableValue:
            return nil
        }
    }

    func fetchJobLog(repo: RepoID, jobID: Int) async throws -> String {
        // Přímé API, ne `gh run view --job --log` — změřeno 1,50 s proti 4,77 s za tentýž obsah
        // (#214). Bez dekódování: odpověď je **plain text**, ne JSON.
        try await run(["api", "repos/\(repo)/actions/jobs/\(jobID)/logs"])
    }

    func fetchCommits(id: PRIdentifier) async throws -> [PullRequestCommit] {
        // `per_page=100` je strop GitHubu a `--paginate` je tu kvůli PR, které ho přerostou:
        // bez něj by přišlo **prvních třicet** (výchozí stránka) a odznak by nad stovkou commitů
        // tvrdil třicet. U běžného PR je to pořád **jedno** volání, takže se za to neplatí nic —
        // změřeno 1,20 s pro sedm commitů. Stránky `gh` slévá do jednoho pole (ověřeno na živém
        // API), takže se dekóduje pořád `[GhCommit]`.
        //
        // Sám GitHub vydá nejvýš 250 commitů na PR, ať se stránkuje jak chce; že se na ten strop
        // narazilo, se pozná z počtu a **řekne se to v tabu** (`Policy.commitsHeadline`) — jinak
        // by seznam tvrdil, že je celý.
        let items = try await run([
            "api", "repos/\(id.repo)/pulls/\(id.number)/commits?per_page=100", "--paginate",
        ], phase: "Commity pull requestu", decodedAs: [GhCommit].self)

        // **Neřadí se tady, a nikde jinde ani podle data.** GitHub vrací commity topologicky od
        // nejstaršího a přerovnat je podle času by po rebase nebo cherry-picku ten postup rozházelo.
        // Pořadí, ve kterém se kreslí, je rozhodnutí, ne tvar odpovědi: gateway vydá, co přišlo,
        // a `Policy.commitsNewestFirst` to na jednom místě **otočí** (nejnovější nahoře, #316) —
        // topologické pořadí se tím zachová, jen se čte z druhé strany. Zahazují se jen položky
        // bez sha, ze kterých se řádek udělat nedá.
        return items.compactMap(\.pullRequestCommit)
    }

    /// `phase` **není dekorace**: `Výstupu gh nerozumím. keyNotFound…` neříká, co se zkoušelo,
    /// takže se z hlášky nedá poznat ani to, která obrazovka je poloprázdná. Fáze je jediné, co
    /// k tomu volající ví a chyba sama ne.
    private func run<T: Decodable>(
        _ arguments: [String],
        phase: String,
        decodedAs type: T.Type
    ) async throws -> T {
        let output = try await run(arguments)
        do {
            return try GhOutput.decoder.decode(type, from: Data(output.utf8))
        } catch {
            throw GitHubError.malformedOutput("\(phase): \(error)")
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
