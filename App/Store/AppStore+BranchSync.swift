import Foundation

/// Srovnání vlastní větve se základem — `Rebase` (#466).
///
/// **Dva kroky, dvě různé váhy, a je to celý tvar téhle akce.** Rebase je lokální práce v cache
/// (`RepoCheckout`), kterou lze vzít zpět, takže stojí na jedno kliknutí. Přetlačení je **nevratné**
/// a přepisuje historii větve na remote, takže si žádá **výslovné potvrzení** (`BranchPushSubmission`
/// nad `BranchPushing`) — tatáž třída jako merge. Store je to jediné místo, které ty dva kroky
/// spojuje, protože jedině on ví, co je v panelu a jaký stav se má ukázat.
///
/// Pusher se tady **nevyrábí**: skládá se až uvnitř `BranchPushSubmission.push`, takže store drží
/// jen cestu ke `gitu`, ke `gh`, cache a stav (tvrdá podmínka č. 1).
extension AppStore {
    // MARK: - Čtení

    func branchSyncState(for pr: PRIdentifier) -> BranchSyncState? { branchSyncStates[pr] }

    /// Zapomene, co se posledně stalo — tlačítko `Zavřít` u hlášky v panelu.
    ///
    /// **Nesahá na stav, ve kterém v cache něco leží.** Zavřít hlášku o přerovnané větvi, která
    /// neodešla, by tu práci schovalo, aniž by zmizela — a to je zrovna ten tichý stav, kterému se
    /// tahle akce vyhýbá. Na to je `discardSync`.
    func clearBranchSync(for pr: PRIdentifier) {
        guard let state = branchSyncStates[pr], !state.isBusy, !state.hasDiscardableWork else {
            return
        }
        branchSyncStates[pr] = nil
    }

    /// Hledá v cache rozdělanou práci po srovnání větve (#466).
    ///
    /// **Volá se při každém otevření vlastního PR**, ne jen po neúspěšném srovnání: aplikaci zabitou
    /// uprostřed rebase — a stejně tak zavřenou mezi rebasem a potvrzením přetlačení — nemá kde nic
    /// zapsat, takže by o té práci okno po restartu mlčelo. Strom v cache **je** ten záznam.
    ///
    /// Hledá se **obojí**: rozdělaný rebase i **přerovnaná větev, která neodešla**. Druhé přibylo
    /// s rozdělením akce na dva kroky a je to tatáž úvaha — tichý stav v cache je horší než chyba,
    /// protože příští akce nad tím PR se nad ním zachová divně.
    ///
    /// **Nepřepisuje existující stav**: hláška po srovnání i vlastní `unfinished` z právě proběhlého
    /// pokusu jsou přesnější než tenhle nález, který jména kolidujících souborů nezná.
    func findUnfinishedSync(for pr: PRIdentifier) async {
        guard let checkout, branchSyncStates[pr] == nil else { return }
        guard let detail = detail(of: pr), !detail.headSha.isEmpty, !detail.baseRef.isEmpty else {
            return
        }
        switch await checkout.syncWorktreeState(
            for: pr,
            at: detail.headSha,
            onto: detail.baseRef
        ) {
        case .empty: return
        case .unfinishedRebase: branchSyncStates[pr] = .unfinished(files: [])
        case .rebased(let branch): branchSyncStates[pr] = .rebased(branch)
        }
    }

    // MARK: - První krok: rebase v cache

    /// Spustí srovnání a **počká na něj** — ale ve vlastním tasku, aby šlo zrušit (#467).
    ///
    /// **Dva důvody, proč se to nedělá prostým `await` v akci tlačítka.** Za prvé slévání
    /// konfliktů je `claude` session, která běží minuty a stojí peníze, takže musí být kde vzít
    /// `cancel()` — jak pro tlačítko `Zrušit`, tak pro zavírání aplikace (#264, #351). Za druhé
    /// běh drží repo proti eviction (`busyRepositories`), a to se pozná jedině ze zapsaného tasku.
    ///
    /// **Čekání zůstává**, takže se volající ani testy nemusí měnit: `await task.value` skončí
    /// i u zrušeného tasku, jen dřív.
    func syncBranch(_ pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        // Během zavírání se nic nespouští (#264) — tatáž brána jako u review, kontroly nálezů
        // a rozhovoru. A druhé srovnání téhož PR taky ne: pracovaly by v jednom stromě.
        guard !isTerminating, branchSyncTasks[id] == nil else { return }
        // `Task<Void, Never>`, tedy bez `?` z `self?` — jinak by z uzávěru vypadlo `()?`.
        let task = Task { [weak self] in
            guard let self else { return }
            await performSync(pullRequest)
        }
        branchSyncTasks[id] = task
        await task.value
        branchSyncTasks[id] = nil
        branchSyncTail[id] = nil
    }

