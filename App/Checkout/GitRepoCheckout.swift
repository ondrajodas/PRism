import Foundation

/// `RepoCheckout` nad `git` CLI.
struct GitRepoCheckout: RepoCheckout {
    private let git: URL
    private let gh: URL
    private let layout: CacheLayout
    private let runner: ProcessRunning
    private let timeout: Duration
    private let remote: @Sendable (RepoID) -> String
    private let coordinator = WorkCoordinator()

    /// `remote` je švih pro integrační testy — ty klonují z `file://` scratch repa, aby
    /// nepotřebovaly síť ani přihlášení.
    init(
        git: URL,
        gh: URL,
        layout: CacheLayout = .applicationSupport,
        runner: ProcessRunning,
        timeout: Duration = .seconds(300),
        remote: @escaping @Sendable (RepoID) -> String = { "https://github.com/\($0).git" }
    ) {
        self.git = git
        self.gh = gh
        self.layout = layout
        self.runner = runner
        self.timeout = timeout
        self.remote = remote
    }

    func prepare(_ repo: RepoID) async throws -> URL {
        try await coordinator.run(key: "clone:\(repo)", kind: "clone") { try await clone(repo) }
    }

    func worktree(for pr: PRIdentifier, at headSha: String) async throws -> URL {
        let path = layout.worktree(for: pr, at: headSha)
        return try await coordinator.run(key: Self.worktreeKey(path), kind: "add") {
            try await addWorktree(for: pr, at: headSha, path: path)
        }
    }

    func removeWorktree(for pr: PRIdentifier, at headSha: String) async throws {
        let path = layout.worktree(for: pr, at: headSha)
        try await coordinator.run(key: Self.worktreeKey(path), kind: "remove") {
            try await discardWorktree(for: pr, at: path)
        }
    }

    private func discardWorktree(for pr: PRIdentifier, at path: URL) async throws {
        let clone = layout.bareClone(for: pr.repo)

        // `--force` dvakrát schválně: jedno vynutí odstranění špinavého stromu, druhé
        // odemkne zamčený. Zabitý `worktree add` po sobě nechává zámek `initializing`
        // a s jedním `--force` na něm `remove` skončí `cannot remove a locked working
        // tree` — stav by se pak nedal srovnat vůbec.
        let removed = try await succeeds([
            "-C", clone.path(percentEncoded: false),
            "worktree", "remove", "--force", "--force",
            path.path(percentEncoded: false),
        ])

        // `prune` uklidí záznamy po stromech, které zmizely bez `remove` (pád aplikace,
        // ruční smazání složky). Když klon neexistuje, není co uklízet — a úklid stromu
        // v neexistujícím klonu chybou být nemá.
        if FileManager.default.fileExists(atPath: clone.path(percentEncoded: false)) {
            try await run(["-C", clone.path(percentEncoded: false), "worktree", "prune"])
        }

        // Poslední záchrana: když `git` strom neodstranil, složka na disku by zůstala
        // a příští `add` na stejné jméno by odmítl.
        if !removed {
            try removeDirectory(at: path, describedAs: "Zbytek po worktree")
        }
    }

    /// Výpis dělá `git`, ne `FileManager`: `git gc` volné refy zabalí do `packed-refs`
    /// a složku `refs/prism/pr` přitom smaže, takže čtení adresáře by po prvním gc tiše
    /// přestalo cokoli najít. Novější `reftable` backend složku nemá vůbec.
    func trackedPullRequests(in repo: RepoID) async throws -> [Int] {
        let clone = layout.bareClone(for: repo)
        guard FileManager.default.fileExists(atPath: clone.path(percentEncoded: false)) else { return [] }
        let output = try await run([
            "-C", clone.path(percentEncoded: false),
            "for-each-ref", "--format=%(refname)", "refs/prism/pr",
        ])
        return output.split(separator: "\n").compactMap { Int($0.split(separator: "/").last ?? "") }
    }

    func trackedFiles(in worktree: URL) async throws -> [String] {
        // `-c` je sice výchozí, ale vypsané je z příkazu vidět, že jde o index, ne o to,
        // co zrovna leží na disku.
        let output = try await run(["-C", worktree.path(percentEncoded: false), "ls-files", "-c"])
        return output.split(separator: "\n").map(String.init)
    }

