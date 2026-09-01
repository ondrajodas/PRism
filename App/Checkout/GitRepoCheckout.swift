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
        // Řádky přes `TextLines` (#295) — jedno místo, kde se rozhoduje, co je řádek. Tady `git`
        // `LF` posílá vždycky, ale druhá cesta k dělení je druhé místo, kde se to dá zapomenout.
        return TextLines.nonEmpty(output).compactMap { Int($0.split(separator: "/").last ?? "") }
    }

    // MARK: - Srovnání větve (#466)

    func rebase(
        _ pr: PRIdentifier,
        at headSha: String,
        onto base: String,
        keepingConflict: Bool
    ) async throws -> RebaseOutcome {
        let path = layout.syncWorktree(for: pr)
        return try await coordinator.run(key: Self.worktreeKey(path), kind: "rebase") {
            // **Základ se dotahuje pokaždé**, i když se strom dá použít znovu: rebase nad
            // zastaralým `main`em by větev srovnal s něčím, co už není. `prepare` jde přes
            // koordinátor pod **jiným** klíčem (`clone:`), takže se tím nečeká samo na sebe.
            let clone = try await prepare(pr.repo)

            // Rozdělaný rebase z minula se **nepřepisuje**: je to rozdělaná práce, o které má
            // rozhodnout člověk (zahodit tlačítkem, dokončit v terminálu) — a session ji od #467
            // dostane až tehdy, když ji vyrobil **tenhle** pokus. Rozdělaný z minula nemusí být
            // z rebase, o kterém teď rozhodujeme (jiná hlava, jiný základ), takže se nad ním
            // neplatí za slévání.
            if await hasRebaseInProgress(at: path) {
                return .conflicted(
                    files: await conflictingFiles(at: path),
                    aborted: false,
                    worktree: path
                )
            }

            let worktree = try await preparedSyncWorktree(for: pr, at: headSha, in: clone, at: path)
            return try await replay(
                in: worktree,
                from: headSha,
                onto: "refs/heads/\(base)",
                keepingConflict: keepingConflict
            )
        }
    }

    /// Zapíše slité soubory do indexu a vrátí diff toho, co z nich vzniklo (#467).
    ///
    /// **Diff se bere před `git add`**, a je to podstatné: `git diff --cached HEAD` by po zápisu
    /// obsahoval **celý** přehrávaný commit (změřeno — přibyl v něm soubor, který vůbec
    /// nekolidoval), kdežto `git diff HEAD -- <soubory>` mluví jen o kolizi. Změřeno taky, že
    /// `git diff HEAD` nad **nesloučenou** cestou vydá obyčejný dvoustranný diff, ne kombinovaný;
    /// bez toho by se výpis v potvrzení nedal číst jako diff.
    ///
    /// **Soubor se značkami se nezapisuje.** `git add` by je zanesl do commitu a rebase by
    /// **prošel** — tedy ta nejdražší podoba uhádaného slití, protože se pozná až buildem.
    func stageResolution(in worktree: URL, paths: [String]) async throws -> ConflictStaging {
        guard !paths.isEmpty else { return ConflictStaging() }
        let path = worktree.path(percentEncoded: false)
        let unresolved = paths.filter { hasConflictMarkers(in: worktree.appending(path: $0)) }
        let clean = paths.filter { !unresolved.contains($0) }
        guard !clean.isEmpty else { return ConflictStaging(unresolved: unresolved) }

        let diff = try await run(["-C", path, "diff", "HEAD", "--"] + clean)
        try await run(["-C", path, "add", "--"] + clean)
        return ConflictStaging(diff: diff, unresolved: unresolved)
    }

    func continueRebase(
        _ pr: PRIdentifier,
        at headSha: String,
        onto base: String,
        keepingConflict: Bool
    ) async throws -> RebaseOutcome {
        let path = layout.syncWorktree(for: pr)
        return try await coordinator.run(key: Self.worktreeKey(path), kind: "rebase-continue") {
            try await self.replay(
                in: path,
                from: headSha,
                onto: "refs/heads/\(base)",
                keepingConflict: keepingConflict,
                continuing: true
            )
        }
    }

    /// Zůstaly v souboru konfliktní značky?
    ///
    /// **Hledá se `<<<<<<<` a `>>>>>>>` na začátku řádku, ne `=======`.** Sedm rovnítek je
    /// v Markdownu podtržení nadpisu a v generovaných souborech oddělovač, takže by na nich test
    /// odmítal slití, které je v pořádku. Horní a dolní značku naopak `git` napíše vždycky
    /// a v běžném textu se nevyskytují.
    ///
    /// **Nepřečtený soubor se počítá za nevyřešený.** Je to jediná bezpečná odpověď: `git add`
    /// nad souborem, u kterého nevíme, co v něm je, by značky do commitu zanesl potichu.
    private func hasConflictMarkers(in file: URL) -> Bool {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return true }
        return TextLines.all(text).contains { $0.hasPrefix("<<<<<<<") || $0.hasPrefix(">>>>>>>") }
    }

    /// **Maže celý strom, ne `rebase --abort`.** Od #466 se zahazují dvě různé věci — rozdělaný
    /// rebase i přerovnaná větev, která neodešla — a `--abort` umí jen tu první: nad dokončeným
    /// rebasem by neudělal nic a v cache by zůstaly přehrané commity, přestože panel hlásí
    /// uklizeno. `git worktree remove --force --force` zvládne obojí naráz (ověřeno integračním
    /// testem, i nad stromem uprostřed rebase), takže je to jedna operace s jedním významem.
    ///
    /// **Selhání se nepolyká**: `discardWorktree` hlásí všechno kromě „nic tam nebylo“, takže se
    /// nemůže stát, že okno hlásí uklizeno a v cache zůstane rozdělaná práce.
    func discardSync(for pr: PRIdentifier) async throws {
        let path = layout.syncWorktree(for: pr)
        guard FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) else { return }
        try await coordinator.run(key: Self.worktreeKey(path), kind: "discard-sync") {
            try await discardWorktree(for: pr, at: path)
        }
    }

    func syncWorktreeState(
        for pr: PRIdentifier,
        at headSha: String,
        onto base: String
    ) async -> SyncWorktreeState {
        let path = layout.syncWorktree(for: pr)
        guard FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) else {
            return .empty
        }
        if await hasRebaseInProgress(at: path) { return .unfinishedRebase }
        // **Přerovnaná větev se pozná tím, že hlava stromu není hlavou PR.** Je to jediná
        // informace, která v cache po restartu aplikace zůstane — v `sessions.json` se tohle
        // nikam nezapisuje a zapisovat nemá: strom **je** ten záznam.
        guard let head = try? await run([
            "-C", path.path(percentEncoded: false), "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines),
            !head.isEmpty, head != headSha
        else { return .empty }
        // Počet se dopočítá z výsledku, ne z paměti. Když se nedá přečíst, je to `.empty`, ne
        // `.rebased` s nulou: nabídnout přetlačení a u toho tvrdit „nula commitů“ je horší než
        // nechat člověka spustit rebase znovu.
        // **Dva rozsahy, dvě různé veličiny** (změřeno 1 proti 2): co refu na remote chybí
        // (`headSha..HEAD`, tedy co push zanese) a kolik z toho je přehraných (`base..HEAD`).
        guard let arriving = try? await commits(in: path, from: headSha),
            let replayed = try? await commitCount(in: path, from: "refs/heads/\(base)")
        else { return .empty }
        return .rebased(
            RebasedBranch(
                worktree: path,
                headSha: head,
                rebasedFrom: headSha,
                arriving: arriving,
                replayed: replayed
            )
        )
    }

    /// Vlastní přehrání. **Konflikt se pozná podle toho, že po pádu `rebase` běží dál** — ne podle
    /// textu chyby: `git` skončí nenulově i tehdy, když je základ neznámý nebo je strom špinavý,
    /// a to jsou chyby, které se mají hlásit, ne vydávat za konflikt.
    private func replay(
        in worktree: URL,
        from headSha: String,
        onto base: String,
        keepingConflict: Bool,
        continuing: Bool = false
    ) async throws -> RebaseOutcome {
        let path = worktree.path(percentEncoded: false)
        do {
            // `GIT_EDITOR=true` je pojistka u `rebase <base>` a **nutnost u `--continue`**:
            // dokončení kolizního commitu editor zprávy spouští vždycky, takže by podproces bez
            // terminálu visel do timeoutu (změřeno na scratch repu).
            //
            // **`merge.conflictStyle=zdiff3` je tu kvůli session** (#467): značka pak nese vedle
            // obou stran i **základ**, takže se dá poznat, co která strana změnila — a to je přesně
            // to, co by si session jinak tahala `gitem`, který v její sadě nástrojů není. Předává
            // se `-c`, tedy pro jedno volání, ne zápisem do konfigurace: cizí konfigurace se
            // nepřepisuje ani ve vlastní cache.
            try await run(
                ["-C", path, "-c", "merge.conflictStyle=zdiff3", "rebase"]
                    + (continuing ? ["--continue"] : [base]),
                environment: environment.merging(["GIT_EDITOR": "true"]) { _, new in new }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard await hasRebaseInProgress(at: worktree) else { throw error }
            let files = await conflictingFiles(at: worktree)
            // **Zahodit, nebo nechat stát** — rozhoduje volající, ne tenhle řádek. Session umí
            // pracovat jedině nad rebasem, který stojí: v zahozeném žádné značky nejsou.
            var aborted = false
            if !keepingConflict {
                aborted = try await succeeds(["-C", path, "rebase", "--abort"])
            }
            return .conflicted(files: files, aborted: aborted, worktree: worktree)
        }

        let head = try await run(["-C", path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .rebased(
            RebasedBranch(
                worktree: worktree,
                headSha: head,
                rebasedFrom: headSha,
                arriving: try await commits(in: worktree, from: headSha),
                replayed: try await commitCount(in: worktree, from: base)
            )
        )
    }

    /// Kolik commitů leží nad daným bodem. **Nečte se `?? 0`**: nesrozumitelný výstup `gitu` je
    /// porucha, a nula by tvrdila „nepřehrálo se nic“ nad větví, která se přehrála celá.
    private func commitCount(in worktree: URL, from start: String) async throws -> Int {
        let output = try await run([
            "-C", worktree.path(percentEncoded: false), "rev-list", "--count", "\(start)..HEAD",
        ])
        guard let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CheckoutError.gitFailed(
                exitCode: 0,
                message: "Počet přehraných commitů nejde přečíst z „\(output)“."
            )
        }
        return count
    }

    /// Které commity **na větvi přibudou** a kolik z nich je přehraných. **Nečte se `?? []`**:
    /// nesrozumitelný výstup `gitu` je porucha, a prázdný seznam by v potvrzení tvrdil „nic
    /// neodejde“ nad větví, která se přehrála celá — u nevratné akce ten nejhorší možný omyl.
    /// Commity nad základem — sha a první řádek zprávy, **od nejstaršího**.
    ///
    /// **Jedno volání místo dvou.** Do #466 tu stál `rev-list --count`, tedy jen počet; počet se
    /// teď bere z délky seznamu, protože dvě čísla o jedné věci se umí rozejít.
    ///
    /// **`%x09` jako oddělovač, ne mezera:** tabulátor se v sha vyskytnout nemůže a v titulku ho
    /// `git` v `%s` nevydá, kdežto mezera je v titulcích samozřejmě. Řádky dělí `TextLines`
    /// (pravidlo z `CLAUDE.md`: `split(separator: "\n")` na `CRLF` nerozdělí vůbec) a titulek se
    /// sráží `String.singleLine`, protože je to cizí text.
    private func commits(in worktree: URL, from start: String) async throws -> [RebasedCommit] {
        let output = try await run([
            "-C", worktree.path(percentEncoded: false),
            "log", "--reverse", "--format=%H%x09%s", "\(start)..HEAD",
        ])
        var commits: [RebasedCommit] = []
        for line in TextLines.nonEmpty(output) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard let sha = parts.first, !sha.isEmpty else {
                throw CheckoutError.gitFailed(
                    exitCode: 0,
                    message: "Seznam přehraných commitů nejde přečíst z „\(output)“."
                )
            }
            let title = parts.count > 1 ? String(parts[1]).singleLine : ""
            commits.append(
                RebasedCommit(
                    sha: String(sha),
                    // Prázdná zpráva je platný commit, ale prázdný řádek ve výpisu „co odejde“ je
                    // díra — tak se řekne, že zpráva chybí.
                    title: title.isEmpty ? "(bez zprávy)" : title
                )
            )
        }
        return commits
    }

    /// Strom, ve kterém se srovnává. Klíčovaný **jen pull requestem**, takže se v něm dá
    /// rozdělaný rebase najít i po restartu aplikace.
    private func preparedSyncWorktree(
        for pr: PRIdentifier,
        at headSha: String,
        in clone: URL,
        at path: URL
    ) async throws -> URL {
        if await isUsableWorktree(at: path, expecting: headSha) { return path }
        // Co použitelné není, se zahodí — tak jako u stromu pro review. Rozdělaný rebase je
        // odchycený výš, takže se tudy nezahazuje rozdělaná práce.
        //
        // Přímo `discardWorktree`, ne `removeWorktree`: to jde přes koordinátor pod **stejným
        // klíčem**, pod kterým už běžíme.
        if FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) {
            try await discardWorktree(for: pr, at: path)
        }
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

    /// Běží ve stromě rebase?
    ///
    /// Ptá se `gitu` na **cestu** ke složce rozdělaného rebase, ne `FileManageru` na `.git`:
    /// u pracovního stromu leží `rebase-merge` uvnitř klonu (`<klon>/worktrees/<jméno>/`) —
    /// změřeno. `git` vrátí cestu absolutní i relativní podle toho, kde strom je, takže se
    /// relativní doplní o kořen stromu.
    ///
    /// Obě jména schválně: `rebase-merge` zakládá výchozí backend, `rebase-apply` ten starší
    /// (`git rebase --apply`), a zahodit se musí obojí.
    ///
    /// **`try?` je tady v pořádku, i když se jinak v tomhle repu nesmí**, a nestojí to na tom, že
    /// návratový typ je `Bool`. `rev-parse --git-path` je **výpočet cesty**, ne práce s daty:
    /// selže právě tehdy, když ta složka není pracovní strom `gitu` — a v tom případě v ní žádný
    /// rebase neběží, takže `false` je správná odpověď, ne spolknutá. Že by selhal proto, že `git`
    /// nejde spustit, se sem nedonese: `rebase` začíná `prepare`m, který na tom padne dřív.
    private func hasRebaseInProgress(at worktree: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: worktree.path(percentEncoded: false)) else {
            return false
        }
        for directory in ["rebase-merge", "rebase-apply"] {
            guard let path = try? await run([
                "-C", worktree.path(percentEncoded: false), "rev-parse", "--git-path", directory,
            ]) else { continue }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let resolved = trimmed.hasPrefix("/")
                ? URL(filePath: trimmed)
                : worktree.appending(path: trimmed)
            if FileManager.default.fileExists(atPath: resolved.path(percentEncoded: false)) {
                return true
            }
        }
        return false
    }

    /// Které soubory se nepodařilo slít. **Prázdný seznam je odpověď „nevím“**, ne „žádné“ —
    /// věta v okně to rozlišuje (`BranchSyncState.sentence` píše `soubory nezjištěny`).
    ///
    /// `try?` je tady v pořádku, i když se jinak v tomhle repu nesmí: **volá se až nad
    /// konfliktem, který se hlásí tak jako tak**, takže se tím neztrácí zpráva o selhání, jen
    /// výčet jmen. A zrušení se nepolyká doopravdy: hned po tomhle volání jde `rebase --abort`
    /// přes `succeeds`, který `CancellationError` propouští.
    private func conflictingFiles(at worktree: URL) async -> [String] {
        let output = try? await run([
            "-C", worktree.path(percentEncoded: false),
            "diff", "--name-only", "--diff-filter=U",
        ])
        // Řádky přes `TextLines` (#295) — jedno místo, kde se rozhoduje, co je řádek.
        return TextLines.nonEmpty(output ?? "").map(String.init)
    }

    func trackedFiles(in worktree: URL) async throws -> [String] {
        // `-c` je sice výchozí, ale vypsané je z příkazu vidět, že jde o index, ne o to,
        // co zrovna leží na disku.
        let output = try await run(["-C", worktree.path(percentEncoded: false), "ls-files", "-c"])
        // Dělení na `CR` tady jméno souboru rozdělit nemůže: `core.quotePath` je ve výchozím stavu
        // zapnutý, takže `git ls-files` řídicí znaky **odcituje** — ověřeno na souboru
        // `a<CR>b.swift`, ze kterého vypadlo `"a\rb.swift"` s doslovným zpětným lomítkem.
        return TextLines.nonEmpty(output).map(String.init)
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
    /// aplikace token nedrží. Skládá to `GitCredentials`, protože totéž potřebuje
    /// i `GitBranchPush` (#466) a dvě opsané kopie by znamenaly dvě místa, kde se dá zapomenout
    /// na escapování.
    private var credentialConfiguration: [String] { GitCredentials.configuration(gh: gh) }

    /// Bez toho by se `git` na chybějící heslo zeptal a čekal — podproces bez terminálu
    /// by na tom visel až do timeoutu.
    private var environment: [String: String] { GitCredentials.environment }

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
