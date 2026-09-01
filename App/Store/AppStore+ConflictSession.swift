import Foundation

/// Slévání konfliktů při srovnání větve (#467) — **jediná session v téhle aplikaci, která smí
/// měnit soubory**.
///
/// **Kdo co dělá, je celý tvar téhle akce a nesmí se to slít.** Session **jen upraví soubory**
/// v pracovním stromě; `git add` a `git rebase --continue` dělá **aplikace** (`RepoCheckout`),
/// a do remote se ani jeden z nich nedostane — na to je `BranchPushing` a potvrzení. Dvě věci,
/// které commitují, by se rozešly (zadání #467).
///
/// **Store je to jediné místo, které kolo umí zopakovat**, protože jedině on vidí obojí: co
/// řekla session a co na to `git`. Proto tady, a ne v runneru ani v checkoutu.
extension AppStore {
    /// Jak dopadlo slévání. **Dva případy, ne tři** — a je to schválně: `reported` znamená
    /// „stav v panelu je už nastavený, nepřepisuj ho“, protože jedině tady se ví, co session
    /// řekla a proč se její výsledek nepřijal.
    enum ConflictLoopOutcome {
        /// Pokračuj, jako by se neslévalo — nese výsledek rebase (i doběhlý).
        case finished(RebaseOutcome)
        /// Nedopadlo to a **`branchSyncStates` je nastavený**.
        case reported
    }

    /// Nechá session slít konflikty a rebase dokončit — kolo za kolem, dokud rebase stojí.
    ///
    /// **Kol je víc než jedno, protože rebase se zastaví u každého kolizního commitu.** Strop je
    /// `Policy.maxConflictRounds` a je proti **účtu**, ne proti zacyklení: každé kolo je vlastní
    /// session, tedy vlastní útrata.
    ///
    /// Kde to skončí přiznáním, a v čem se ty případy liší:
    ///
    /// - **session psala mimo strom** — výsledek se nepřijme vůbec, `git add` neproběhne;
    /// - **v souboru zůstaly značky** (změřeno `gitem`, ne tvrzeno modelem) — ten soubor se
    ///   nezapíše a dál se nejde;
    /// - **vyčerpala se kola** — v cache leží rozdělaný rebase a řekne se to.
    ///
    /// Ve všech třech případech **rebase zůstane rozdělaný** a panel nabídne `Zahodit rebase`
    /// i terminál (#459). Uhádané slití, které projde testy a rozbije se v provozu, je horší
    /// výsledek než přiznané „na tohle nestačím“ (zadání #467).
    func resolveConflicts(
        in outcome: RebaseOutcome,
        of pullRequest: PullRequestSummary,
        plan: BranchSyncPlan,
        using checkout: any RepoCheckout
    ) async throws -> ConflictLoopOutcome {
        let id = pullRequest.id
        guard conflicts != nil, let first = Self.pendingConflict(in: outcome) else {
            // Bez resolveru, po doběhlém rebasu i nad **zahozeným** konfliktem se pokračuje jako
            // v #466. Zahozený se slít nedá: v souborech po něm nejsou žádné značky.
            return .finished(outcome)
        }
        // **Hranice cache, a tatáž kontrola jako u pushe** (`CacheFile.refusal`, tvrdá podmínka
        // č. 3). Session dostane ten strom jako **rozsah, na který smí psát**, takže cesta mimo
        // cache by znamenala povolení psát do cizího klonu. Druhý opis téhle úvahy sem nepatří.
        guard CacheFile.refusal(for: first.worktree, in: cacheLayout) == nil else {
            branchSyncStates[id] = .failed(.outsideCache(first.worktree.path(percentEncoded: false)))
            return .reported
        }

        var current = outcome
        var log = ConflictLog()

        while let step = Self.pendingConflict(in: current), log.rounds < Policy.maxConflictRounds {
            log.rounds += 1
            branchSyncStates[id] = .resolving(round: log.rounds, files: step.files)
            branchSyncActivity[id] = nil

            let result: RoundResult
            do {
                result = try await runRound(step, of: id, plan: plan, using: checkout, log: &log)
            } catch is CancellationError {
                // **Zrušení nesmí spadnout na `failed(.interrupted)`**, a je to rozdíl proti #466:
                // tehdy byl rebase volání `gitu` a po zrušení v cache nic nezůstalo. Session
                // v souborech nechá rozdělanou práci, takže po zrušení musí zůstat stav, ze kterého
                // jde **zahodit** i **otevřít terminál** — `Přerušeno.` by ta tlačítka nenabídlo
                // a rozdělaný rebase by v cache zůstal, aniž by o něm okno mluvilo.
                branchSyncStates[id] = .unresolved(files: step.files, detail: "slévání jsi zrušil")
                return .reported
            }

            switch result {
            case .rejected(let files, let detail):
                branchSyncStates[id] = .unresolved(files: files, detail: detail)
                return .reported
            case .continued(let next):
                current = next
            }
        }

        // Rebase pořád stojí — vyčerpala se kola. **V cache po tom zůstává rozdělaná práce**,
        // takže se to musí říct, ne zahodit potichu.
        if let step = Self.pendingConflict(in: current) {
            branchSyncStates[id] = .unresolved(
                files: step.files,
                detail: log.detail ?? "vyčerpala se kola (\(Policy.maxConflictRounds))"
            )
            return .reported
        }

        // Doběhlo. Účet session se **připisuje k výsledku**, ne ukládá vedle: potvrzení force pushe
        // ho vypisuje nad diffem a bez něj by o konfliktech mlčelo.
        guard case .rebased(let rebased) = current else { return .finished(current) }
        return .finished(.rebased(rebased.reporting(log.resolution)))
    }