    func existingClone(for repo: RepoID) async -> URL? {
        hasUsableClone(for: repo) ? layout.bareClone(for: repo) : nil
    }

    func pruneWorktrees(in repo: RepoID) async throws {
        let clone = layout.bareClone(for: repo)
        guard FileManager.default.fileExists(atPath: clone.path(percentEncoded: false)) else { return }
        try await run(["-C", clone.path(percentEncoded: false), "worktree", "prune"])
    }

    func forgetPullRequest(_ pr: PRIdentifier) async throws {
        let clone = layout.bareClone(for: pr.repo)
        guard FileManager.default.fileExists(atPath: clone.path(percentEncoded: false)) else { return }
        let ref = "refs/prism/pr/\(pr.number)"

        // Nejdřív se zjistí, jestli ref vůbec je — teprve pak se maže „naostro“. Kdyby se
        // výsledek mazání jen spolkl, prošla by tudy i skutečná chyba `gitu` a ref by
        // zůstal viset, takže by `git gc` jeho objekty nikdy neuvolnil.
        let arguments = ["-C", clone.path(percentEncoded: false)]
        guard try await succeeds(arguments + ["show-ref", "--verify", "--quiet", ref]) else { return }
        try await run(arguments + ["update-ref", "-d", ref])
    }

    private func addWorktree(for pr: PRIdentifier, at headSha: String, path: URL) async throws -> URL {
        // Použitelný strom se sdílí — dva skilly nad jedním PR mají jeden checkout — a
        // hlavně se kvůli němu nemusí znovu fetchovat.
        if await isUsableWorktree(at: path, expecting: headSha) {
            // I znovupoužití je použití — bez tohohle by repo, nad kterým se denně
            // reviewuje, mělo `lastUsed` staré týdny a v LRU odešlo jako první.
            try? CacheEviction.markUsed(pr.repo, in: layout)
            return path
        }

        // Když tam něco je a použitelné to není, zahodí se to. Po zabitém `worktree add`
        // zůstane rozkopírovaná složka se zámkem, kterou `fileExists` od hotové nerozezná
        // — reviewer by četl uříznutý strom a nálezy by se naklíčovaly na `headSha` proti
        // kódu, který tam není.
        //
        // Přímo `discardWorktree`, ne `removeWorktree`: to jde přes koordinátor pod
        // **stejným klíčem**, pod kterým už běžíme — čekalo by samo na sebe.
        if FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) {
            try await discardWorktree(for: pr, at: path)
        }