    /// Zrušení uživatelem — **zabije session, která slévá konflikty**.
    ///
    /// Rozdělaný rebase v cache **zůstane**: session ho tam nechala rozpracovaný a zahodit ho za
    /// člověka by znamenalo zahodit i to, co už slila. Panel to řekne (`unfinished`) a nabídne
    /// `Zahodit rebase` i terminál — tatáž volba jako u nerozřešeného konfliktu.
    ///
    /// **Zkratku `⌘.` si to nebere**, ze stejného důvodu jako `cancelAsk` (#452): jedna klávesa
    /// nesmí podle stavu zastavit jednou review a jindy něco jiného. Je to pojmenované tlačítko
    /// u té hlášky, ke které patří.
    func cancelBranchSync(for pr: PRIdentifier) {
        branchSyncTasks[pr]?.cancel()
    }

    /// Co session nad konflikty zrovna dělá. Prázdné, dokud neřekla nic.
    ///
    /// **Poslední prvek ocasu, ne vlastní záznam** (#511): u slévání konfliktů kreslí panel jednu
    /// řádku dál (#467) a druhá mapa vedle `branchSyncTail` by o jedné věci uměla tvrdit dvě.
    func branchSyncActivityLine(for pr: PRIdentifier) -> String? { branchSyncTail[pr]?.last }

    /// Posledních pár kroků agenta — **živý ocas** pod větou v sekci `Větev` (#511).
    ///
    /// Prázdné pole a `nil` jsou tady jedno a totéž („zatím nic neřekl“), takže se vrací pole:
    /// view kreslí ocas jedině, když v něm něco je, a rozlišovat dvě prázdna by bylo rozhodnutí
    /// bez následku.
    func agentTail(for pr: PRIdentifier) -> [String] { branchSyncTail[pr] ?? [] }

    /// Co o agentovi říká **řádek seznamu** (#511). `nil` = nic — cizí PR, nebo se nic neděje.
    ///
    /// **Skládá to store, ne řádek**, a je to kvůli hodinám: uplynulý čas se počítá z `time.now`,
    /// tedy z toho zdroje času, který se v testech dá nastavit — `Date()` uvnitř `body` by z toho
    /// udělal měření, které se nedá zopakovat. Rozhodnutí zůstává v `Policy`, tady je jen sběr
    /// vstupů.
    ///
    /// **Přepočítává se při každém překreslení řádku, a to je schválně.** Je to jeden `switch` nad
    /// jednou hodnotou z mapy; cache by tady stála víc pozornosti, než kolik ušetří — a hlavně by
    /// se musela vyprazdňovat každou minutu, protože v odpovědi je uplynulý čas.
    func agentRowPill(for pullRequest: PullRequestSummary) -> AgentRowPill? {
        Policy.agentRowPill(
            sync: branchSyncStates[pullRequest.id],
            ownership: ownership(of: pullRequest),
            now: time.now
        )
    }

    /// Přehraje commity nad základem — **a nic nepřetlačí**.
    ///
    /// **Kontrola nabídky je tady podruhé** (poprvé ji dělá tlačítko, které je jinak zakázané):
    /// spoléhat se na to, že si to pohlídá view, je o jedno místo k zapomenutí víc. Tatáž
    /// konstrukce jako u `mergeSubmission(for:)`.
    ///
    /// **Když se hlava nezmění, nekončí to mezistavem.** Rebase nad základem, nad kterým už větev
    /// je, vydá tutéž hlavu — a nabídnout k přetlačení něco, co se nezměnilo, by znamenalo sáhnout
    /// na cizí server pro nic. Proto vlastní stav, ne `rebased` s nulou.
    private func performSync(_ pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard let checkout, let plan = branchSyncPlan(for: id) else {
            // Sem se z povoleného tlačítka nedá dojít — `git`, `gh` i pracovní kopii skládá tentýž
            // preflight. Kdyby přesto, **řekne se to**: mlčící tlačítko je horší než hláška.
            if branchSection(for: id)?.sync.isAllowed == true {
                branchSyncStates[id] = .failed(
                    .toolUnavailable("git nebo pracovní kopie v cache nejsou k dispozici.")
                )
            }
            return
        }

        branchSyncStates[id] = .rebasing
        do {
            // **Konflikt se nechává stát, když ho má kdo slít** (#467). Bez resolveru je chování
            // to z #466: rebase se zahodí a v cache po něm nic nezůstane.
            let replayed = try await checkout.rebase(
                id,
                at: plan.expectedRemoteSha,
                onto: plan.base,
                keepingConflict: conflicts != nil
            )
            // **Slévání konfliktů** (#467) — `reported` znamená „stav je nastavený, nepřepisuj ho“:
            // co session řekla a proč se její výsledek nepřijal, se ví jedině tam.
            guard case .finished(let outcome) = try await resolveConflicts(
                in: replayed,
                of: pullRequest,
                plan: plan,
                using: checkout
            ) else { return }
            switch outcome {
            case .conflicted(let files, let aborted, _):
                // Zahozený rebase a rozdělaný rebase jsou **dva různé stavy**: z prvního plyne
                // „vyřeš to jinde“, z druhého „napřed to ukliď“. Stav po **nerozřešené session**
                // je třetí a nastavuje ho `resolveConflicts` — sem se dojde jedině tehdy, když
                // se o slévání vůbec nepokusilo.
                branchSyncStates[id] = aborted ? .conflicted(files: files) : .unfinished(files: files)
            case .rebased(let rebased):
                guard rebased.headSha != plan.expectedRemoteSha else {
                    branchSyncStates[id] = .alreadyInSync
                    return
                }
                // **Konec prvního kroku.** Do remote se nesáhlo a dál se jde jedině přes potvrzení.
                branchSyncStates[id] = .rebased(rebased)
            }
        } catch let error as BranchSyncError {
            branchSyncStates[id] = .failed(error)
        } catch let error as CheckoutError {
            branchSyncStates[id] = .failed(.failed(error.userDescription))
        } catch is CancellationError {
            // Zrušený rebase je lokální práce, takže se **dá** tvrdit, že do remote nic neodešlo —
            // na rozdíl od zrušeného pushe. Věta je přesto obecná, protože stav stromu jistý není;
            // příští pokus si ho stejně srovná (`isUsableWorktree`).
            branchSyncStates[id] = .failed(.interrupted)
        } catch {
            branchSyncStates[id] = .failed(.failed(error.localizedDescription))
        }
    }

