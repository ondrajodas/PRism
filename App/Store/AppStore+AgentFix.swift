import Foundation

/// Agent, který opraví **vlastní** PR po cizím review (#510) — a jediná session v téhle aplikaci,
/// která startuje **bez kliknutí**.
///
/// **Co je na tom nové, je spouštěč, ne to, co session smí.** Sada povolení je doslova ta z #467
/// (`AgentFixCommand` ji bere z `ConflictCommand`), commituje **aplikace** a do remote se sáhne
/// jedině potvrzením force pushe (#466). Tvrdá podmínka č. 1 se tedy nemění vůbec, č. 2 dostává
/// **větu o spouštěči**: bez kliknutí se smí startovat jedině nad stromem `-sync` **vlastního** PR
/// a jedině po **cizí** aktivitě.
///
/// **Čtyři brány, každá jinde a každá se dá zkontrolovat zvlášť:**
///
/// 1. `Policy.agentFix(…)` — vlastnictví, `autoAgent`, stav PR, je co opravovat, běží už něco;
/// 2. **stav stromu `-sync`** — nad rozdělanou prací se nespouští nic, o té rozhoduje člověk;
/// 3. **denní rozpočet** (`autoRunsPerDay`), tentýž jako u automatu review — je to jeden společný
///    limit, protože dvě poloviny by dohromady byly dvojnásobek;
/// 4. **druhá vrstva po běhu** — co session zkusila zapsat mimo strom, se čte ze streamu a
///    výsledek se pak **nepřijme**.
///
/// **Zápis do `branchSyncTasks` a `branchSyncStates` je schválně**, ne vlastní dvojice map: agent
/// i `Rebase` pracují v **jednom** stromě, takže se nesmí potkat — a jedna mapa je jediný způsob,
/// jak to zaručit i po přidání třetí akce. Vedlejším efektem je, že agent drží repo proti eviction
/// (`busyRepositories`) a že ho zavírání aplikace zabije (#264), obojí bez řádku kódu navíc.
extension AppStore {
    /// Vyřídí cizí aktivitu na jednom vlastním PR (#510). Volá se z rozhlídky po tiku.
    ///
    /// **Razítko se posouvá při startu, ne po doběhnutí.** Kdyby se posouvalo až po úspěchu, běh,
    /// který skončil chybou, by se pouštěl **při každém tiku** — tedy nekonečná řada session za
    /// peníze nad zpětnou vazbou, kterou model neumí vyřídit. Takhle se za jednu zpětnou vazbu
    /// zaplatí jednou a co se nepovedlo, je vidět v panelu.
    ///
    /// **Podnět, který přijde za běhu, se nezahodí**: jeho datum je novější než razítko, takže ho
    /// příští tik uvidí znovu — a tehdy už session neběží. To je celé „zařadí se do fronty“.
    func startAgentFix(on pr: PRIdentifier) async {
        guard let summary = pullRequests.first(where: { $0.id == pr }) else { return }
        // **Chybějící razítko je ticho, ne celá historie.** Při prvním setkání s PR se zasadí
        // a nespouští se nic — jinak by aplikace po startu pustila agenta na měsíc starou diskuzi.
        guard let since = agentFixes.lastRun(for: pr) else {
            seedAgentFixBaseline(for: pr)
            return
        }
        let activity = Policy.foreignActivity(in: conversation(for: pr), since: since)
        let decision = Policy.agentFix(
            ownership: ownership(of: summary),
            state: summary.state,
            isAllowed: resolved(for: pr.repo).autoAgent,
            activity: activity,
            // Rebase i agent pracují v jednom stromě, takže se ptáme na **oba** — `branchSyncTasks`
            // drží obojí.
            isRunning: branchSyncTasks[pr] != nil
        )
        guard decision == .start, let handled = activity.latest else { return }

        // Zavírá se aplikace (#264): pouštět session, která ji přežije, je zrovna to, co se tím
        // zavíráním zastavuje. Razítko se v tom případě **neposouvá** — podnět se vyřídí po
        // příštím startu.
        guard !isTerminating else { return }

        // Položky se vybírají **teď**, ne v tasku: skládají se z konverzace, kterou má store po
        // ruce, a druhý dotaz o tik později by mluvil o jiném materiálu, než na který se razítko
        // právě posunulo.
        let items = Policy.agentFixItems(activity, in: conversation(for: pr))
        // **Aktivita, ze které nezbude položka, session nepustí** — a razítko se přesto posune,
        // aby se to nezvažovalo při každém tiku znovu. Prázdná obálka review (schválení bez těla)
        // je pořád cizí aktivita, ale do zadání se nepočítá, takže by agent dostal text bez
        // jediného bodu a zaplatilo by se za nic. Ptá se to **bez sázení textu** (pravidlo #224);
        // celý prompt se skládá až v běhu, kde je po ruce hlava PR.
        //
        // **Před rozpočtem**, ne za ním: za běh, který se nepustí, se nemá utratit ani položka
        // denního limitu.
        guard hasAgentPromptItems(for: pr, only: items) else {
            agentFixes.record(pr, handled: handled, at: time.now)
            return
        }
        // **Až za rozhodnutím**, aby se za nespuštěný běh neplatilo, a **před spuštěním**, aby se
        // nespustil běh, na který nezbývá.
        guard await claimAgentRun() else { return }
        agentFixes.record(pr, handled: handled, at: time.now)
        // **Na běh se tady nečeká, a je to rozdíl proti `syncBranch`.** Ten pouští kliknutí, takže
        // je koho zdržet; tohle visí na **tiku pollingu** — a patnáct minut čekání uvnitř
        // `afterSuccessfulTick` by zastavilo rozhlídku, úklid cache i hlášení o zbytku fronty.
        // Task se proto **uklidí sám** a `stopReviewsBeforeTermination` na něj počká toutéž
        // smyčkou jako na rebase (#264): mapa je jedna.
        //
        // `Task<Void, Never>`, tedy bez `?` z `self?` — jinak by z uzávěru vypadlo `()?` a do
        // `branchSyncTasks` by se to nevešlo.
        branchSyncTasks[pr] = Task { [weak self] in
            guard let self else { return }
            await fix(summary, items: items)
            branchSyncTasks[pr] = nil
            branchSyncActivity[pr] = nil
        }
    }