        let clone = try await prepare(pr.repo)
        try await ensureCommit(headSha, of: pr, in: clone)
        try createParentDirectory(of: path)
        try await run([
            "-C", clone.path(percentEncoded: false),
        ] + credentialConfiguration + [
            "worktree", "add", "--detach",
            path.path(percentEncoded: false),
            headSha,
        ])
        return path
    }

    /// Strom je použitelný, jen když v něm `git` odpoví a stojí přesně na tom commitu.
    ///
    /// Existence složky nestačí: zabitý `add` nechá rozdělaný strom a smazaný klon nechá
    /// strom, ve kterém `git` hlásí `not a git repository`. Porovnání s `headSha` navíc
    /// pokrývá případ, kdy se dva různé commity potkají na zkráceném sha v názvu složky.
    private func isUsableWorktree(at path: URL, expecting headSha: String) async -> Bool {
        guard FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) else {
            return false
        }
        let head = try? await run(["-C", path.path(percentEncoded: false), "rev-parse", "HEAD"])
        return head?.trimmingCharacters(in: .whitespacesAndNewlines) == headSha
    }

    /// Dotáhne commit, pokud v klonu není.
    ///
    /// Vždycky přes `refs/pull/<n>/head`, ne přes samotný sha: ten ref má na GitHubu
    /// **každý** PR včetně těch z forků, kdežto `git fetch origin <sha>` potřebuje na
    /// serveru povolené `allowAnySHA1InWant`, na což spoleh není. Jedna cesta místo dvou.
    private func ensureCommit(_ sha: String, of pr: PRIdentifier, in clone: URL) async throws {
        if try await hasCommit(sha, in: clone) { return }

        try await run(["-C", clone.path(percentEncoded: false)] + credentialConfiguration + [
            "fetch", "--no-tags", "origin", "+refs/pull/\(pr.number)/head:refs/prism/pr/\(pr.number)",
        ])

        guard try await hasCommit(sha, in: clone) else {
            throw CheckoutError.commitNotFound(sha)
        }
    }

    /// Skutečně **lokální** dotaz.
    ///
    /// Bez `GIT_NO_LAZY_FETCH=1` si `cat-file` na partial klonu chybějící commit tiše
    /// dotáhne z promisor remote — takže by tahle „levná kontrola“ chodila na síť,
    /// s naším timeoutem, bez credential helperu, a fetch `refs/pull/<n>/head` pod ní
    /// by se nikdy nespustil. Commit by pak v klonu ležel bez refu, který ho drží.
    private func hasCommit(_ sha: String, in clone: URL) async throws -> Bool {
        let arguments = ["-C", clone.path(percentEncoded: false), "cat-file", "-e", "\(sha)^{commit}"]
        let local = environment.merging(["GIT_NO_LAZY_FETCH": "1"]) { _, new in new }
        return try await succeeds(arguments, environment: local)
    }

    /// Prošel příkaz? Chyba `gitu` je odpověď „ne“, ale **zrušení odpověď není** — samotné
    /// `try?` by ho spolklo a úloha by pokračovala dál, i když ji nikdo nechce.
    private func succeeds(_ arguments: [String], environment: [String: String]? = nil) async throws -> Bool {
        do {
            _ = try await run(arguments, environment: environment)
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return false
        }
    }

    private static func worktreeKey(_ path: URL) -> String {
        "worktree:\(path.path(percentEncoded: false))"
    }

    private func clone(_ repo: RepoID) async throws -> URL {
        let clone = layout.bareClone(for: repo)

        if hasUsableClone(for: repo) {
            try await run(fetchArguments(in: clone))
            // Záznam o použití rozhoduje, co z cache odejde první — proto se obnovuje
            // při každé přípravě, ne jen při klonování.
            try? CacheEviction.markUsed(repo, in: layout)
            return clone
        }

        // Cílová složka může existovat i po **přerušeném** klonu — `git` po sobě neuklidí
        // vždycky a náš timeout ho zabíjí `SIGKILL`em, takže na to není spoleh. Rozhodovat
        // se podle pouhé existence složky by znamenalo, že další pokus jde na `fetch`
        // v něčem, co repozitář není, a opakování by se z toho nikdy nezotavilo.
        try removeDirectory(at: clone, describedAs: "Zbytek po klonu")
        try createParentDirectory(of: clone)
        // Razítko se zapisuje **před** klonováním: rozklonované repo by jinak razítko
        // nemělo, v LRU vyšlo jako nejstarší a eviction by ho odstřelila uprostřed práce.
        try? CacheEviction.markUsed(repo, in: layout)
        try await run(cloneArguments(from: repo, into: clone))
        try markCloneComplete(repo)
        try? CacheEviction.markUsed(repo, in: layout)
        return clone
    }

    /// Hotový klon poznáme podle **vlastní značky**, ne podle toho, co je uvnitř.
    /// `git` zakládá `HEAD`, `config` i `refs/` hned na začátku, takže zabitý klon vypadá
    /// zvenčí jako hotový repozitář — a fetch nad ním dokonce projde, jen z klonu tiše
    /// zmizí `promisor` a partial clone přestane platit.
    private func hasUsableClone(for repo: RepoID) -> Bool {
        FileManager.default.fileExists(
            atPath: layout.cloneMarker(for: repo).path(percentEncoded: false)
        )
    }

    /// Nezdařený zápis značky je chyba, i když klon sám prošel.
    ///
    /// Původně se polykal: chybějící značka znamenala jen klonování navíc. Od chvíle, kdy
    /// nad klonem visí worktrees, to neplatí — příští `prepare` by klon bez značky smazal
    /// a stromy pod ním by zůstaly bez repozitáře. Selhat hned a hlasitě je levnější.
    private func markCloneComplete(_ repo: RepoID) throws {
        // Složka po úspěšném klonu existuje; `createDirectory` je tu proto, aby značka
        // nebyla první věc, která spadne, když se stane něco nečekaného.
        try? FileManager.default.createDirectory(
            at: layout.bareClone(for: repo),
            withIntermediateDirectories: true
        )
        let marker = layout.cloneMarker(for: repo).path(percentEncoded: false)
        guard FileManager.default.createFile(atPath: marker, contents: nil) else {
            throw CheckoutError.cacheUnavailable("Značku dokončeného klonu nejde zapsat: \(marker)")
        }
    }

    /// Partial clone: `--filter=blob:none` stáhne historii bez obsahu souborů a bloby
    /// doplní až na vyžádání. I velký monorepo se tím naklonuje v sekundách.
    private func cloneArguments(from repo: RepoID, into clone: URL) -> [String] {
        credentialConfiguration + [
            "clone", "--bare", "--filter=blob:none",
            remote(repo),
            clone.path(percentEncoded: false),
        ]
    }

    /// Refspec se musí napsat ručně. `git clone --bare` totiž **nenastaví**
    /// `remote.origin.fetch` (na rozdíl od běžného klonu i od `--mirror`), takže samotné
    /// `git fetch origin` jen zapíše `FETCH_HEAD` a větve v klonu zůstanou tam, kde byly.
    /// Odhalil to až integrační test proti skutečnému `gitu`.
    private func fetchArguments(in clone: URL) -> [String] {
        ["-C", clone.path(percentEncoded: false)] + credentialConfiguration + [
            "fetch", "--prune", "origin", "+refs/heads/*:refs/heads/*",
        ]
    }

    /// Přihlášení k privátním repům se deleguje na `gh`, stejně jako všude jinde —
    /// aplikace token nedrží.
    ///
    /// Helper se předává jako `-c` u jednoho volání, ne přes `gh auth setup-git`: ten
    /// zapisuje do **globálního** git configu uživatele, a do toho aplikace sahat nemá.
    /// `gh` se volá absolutní cestou, protože helper spouští shell, který `PATH`
    /// z GUI aplikace nezdědil.
    private var credentialConfiguration: [String] {
        // Helper spouští shell, takže cesta musí do apostrofů — a apostrof v ní se musí
        // odescapovat, jinak by je předčasně uzavřela. Cesta k `gh` sice pochází
        // z preflightu, ne od uživatele, ale skládat shellový příkaz bez escapování je
        // zvyk, který se dřív nebo později vymstí.
        let quoted = gh.path(percentEncoded: false).replacingOccurrences(of: "'", with: "'\\''")
        return ["-c", "credential.helper=!'\(quoted)' auth git-credential"]
    }

    /// Bez toho by se `git` na chybějící heslo zeptal a čekal — podproces bez terminálu
    /// by na tom visel až do timeoutu.
    private var environment: [String: String] {
        ["GIT_TERMINAL_PROMPT": "0"]
    }

    /// „Nic tam nebylo“ je normální stav, cokoli jiného ne. Spolknout selhání mazání by
    /// znamenalo, že se `git` zakousne na „destination path already exists“ a skutečná
    /// příčina (práva, zamčený soubor) se nikam nedostane.
    private func removeDirectory(at url: URL, describedAs what: String) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            throw CheckoutError.cacheUnavailable(
                "\(what) v \(url.path(percentEncoded: false)) nejde smazat: "
                    + error.localizedDescription
            )
        }
    }

    private func createParentDirectory(of clone: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: clone.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw CheckoutError.cacheUnavailable(
                "Složku v cache nejde založit: " + error.localizedDescription
            )
        }
    }

    @discardableResult
    private func run(
        _ arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> String {
        let result: ProcessResult
        do {
            result = try await runner.run(
                git,
                arguments: arguments,
                environment: environment ?? self.environment,
                timeout: timeout
            )
        } catch ProcessError.timedOut {
            throw CheckoutError.timedOut
        } catch ProcessError.launchFailed(let detail) {
            throw CheckoutError.toolUnavailable(detail)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CheckoutError.toolUnavailable(error.localizedDescription)
        }

        guard result.exitCode == 0 else { throw CheckoutError(failure: result) }
        return result.standardOutput
    }
}