    /// Zahodí, co po srovnání zůstalo v cache — **rozdělaný rebase i přerovnanou větev, která
    /// neodešla**, jedním tlačítkem.
    ///
    /// Na remote se nesáhlo, takže není co vracet: po úspěchu se hláška zahodí celá a sekce se vrátí
    /// do stavu, ve kterém byla před pokusem.
    func discardSync(for pr: PRIdentifier) async {
        guard let checkout else { return }
        guard branchSyncStates[pr]?.isBusy != true else { return }
        branchSyncStates[pr] = .discarding
        do {
            try await checkout.discardSync(for: pr)
            branchSyncStates[pr] = nil
            // Diff agenta (#511) mluví o commitu, který ve stromě právě přestal existovat —
            // nechat ho otevřený v tabu `Commity` by byl pohled na kód, který nikde není.
            forgetAgentDiff(in: pr)
        } catch let error as CheckoutError {
            branchSyncStates[pr] = .failed(.failed(error.userDescription))
        } catch is CancellationError {
            branchSyncStates[pr] = .failed(.interrupted)
        } catch {
            branchSyncStates[pr] = .failed(.failed(error.localizedDescription))
        }
    }

    // MARK: - Druhý krok: přetlačení (jediná cesta do remote)

    /// Složí potvrzení přetlačení — snímek toho, co leží v cache. `nil` = teď to nejde.
    ///
    /// Pusher se tu **nevyrábí** — jen se předá `git`, `gh`, cache, read-only gateway (kvůli
    /// pre-flightu), brána a moje loginy. Vzniká až v `BranchPushSubmission.push`, viz tvrdá
    /// podmínka č. 1.
    ///
    /// **Lease se skládá z hlavy, ze které se rebasovalo** (`rebased.rebasedFrom`), ne z té, kterou
    /// má detail teď. Mezi rebasem a potvrzením může být libovolně dlouhá pauza, takže se hlava PR
    /// mezitím může pohnout — a s aktuální hodnotou by lease prošel a ten nový commit přepsal.
    /// Takhle na něj narazí pre-flight (`headMoved`) a nepřetlačí nic.
    func branchPushSubmission(for pullRequest: PullRequestSummary) -> BranchPushSubmission? {
        let id = pullRequest.id
        guard let git, let gh else { return nil }
        guard let rebased = branchSyncStates[id]?.rebasedBranch else { return nil }
        // Brána a vlastnictví se ověřují **i tady**, ne jen u prvního kroku: mezi rebasem
        // a potvrzením se mohla vypnout v nastavení, a tlačítko, které skončí na bráně, je horší
        // než zašedlé. Sám pusher si ji ověří ještě jednou.
        // **Plán se rozbaluje, ne testuje na `nil`.** Do #466 tu stál `section.syncPlan != nil`
        // a jméno větve se pak bralo přes `?? ""` — fallback, který byl sice nedosažitelný, ale
        // kdyby se ten guard někdy uvolnil, složil by **potichu** plán s prázdným jménem a push
        // by mířil na `refs/heads/`. U cesty do remote je „nedosažitelné“ slabá záruka; rozbalení
        // ji dělá nemožnou.
        guard let section = branchSection(for: id), let syncPlan = section.syncPlan else {
            return nil
        }
        // **Jedna odpověď pro celý panel** — tatáž funkce, kterou se ptá první krok i labely,
        // ne opsaná podmínka.
        guard metadataEditing(for: id).isAllowed else { return nil }

        return BranchPushSubmission(
            pullRequest: pullRequest,
            plan: BranchPushPlan(
                pullRequest: id,
                branch: syncPlan.branch,
                expectedRemoteSha: rebased.rebasedFrom,
                sha: rebased.headSha,
                worktree: rebased.worktree
            ),
            arriving: rebased.arriving,
            replayed: rebased.replayed,
            base: syncPlan.base,
            // Účet session (#467) — **ze snímku, který leží ve stavu**, ne z živého dotazu. Po
            // restartu aplikace je `nil` a sheet o konfliktech mlčí: účet se z pracovního stromu
            // zrekonstruovat nedá a vymyslet se nesmí.
            resolution: rebased.resolution,
            git: git,
            gh: gh,
            layout: cacheLayout,
            gateway: gateway,
            scope: publishScope,
            mine: ownLogins,
            afterSuccess: { [weak self] head in
                self?.branchSyncStates[id] = .pushed(replayed: rebased.replayed)
                await self?.branchWasPushed(pullRequest, expecting: head)
            }
        )
    }

