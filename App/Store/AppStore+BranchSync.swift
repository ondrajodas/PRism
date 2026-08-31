import Foundation

/// Srovnání vlastní větve se základem — `Srovnat s main` (#466).
///
/// Skládá se ze dvou kroků, které patří dvěma různým modulům, a je to schválně: **rebase je
/// lokální práce v cache** (`RepoCheckout`), **push je cesta ven** (`BranchSyncSubmission` nad
/// `BranchPushing`). Store je to jediné místo, které je spojuje — protože jedině on ví, co je
/// v panelu a jaký stav se má ukázat.
///
/// Pusher se tady **nevyrábí**: skládá se až uvnitř `BranchSyncSubmission.push`, takže store drží
/// jen cestu ke `gitu`, ke `gh` a stav (tvrdá podmínka č. 1).
extension AppStore {
    // MARK: - Čtení

    func branchSyncState(for pr: PRIdentifier) -> BranchSyncState? { branchSyncStates[pr] }

    /// Zapomene, co se posledně stalo — tlačítko `Zavřít` u hlášky v panelu.
    func clearBranchSync(for pr: PRIdentifier) {
        guard branchSyncStates[pr]?.isBusy != true else { return }
        branchSyncStates[pr] = nil
    }

    /// Hledá v cache rozdělaný rebase (#466).
    ///
    /// **Volá se při každém otevření vlastního PR**, ne jen po neúspěšném srovnání: aplikaci
    /// zabitou uprostřed rebase nemá kde nic zapsat, takže by o rozdělané práci okno po restartu
    /// mlčelo. Tichý rozdělaný stav v cache je horší než chyba — příští akce nad tím PR se nad ním
    /// zachová divně.
    ///
    /// **Nepřepisuje existující stav**: hláška po srovnání („přetlačeno 5 commitů“) i vlastní
    /// `unfinished` z právě proběhlého pokusu jsou přesnější než tenhle nález, který jména
    /// kolidujících souborů nezná.
    func findUnfinishedRebase(for pr: PRIdentifier) async {
        guard let checkout, branchSyncStates[pr] == nil else { return }
        guard await checkout.rebaseInProgress(for: pr) else { return }
        branchSyncStates[pr] = .unfinished(files: [])
    }

    // MARK: - Zápis (jediná cesta do remote)

    /// Přehraje commity nad základem a přetlačí větev.
    ///
    /// **Kontrola nabídky je tady podruhé** (poprvé ji dělá tlačítko, které je jinak zakázané):
    /// spoléhat se na to, že si to pohlídá view, je o jedno místo k zapomenutí víc. Tatáž
    /// konstrukce jako u `mergeSubmission(for:)`.
    ///
    /// **Když se hlava nezmění, nepushuje se vůbec.** Rebase nad základem, nad kterým už větev je,
    /// vydá tutéž hlavu — a push, po kterém se na remote nic nezmění, je zbytečné sáhnutí na cizí
    /// server a v panelu věta, která tvrdí víc, než co se stalo.
    func syncBranch(_ pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard let checkout, let submission = branchSyncSubmission(for: id) else {
            // Sem se z povoleného tlačítka nedá dojít — `git`, `gh` i pracovní kopii skládá tentýž
            // preflight. Kdyby přesto, **řekne se to**: mlčící tlačítko je horší než hláška.
            if branchSection(for: id)?.sync.isAllowed == true {
                branchSyncStates[id] = .failed(
                    .toolUnavailable("git nebo pracovní kopie v cache nejsou k dispozici.")
                )
            }
            return
        }

        let plan = submission.plan
        branchSyncStates[id] = .rebasing
        do {
            let outcome = try await checkout.rebase(
                id,
                at: plan.expectedRemoteSha,
                onto: plan.base
            )
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
                branchSyncStates[id] = .pushing
                _ = try await submission.push(rebased)
                branchSyncStates[id] = .pushed(replayed: rebased.replayed)
                await branchWasPushed(pullRequest)
            }
        } catch let error as BranchSyncError {
            branchSyncStates[id] = .failed(error)
        } catch let error as CheckoutError {
            branchSyncStates[id] = .failed(.failed(error.userDescription))
        } catch is CancellationError {
            // **Ne „nic se nestalo“.** Zrušit jde i během pushe, takže se nedá tvrdit, že do
            // remote nic neodešlo — tatáž úvaha jako u review a merge.
            branchSyncStates[id] = .failed(.interrupted)
        } catch {
            branchSyncStates[id] = .failed(.failed(error.localizedDescription))
        }
    }

    /// Zahodí rozdělaný rebase (`git rebase --abort`) — **jedním tlačítkem z okna**.
    ///
    /// Na remote se nesáhlo, takže není co vracet: po úspěchu se hláška zahodí celá a sekce se
    /// vrátí do stavu, ve kterém byla před pokusem.
    func discardRebase(for pr: PRIdentifier) async {
        guard let checkout else { return }
        guard branchSyncStates[pr]?.isBusy != true else { return }
        branchSyncStates[pr] = .discarding
        do {
            try await checkout.discardRebase(for: pr)
            branchSyncStates[pr] = nil
        } catch let error as CheckoutError {
            branchSyncStates[pr] = .failed(.failed(error.userDescription))
        } catch is CancellationError {
            branchSyncStates[pr] = .failed(.interrupted)
        } catch {
            branchSyncStates[pr] = .failed(.failed(error.localizedDescription))
        }
    }

    /// Složí jedno srovnání — snímek toho, co je teď v panelu. `nil` = teď to nejde.
    ///
    /// Pusher se tu **nevyrábí** — jen se předá `git`, `gh`, read-only gateway (kvůli pre-flightu),
    /// brána a moje loginy. Vzniká až v `BranchSyncSubmission.push`, viz tvrdá podmínka č. 1.
    func branchSyncSubmission(for pr: PRIdentifier) -> BranchSyncSubmission? {
        guard let git, let gh else { return nil }
        guard let section = branchSection(for: pr), section.sync.isAllowed else { return nil }
        guard let plan = section.syncPlan else { return nil }
        return BranchSyncSubmission(
            plan: plan,
            git: git,
            gh: gh,
            gateway: gateway,
            scope: publishScope,
            mine: ownLogins
        )
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