    /// Zasadí razítko na to, co na PR **už leží** — tedy „tohle všechno se počítá za viděné“.
    ///
    /// Tatáž konstrukce jako `seedVisitBaseline(for:)` u cizí aktivity (#335) a ze stejného
    /// důvodu: „od minule“ se u PR, který jsem nikdy neviděl, nemá o co opřít. Prázdná diskuze
    /// dostane **teď**, protože razítko musí vzniknout tak jako tak — bez něj by se zasazovalo
    /// při každém tiku a agent by se nespustil nikdy.
    private func seedAgentFixBaseline(for pr: PRIdentifier) {
        let everything = Policy.foreignActivity(in: conversation(for: pr), since: .distantPast)
        agentFixes.record(pr, handled: everything.latest ?? time.now, at: time.now)
    }

    /// Sáhne si o denní rozpočet. `false` = dnes už ne.
    ///
    /// **Tentýž rozpočet jako automat review** (`autoRunsPerDay`), ne druhý vedle něj: dvě
    /// poloviny by dohromady byly dvojnásobek toho, co si člověk nastavil — a je to jedna otázka
    /// („kolik session smí za den utratit něco, co jsem nespustil“).
    private func claimAgentRun() async -> Bool {
        guard let autoRuns else { return true }
        let allowed = await autoRuns.take(limit: configuration.global.autoRunsPerDay)
        automaticRunsToday = await autoRuns.used()
        return allowed
    }