    /// Plán prvního kroku — co se bude přehrávat. `nil` = teď to nejde.
    func branchSyncPlan(for pr: PRIdentifier) -> BranchSyncPlan? {
        guard let section = branchSection(for: pr), section.sync.isAllowed else { return nil }
        return section.syncPlan
    }

    /// Úklid po přetlačení: **hlava se změnila, takže se detail i stav větve načtou znovu**.
    ///
    /// Záložka se **nezavírá**, na rozdíl od merge (#465): pull request žije dál a člověk na něm
    /// obvykle pokračuje. Nálezy se překlíčováním hlavy stanou zastaralými samy (tvrdá podmínka
    /// č. 5) — je to tatáž cesta jako po pushi z terminálu, jen se nečeká na tik pollingu.
    ///
    /// Cache se zahazuje **ručně**: detail jde podle `updatedAt` shrnutí, a to se v našem seznamu
    /// změní až dalším tikem.
    private func branchWasPushed(_ pullRequest: PullRequestSummary, expecting head: String) async {
        // **Napřed se počká na hlavu, teprve pak se tahá detail.** Obráceně to nešlo: objekt pull
        // requestu je po force pushi 1,45–2,16 s nekonzistentní (změřeno, viz
        // `Policy.awaitsPushedHead`), takže detail načtený hned po acku pushe nese **starou**
        // hlavu — a merge s ní skončí na `409`, protože ji posílá v payloadu.
        await awaitPushedHead(head, for: pullRequest.id)
        detailStates[pullRequest.id] = nil
        branchStatuses[pullRequest.id] = nil
        await loadDetail(for: pullRequest)
        await loadBranchStatus(for: pullRequest)
    }

    /// Ptá se na **hlavu**, dokud pull request nehlásí tu, kterou jsme pushnuli.
    ///
    /// **`fetchHeads`, ne `fetchDetail`** — je to `cost = 1` a jeden dotaz, kdežto plný detail
    /// s sebou tahá checky, commity i labely. Čeká se na jednu hodnotu, tak se ptá jen na ni;
    /// plný detail se pak načte **jednou**, tou jedinou cestou, která to umí správně.
    ///
    /// **Na `mergeable` se tady nečeká vůbec**, a je to schválně: usadí se dřív než dorazí hlava
    /// (0,65 s proti 1,45 s), takže by to byla hotová odpověď o **starém** commitu. Jak dorazí
    /// hlava, je celý objekt konzistentní a `loadBranchStatus` si zbytek dořeší svými pokusy.
    ///
    /// **Selhání dotazu čekání ukončí.** Nemá cenu opakovat něco, co spadlo na síti — a hlavně:
    /// „nezeptal jsem se“ není „hlava nedorazila“. Zbytek dopadne na `loadDetail` a příští tik.
    private func awaitPushedHead(_ head: String, for id: PRIdentifier) async {
        var seen: String?
        for attempt in 0... {
            guard Policy.awaitsPushedHead(expected: head, actual: seen, attempt: attempt) else {
                return
            }
            if attempt > 0 { try? await Task.sleep(for: Policy.pushedHeadRetryDelay) }
            guard let heads = try? await gateway.fetchHeads(of: [id]) else { return }
            seen = heads[id]?.sha
        }
    }
}