    /// Jak dopadlo jedno kolo.
    private enum RoundResult {
        /// Rebase se posunul — doběhl, nebo stojí na dalším kolizním commitu.
        case continued(RebaseOutcome)
        /// Výsledek se **nepřijal**. Nese soubory, o kterých se to říká, a věcnou příčinu.
        case rejected(files: [String], detail: String?)
    }

    /// Jedno kolo: session slije soubory, **aplikace** je zapíše do indexu a dokončí rebase.
    private func runRound(
        _ step: (files: [String], worktree: URL),
        of id: PRIdentifier,
        plan: BranchSyncPlan,
        using checkout: any RepoCheckout,
        log: inout ConflictLog
    ) async throws -> RoundResult {
        // Volající ověřil, že resolver je — tady je to jen rozbalení bez `!`.
        guard let conflicts else { return .rejected(files: step.files, detail: nil) }

        let answer = try await conflicts.resolve(
            ConflictRequest(
                pullRequest: id,
                prompt: Policy.conflictPrompt(files: step.files, base: plan.base),
                worktree: step.worktree
            ),
            progress: { [weak self] progress in
                Task { @MainActor in self?.note(progress, about: id, worktree: step.worktree) }
            }
        )
        // Útrata se zapisuje **před** kontrolou zrušení, jako u review a rozhovoru: session, která
        // doběhla, peníze stála, ať se její práce přijme, nebo ne.
        await recordSpend(answer.usage)
        log.usage = RunUsage.summed(log.usage, answer.usage)
        try Task.checkCancellation()

        // **Zápis mimo strom je konec, ne varování.** Brána v `--allowedTools` je změřená a takový
        // pokus odmítne (viz `ConflictCommand`); kdyby se přesto stal, znamená to, že se ta brána
        // změnila — a pak se nesmí commitnout nic.
        guard answer.writesOutside.isEmpty else {
            return .rejected(
                files: step.files,
                detail: Policy.writesOutsideWorktree(answer.writesOutside)
            )
        }

        let staging = try await checkout.stageResolution(in: step.worktree, paths: step.files)
        log.absorb(answer, over: step.files, staging: staging)
        guard staging.unresolved.isEmpty else {
            return .rejected(files: staging.unresolved, detail: log.detail)
        }

        return .continued(
            try await checkout.continueRebase(
                id,
                at: plan.expectedRemoteSha,
                onto: plan.base,
                keepingConflict: true
            )
        )
    }

    /// Stojí rebase na konfliktu, který má smysl slévat? `nil` = ne.
    ///
    /// **Zahozený rebase i chybějící cesta jsou `nil`**: v prvním případě nejsou v souborech
    /// značky, ve druhém není kam poslat session.
    private static func pendingConflict(in outcome: RebaseOutcome) -> (files: [String], worktree: URL)? {
        guard case .conflicted(let files, false, .some(let worktree)) = outcome, !files.isEmpty else {
            return nil
        }
        return (files, worktree)
    }

    /// Co session zrovna dělá, do druhého řádku u hlášky.
    private func note(_ progress: ConflictProgress, about pr: PRIdentifier, worktree: URL) {
        // Došlá událost z běhu, který mezitím skončil, se zahazuje — jinak by po doběhnutí zůstal
        // viset řádek o kroku, který se hlásil naposled (tentýž vzor jako u rozhovoru).
        guard branchSyncStates[pr]?.isResolving == true else { return }
        switch progress {
        case .started: branchSyncActivity[pr] = nil
        case .attemptedTool(let tool):
            branchSyncActivity[pr] = Policy.conflictToolActivity(of: tool, inside: worktree)
        }
    }
}

/// Co se za kola slévání nasbíralo (#467).
///
/// **Vlastní typ, ne pět proměnných v cyklu**: skládá se z něj `ConflictResolution`, tedy to, co
/// se ukáže v potvrzení force pushe — a rozhodnutí „co je účet a co doklad“ má být na jednom
/// místě, ne rozsypané po `while`u.
private struct ConflictLog {
    var rounds = 0
    var usage: RunUsage?
    private var files: [ResolvedConflictFile] = []
    private var diff = ""
    private var notes: [String] = []

    /// Přibere jedno kolo. **Výpis skládá `Policy`**, ne tenhle typ: účet session se srovnává
    /// s tím, co kolidovalo podle `gitu`, a to je rozhodnutí nad daty.
    mutating func absorb(_ answer: ConflictAnswer, over conflicted: [String], staging: ConflictStaging) {
        files += Policy.resolvedFiles(
            conflicted: conflicted,
            claimed: answer.files,
            unresolvedPaths: staging.unresolved
        )
        if !staging.diff.isEmpty {
            if !diff.isEmpty { diff += "\n" }
            diff += staging.diff
        }
        // **Nedoběhlá session je poznámka, ne konec.** Mohla polovinu souborů slít správně a na
        // další vytimeoutovat; jestli se dá pokračovat, rozhoduje `git` (zůstaly značky?), ne to,
        // jak session skončila. Věta ale musí zůstat vidět — je to zaplacená informace.
        if let failure = answer.failure { notes.append(failure) }
        if let caveats = answer.caveats { notes.append(caveats) }
    }

    /// Věta k tomu, co se nepovedlo — **z toho, co session řekla**. `nil` = neřekla nic.
    var detail: String? { notes.isEmpty ? nil : notes.joined(separator: " ") }

    /// Účet do potvrzení. `nil` = **žádné kolo neproběhlo**, tedy konflikty nebyly.
    var resolution: ConflictResolution? {
        guard rounds > 0 else { return nil }
        return ConflictResolution(
            files: files,
            diff: diff,
            rounds: rounds,
            usage: usage,
            caveats: detail
        )
    }
}