    /// Jeden běh: strom, session, a **commit, který udělá aplikace**.
    private func fix(_ pullRequest: PullRequestSummary, items: Set<String>) async {
        let id = pullRequest.id
        guard let fixer, let checkout else { return }
        // **Detail se dotahuje tady, ne v rozhlídce.** Spouštěč běží po tiku pollingu, kde je
        // v ruce jedině shrnutí (`gh search prs` hlavu ani základ nevrací, viz #4) — a bez hlavy
        // se nedá založit strom ani složit lease. Je to **čtení** a stojí jedno `gh pr view`, které
        // se navíc platí jedině tehdy, když se agent doopravdy pouští: brána, cizí aktivita
        // i rozpočet jsou vyhodnocené dřív.
        if detail(of: id) == nil { await loadDetail(for: pullRequest) }
        guard let detail = detail(of: id), !detail.headSha.isEmpty, !detail.baseRef.isEmpty else {
            // **Řekne se to**, protože ticho po spuštěném agentovi je k nerozeznání od zaseknutí.
            branchSyncStates[id] = .failed(
                .failed("detail pull requestu se nenačetl, takže agent nemá nad čím pracovat.")
            )
            return
        }
        // **Nad rozdělanou prací se nespouští nic** — o té rozhoduje člověk (`Zahodit`, terminál).
        // Ptá se `gitu`, ne paměti: aplikace mohla být mezitím zavřená a strom v cache **je** ten
        // záznam (tatáž úvaha jako `findUnfinishedSync`).
        guard await checkout.syncWorktreeState(
            for: id,
            at: detail.headSha,
            onto: detail.baseRef
        ) == .empty else {
            await findUnfinishedSync(for: id)
            return
        }

        branchSyncStates[id] = .fixing(items: items.count)
        branchSyncActivity[id] = nil
        do {
            let worktree = try await checkout.agentFixWorktree(for: id, at: detail.headSha)
            // **Hranice cache, a tatáž kontrola jako u pushe a u konfliktů** (`CacheFile.refusal`,
            // tvrdá podmínka č. 3). Session dostane ten strom jako **rozsah, na který smí psát**,
            // takže cesta mimo cache by znamenala povolení psát do cizího klonu.
            guard CacheFile.refusal(for: worktree, in: cacheLayout) == nil else {
                branchSyncStates[id] = .failed(
                    .outsideCache(worktree.path(percentEncoded: false))
                )
                return
            }
            // Zadání se skládá **toutéž cestou jako `Sestavit prompt`** (#333), jen zúžené na to,
            // co přišlo (`only:`). Druhá cesta k témuž textu by se s panelem rozešla.
            let handoff = agentPrompt(for: id, only: items)
            let answer = try await fixer.fix(
                AgentFixRequest(
                    pullRequest: id,
                    prompt: Policy.agentFixPrompt(handoff: handoff.text, base: detail.baseRef),
                    worktree: worktree
                ),
                progress: { [weak self] progress in
                    Task { @MainActor in self?.note(progress, about: id, worktree: worktree) }
                }
            )
            // Útrata se zapisuje **před** kontrolou zrušení, jako u review a konfliktů: session,
            // která doběhla, peníze stála, ať se její práce přijme, nebo ne.
            await recordSpend(answer.usage)
            try Task.checkCancellation()
            try await accept(answer, of: pullRequest, at: detail.headSha, in: worktree, using: checkout)
        } catch is CancellationError {
            // Zrušení nesmí spadnout na `failed(.interrupted)`: session mohla ve stromě nechat
            // rozdělanou práci, takže musí zůstat stav, ze kterého jde **zahodit** i **otevřít
            // terminál** (tatáž úvaha jako u konfliktů, #467).
            branchSyncStates[id] = .fixRejected(
                detail: "Agenta jsi zrušil. Co ve stromě zůstalo, zahoď, nebo si to prohlédni v terminálu."
            )
        } catch let error as CheckoutError {
            branchSyncStates[id] = .failed(.failed(error.userDescription))
        } catch {
            branchSyncStates[id] = .failed(.failed(error.localizedDescription))
        }
    }

    /// Co s výsledkem — **čtyři konce a každý je jiná věta**.
    private func accept(
        _ answer: AgentFixAnswer,
        of pullRequest: PullRequestSummary,
        at headSha: String,
        in worktree: URL,
        using checkout: any RepoCheckout
    ) async throws {
        let id = pullRequest.id
        // **Zápis mimo strom je konec, ne varování.** Brána v `--allowedTools` je změřená a takový
        // pokus odmítne (viz `ConflictCommand`); kdyby se přesto stal, znamená to, že se ta brána
        // změnila — a pak se nesmí commitnout nic. Počítají se i **odmítnuté** pokusy: otázka není
        // „povedlo se to“, ale „mířila session mimo strom“.
        guard answer.writesOutside.isEmpty else {
            branchSyncStates[id] = .fixRejected(
                detail: Policy.agentFixWritesOutside(answer.writesOutside)
            )
            return
        }
        // **Nedoběhlá session se necommituje.** Na rozdíl od konfliktů tu není `git`, který by
        // řekl, jestli je práce hotová — polovina opravy vypadá jako celá, a commitnout ji by
        // znamenalo nabídnout k přetlačení něco, co nikdo nedokončil.
        if let failure = answer.failure {
            branchSyncStates[id] = .fixRejected(
                detail: failure + " Co ve stromě zůstalo, zahoď, nebo si to prohlédni v terminálu."
            )
            return
        }
        guard let branch = try await checkout.commitAgentFix(
            for: id,
            in: worktree,
            at: headSha,
            message: Policy.agentFixCommitMessage(for: id)
        ) else {
            // Nic se nezměnilo — legitimní výsledek, po kterém v cache nic neleží.
            branchSyncStates[id] = .fixedNothing(detail: answer.skipped ?? answer.summary)
            return
        }
        // **Účet agenta se připisuje k výsledku**, ne ukládá vedle: panel i potvrzení force pushe
        // z něj berou větu o tom, co se opravilo a co agent nechal být.
        branchSyncStates[id] = .rebased(branch.reporting(fix: answer))
    }

    /// Co agent zrovna dělá, do druhého řádku u hlášky.
    private func note(_ progress: AgentFixProgress, about pr: PRIdentifier, worktree: URL) {
        // Došlá událost z běhu, který mezitím skončil, se zahazuje — jinak by po doběhnutí zůstal
        // viset řádek o kroku, který se hlásil naposled (tentýž vzor jako u konfliktů).
        guard branchSyncStates[pr]?.isFixing == true else { return }
        switch progress {
        case .started: branchSyncActivity[pr] = nil
        case .attemptedTool(let tool):
            branchSyncActivity[pr] = Policy.writingToolActivity(of: tool, inside: worktree)
        }
    }
}
