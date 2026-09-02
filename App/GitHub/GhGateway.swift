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
    /// Jak dlouho se čeká, než se GitHubu položí druhý dotaz na líné pole `mergeable` (#465).
    ///
    /// **Parametr, ne konstanta**, aby se opakovaný dotaz dal otestovat bez čekání ve zkoušce —
    /// je to totéž, co dělá `timeout` o řádek výš.
    private let branchStatusDelay: Duration
    /// Kolik rep organizace se vypíše nejvýš (#532) — `--limit` u `gh repo list`.
    ///
    /// Tisíc, protože to je hodnota ze zákresu a `keboola` na ni **doopravdy naráží** (změřeno:
    /// přesně 1000 položek). Že se na strop došlo, se z odpovědi pozná — viz
    /// `OrganizationRepositories.hitLimit`.
    private let repositoryLimit: Int
    /// Vlastní limit pro výpis rep organizace (#532), protože se do třiceti sekund **nevejde**:
    /// změřeno 46,8 s nad `keboola`.
    ///
    /// **Parametr, ne konstanta**, ze stejného důvodu jako `branchStatusDelay` — test se nemá
    /// s čím měřit tři minuty.
    private let repositoryTimeout: Duration

    /// Kolikrát se aplikace zeptá na slévatelnost, než to vzdá (#465).
    ///
    /// Tři, a je to volba, ne měření: kolik dotazů GitHub potřebuje, se z venku zjistit nedá
    /// (v měření odpovídal usazeně hned — viz `fetchBranchStatus`). Tři znamenají dvě vteřiny
    /// čekání v tom nejhorším případě, což je pod hranicí, kdy by si člověk stihl všimnout, že
    /// panel na něco čeká. Víc by ho v „zjišťuju“ drželo dýl, než kolik stojí odpověď, kterou si
    /// umí vyžádat sám obnovením okna.
    private static let branchStatusAttempts = 3

    /// `searchLimit` je jedna stránka `gh search prs`. Sto review requestů naráz je řádově
    /// víc, než kolik jich reálně vzniká, takže stránkování by byl kód navíc bez užitku.
    init(
        gh: URL,
        runner: ProcessRunning,
        timeout: Duration = .seconds(30),
        searchLimit: Int = 100,
        branchStatusDelay: Duration = .seconds(1),
        repositoryLimit: Int = 1000,
        repositoryTimeout: Duration = .seconds(300)
    ) {
        self.gh = gh
        self.runner = runner
        self.timeout = timeout
        self.searchLimit = searchLimit
        self.branchStatusDelay = branchStatusDelay
        self.repositoryLimit = repositoryLimit
        self.repositoryTimeout = repositoryTimeout
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

    /// Hlavy víc pull requestů jedním dotazem (#420).
    ///
    /// **Nenulový kód tady není chyba volání**, a je to tentýž důvod jako u `fetchChecks(id:)`:
    /// když GitHub na jeden alias neodpoví, přiloží `errors` a `gh` skončí `1` — data ostatních
    /// aliasů ale pošle. Kdyby se šlo přes `run(_:)`, přišla by fronta o odpověď kvůli jedné PR,
    /// na kterou nevidíme, a řádek dění by se neobjevil u žádné z ostatních.
    ///
    /// Selhání se proto rozlišuje podle toho, jestli dorazil rozumný JSON: bez `data` v odpovědi
    /// je nenulový kód selhání a nulový kód nesrozumitelná odpověď.
    func fetchHeads(of ids: [PRIdentifier]) async throws -> [PRIdentifier: PullRequestHead] {
        // Prázdný dotaz se **nespouští**: `query() { }` není platný dokument a nula PR nemá co
        // vracet. Je to zároveň to, co drží „na klidný den nula volání“ — předfiltr běží
        // v `Policy.staleHeadProbe`, takže sem přijde prázdno pokaždé, když se nic nezměnilo.
        guard !ids.isEmpty else { return [:] }
        let result: ProcessResult
        do {
            result = try await runner.run(
                gh,
                arguments: PullRequestHeadsQuery.arguments(for: ids),
                timeout: timeout
            )
        } catch ProcessError.timedOut {
            throw GitHubError.timedOut
        } catch ProcessError.launchFailed(let detail) {
            throw GitHubError.toolUnavailable(detail)
        } catch {
            throw GitHubError.toolUnavailable(error.localizedDescription)
        }

        let response: GhPullRequestHeadsResponse
        do {
            response = try GhOutput.decoder.decode(
                GhPullRequestHeadsResponse.self,
                from: Data(result.standardOutput.utf8)
            )
        } catch {
            // Nenulový kód **a** nesrozumitelný výstup je selhání volání; nad nulovým kódem je to
            // odpověď, které nerozumíme — a v hlášce má být, čím se to pokazilo.
            guard result.exitCode == 0 else { throw GitHubError(failure: result) }
            throw GitHubError.malformedOutput("Hlavy pull requestů: \(error)")
        }
        // `data` je hranice mezi „částečná odpověď“ a „odpověď nedorazila“. Prázdný slovník uvnitř
        // je přitom pořád odpověď: znamená, že se o žádné z těch PR nic nedozvíme, a to volající
        // umí říct — v mapě prostě nebudou.
        guard response.data != nil else {
            guard result.exitCode == 0 else { throw GitHubError(failure: result) }
            throw GitHubError.malformedOutput("Hlavy pull requestů: v odpovědi není `data`.")
        }
        return response.heads(of: ids)
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

    func fetchMetadata(id: PRIdentifier) async throws -> PullRequestMetadata {
        let arguments = [
            "pr", "view", String(id.number),
            "--repo", id.repo.description,
            "--json", GhPullRequestMetadata.jsonFields,
        ]

        return try await run(
            arguments,
            phase: "Labely a reviewery pull requestu",
            decodedAs: GhPullRequestMetadata.self
        ).metadata()
    }

    func fetchRepositoryLabels(repo: RepoID) async throws -> [PullRequestLabel] {
        // `per_page=100` je strop GitHubu a bere se **jedna stránka**: repo se stovkou labelů je
        // řádově víc, než z čeho se v nabídce vybírá, a stránkování by bylo volání navíc za nic.
        let items = try await run([
            "api", "repos/\(repo)/labels?per_page=100",
        ], phase: "Labely repozitáře", decodedAs: [GhLabel].self)

        // **Neřadí se tady** — pořadí v nabídce je rozhodnutí, ne tvar odpovědi. GitHub vrací
        // labely abecedně, což je zrovna to, co nabídka chce; kdyby to změnil, srovná to volající.
        return items.map(\.label)
    }

    func fetchAssignableUsers(repo: RepoID) async throws -> [String] {
        try await run(
            AssignableUsersQuery.arguments(for: repo),
            phase: "Lidé, kteří na repozitář smí",
            decodedAs: GhAssignableUsersResponse.self
        ).logins()
    }

    func fetchAssignableTeams(repo: RepoID) async throws -> [String] {
        do {
            let teams = try await run([
                "api", "orgs/\(repo.owner)/teams?per_page=100",
            ], phase: "Týmy organizace", decodedAs: [GhTeam].self)
            // Slug se nechává, jak přišel — `orgs/…` dává bezpředponovou podobu, tedy tu, kterou
            // chce zápis. Řadí a čistí až `Policy`.
            return teams.map(\.slug)
        } catch GitHubError.notFound {
            // Účet bez organizace týmy nemá; 404 je tady **odpověď**, ne porucha. Ostatní chyby
            // propadnou dál — nabídka pak řekne, že se seznam nepodařilo načíst.
            return []
        }
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

    func repositories(in organization: String) async throws -> OrganizationRepositories {
        // Prázdné jméno se **neptá**: řádek v nastavení vzniká prázdný a `gh repo list ""` je
        // jistá chyba za jedno volání navíc. Je to tatáž ochrana jako u prázdného dotazu zdroje
        // (`Configuration.activeSources`) a u prázdné větve v `fetchDivergence`.
        guard !organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return OrganizationRepositories(repositories: [], hitLimit: false)
        }

        let items = try await run(
            [
                "repo", "list", organization,
                "--limit", String(repositoryLimit),
                "--json", GhRepositoryItem.jsonFields,
            ],
            phase: "Repozitáře organizace",
            decodedAs: [GhRepositoryItem].self,
            // Vlastní limit, ne ten společný: změřeno 46,8 s nad `keboola`, tedy víc než
            // půldruhého násobku výchozích třiceti sekund.
            timeout: repositoryTimeout
        )

        // **Strop se pozná z počtu, ne z hlaviček.** `gh` o dosaženém `--limit` nic neříká, takže
        // je počet položek jediné, co k tomu je — a když jich přijde tolik, kolik jich smělo přijít,
        // je pravděpodobnější, že je jich víc, než že jich je přesně tolik. Tvrdit „tolik jich je“
        // by v tom případě bylo víc, než co data unesou.
        //
        // **`>=`, ne `==`, a je to pojistka, ne nerozhodnost** (nález Copilota): dnes to vyjde
        // nastejno, protože `gh` víc než `--limit` vydat nemá. Kdyby ale vydal, `==` by ten výpis
        // vydávalo za úplný — tedy zrovna to tvrzení, kterému se tenhle příznak vyhýbá.
        return OrganizationRepositories(
            repositories: items.compactMap(\.repository),
            hitLimit: items.count >= repositoryLimit
        )
    }

    // MARK: - Slévatelnost větve (#465)

    /// Jestli se dá větev mergnout. **Ptá se opakovaně, dokud GitHub neodpoví jinak než `UNKNOWN`.**
    ///
    /// `mergeable` je u GitHubu **líné pole**: odpověď se počítá až na vyžádání a dotaz, který ji
    /// nezastihne hotovou, dostane `UNKNOWN` (v RESTu `null`). Bez druhého dotazu by tedy bylo
    /// tlačítko `Mergnout…` u čerstvého PR zašedlé podle náhody.
    ///
    /// **Co je z toho změřené a co ne** — patří sem obojí, aby se to příště nemuselo měřit znovu.
    /// Změřené je, že `UNKNOWN` je **trvalý stav mergnutého PR** (`PRism#470`, obě pole). Změřené
    /// je i to, že se `UNKNOWN` na malém repu **nepodařilo zastihnout**: na `prism-review-sandbox#8`
    /// vyšlo `MERGEABLE`/`CLEAN` hned po založení PR i hned po každém ze tří pushů, přes GraphQL
    /// (`gh pr view`) i přes REST. Opakovaný dotaz je proto pojistka proti **doloženému chování
    /// API**, ne proti stavu, který se tady povedlo vyrobit — a stojí nula, dokud odpověď chodí
    /// usazená.
    ///
    /// **Strop je `attempts`, ne čas**: dotaz sám má svůj `timeout`, takže omezovat celé kolo
    /// hodinami by znamenalo dvě meze na jednu věc. Když se to nestihne, vrátí se `UNKNOWN` —
    /// je to pořád odpověď a panel z ní udělá větu, ne prázdno.
    ///
    /// **Mergnutý a zavřený PR vrací `UNKNOWN` navždycky** (změřeno na `PRism#470`), takže se
    /// na něm vyčerpají všechny pokusy. Nevadí to: sekce `Větev` se kreslí na otevřeném PR
    /// a `Policy.mergeOffer` má stav PR mezi překážkami dřív, než se na tohle pole ptá.
    func fetchBranchStatus(id: PRIdentifier, base: String, head: String) async throws -> BranchStatus {
        var status = try await branchStatus(id: id)
        for _ in 1..<Self.branchStatusAttempts where !status.isSettled {
            try await Task.sleep(for: branchStatusDelay)
            status = try await branchStatus(id: id)
        }
        // Divergence je **druhé volání**, protože `gh pr view --json` na ni pole nemá a `compare`
        // je jen v GraphQL (#466). Neopakuje se: `compare` líné pole není, spočítá se hned.
        //
        // **Bez jména větve nebo bez hlavy se na ni neptáme.** Prázdné hodnoty by z dotazu udělaly
        // `ref(qualifiedName: "refs/heads/")`, tedy jistou chybu za jedno volání navíc; `nil`
        // divergence je přitom platná odpověď („nevím“), kterou panel umí ukázat.
        guard !base.isEmpty, !head.isEmpty else { return status }
        status.divergence = try await divergence(repo: id.repo, base: base, head: head)
        return status
    }

    func fetchDivergence(id: PRIdentifier, base: String, head: String) async throws -> BranchDivergence? {
        // Tatáž ochrana jako v `fetchBranchStatus`: prázdné hodnoty by z dotazu udělaly
        // `ref(qualifiedName: "refs/heads/")`, tedy jistou chybu za jedno volání navíc.
        guard !base.isEmpty, !head.isEmpty else { return nil }
        return try await divergence(repo: id.repo, base: base, head: head)
    }

    private func divergence(repo: RepoID, base: String, head: String) async throws -> BranchDivergence? {
        try await run(
            BranchDivergenceQuery.arguments(repo: repo, base: base, head: head),
            phase: "Poloha větve proti základu",
            decodedAs: GhBranchDivergence.self
        ).divergence
    }

    private func branchStatus(id: PRIdentifier) async throws -> BranchStatus {
        try await run([
            "pr", "view", String(id.number),
            "--repo", id.repo.description,
            "--json", GhBranchStatus.jsonFields,
        ], phase: "Slévatelnost větve", decodedAs: GhBranchStatus.self).status
    }

    /// `phase` **není dekorace**: `Výstupu gh nerozumím. keyNotFound…` neříká, co se zkoušelo,
    /// takže se z hlášky nedá poznat ani to, která obrazovka je poloprázdná. Fáze je jediné, co
    /// k tomu volající ví a chyba sama ne.
    private func run<T: Decodable>(
        _ arguments: [String],
        phase: String,
        decodedAs type: T.Type,
        timeout: Duration? = nil
    ) async throws -> T {
        let output = try await run(arguments, timeout: timeout)
        do {
            return try GhOutput.decoder.decode(type, from: Data(output.utf8))
        } catch {
            throw GitHubError.malformedOutput("\(phase): \(error)")
        }
    }

    /// `timeout` je **volitelný, ne povinný parametr u všech volajících**: jediné volání, které se
    /// do společného limitu nevejde, je výpis rep organizace (#532, změřeno 46,8 s). Kdyby ho
    /// musel předávat každý, byla by z jedné výjimky dvacet čtyři míst, kde se dá napsat jiné
    /// číslo.
    private func run(_ arguments: [String], timeout: Duration? = nil) async throws -> String {
        let result: ProcessResult
        do {
            result = try await runner.run(gh, arguments: arguments, timeout: timeout ?? self.timeout)
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
