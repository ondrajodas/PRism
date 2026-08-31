import Foundation

/// Srovnání vlastní větve se základem — `Srovnat s main` (#466).
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

    /// Přehraje commity nad základem — **a nic nepřetlačí**.
    ///
    /// **Kontrola nabídky je tady podruhé** (poprvé ji dělá tlačítko, které je jinak zakázané):
    /// spoléhat se na to, že si to pohlídá view, je o jedno místo k zapomenutí víc. Tatáž
    /// konstrukce jako u `mergeSubmission(for:)`.
    ///
    /// **Když se hlava nezmění, nekončí to mezistavem.** Rebase nad základem, nad kterým už větev
    /// je, vydá tutéž hlavu — a nabídnout k přetlačení něco, co se nezměnilo, by znamenalo sáhnout
    /// na cizí server pro nic. Proto vlastní stav, ne `rebased` s nulou.
    func syncBranch(_ pullRequest: PullRequestSummary) async {
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
            let outcome = try await checkout.rebase(id, at: plan.expectedRemoteSha, onto: plan.base)
            switch outcome {
            case .conflicted(let files, let aborted):
                // Zahozený rebase a rozdělaný rebase jsou **dva různé stavy**: z prvního plyne
                // „vyřeš to jinde“, z druhého „napřed to ukliď“.
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
        guard let section = branchSection(for: id), section.syncPlan != nil else { return nil }
        // **Jedna odpověď pro celý panel** — tatáž funkce, kterou se ptá první krok i labely,
        // ne opsaná podmínka.
        guard metadataEditing(for: id).isAllowed else { return nil }

        return BranchPushSubmission(
            pullRequest: pullRequest,
            plan: BranchPushPlan(
                pullRequest: id,
                branch: section.syncPlan?.branch ?? "",
                expectedRemoteSha: rebased.rebasedFrom,
                sha: rebased.headSha,
                worktree: rebased.worktree
            ),
            replayed: rebased.replayed,
            git: git,
            gh: gh,
            layout: cacheLayout,
            gateway: gateway,
            scope: publishScope,
            mine: ownLogins,
            afterSuccess: { [weak self] in
                self?.branchSyncStates[id] = .pushed(replayed: rebased.replayed)
                await self?.branchWasPushed(pullRequest)
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
    private func branchWasPushed(_ pullRequest: PullRequestSummary) async {
        detailStates[pullRequest.id] = nil
        branchStatuses[pullRequest.id] = nil
        await loadDetail(for: pullRequest)
        await loadBranchStatus(for: pullRequest)
    }
}
