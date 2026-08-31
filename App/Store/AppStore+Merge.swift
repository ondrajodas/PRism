import Foundation

/// Sekce `Větev` a merge vlastního PR (#465).
///
/// **Čte se jen na vlastním PR**, na rozdíl od labelů a reviewerů. Je to jedno volání `gh` navíc
/// při výběru řádku a na cizím PR by se platilo za sekci, která se tam nekreslí vůbec — mergnout
/// cizí frontu se odsud nedělá nikdy (`Policy.MetadataEditing.absent`).
///
/// Zapisuje se **jedinou cestou ven** (`MergeSubmission`), a je to vědomé rozšíření tvrdé podmínky
/// č. 1 na osmou metodu — zdůvodnění je u `ReviewPublishing`. Publisher se tady **nevyrábí**:
/// skládá se až uvnitř té akce, která odesílá, takže store drží jen cestu ke `gh` a stav.
extension AppStore {
    // MARK: - Čtení

    func branchStatusState(for pr: PRIdentifier) -> BranchStatusState? { branchStatuses[pr] }

    /// Celá sekce `Větev` — stav i nabídka merge. `nil` na cizím PR.
    ///
    /// **Skládá ji `Policy`**, ne tenhle getter: řádek „srovnaná / za základem“ a zašednutí
    /// tlačítka odpovídají na tutéž otázku a dvě skládání by uměla říct každé něco jiného.
    func branchSection(for pr: PRIdentifier) -> Policy.BranchSection? {
        Policy.branchSection(
            editing: metadataEditing(for: pr),
            detail: detail(of: pr),
            commits: commits[pr],
            status: branchStatusState(for: pr),
            checks: checks[pr],
            blockingFindings: blockingFindingCount(for: pr),
            sync: branchSyncStates[pr]
        )
    }

    /// Načtený detail PR, nebo `nil`. Zvlášť proto, že `detailStates` drží i „načítá se“
    /// a „nepovedlo se“ — a z obojího plyne pro sekci `Větev` totéž: plán se nesestaví.
    private func detail(of pr: PRIdentifier) -> PullRequest? {
        guard case .loaded(let detail, _) = detailStates[pr] else { return nil }
        return detail
    }

    /// Kolik platných nálezů na tomhle PR blokuje.
    ///
    /// **Sada kategorií per repo**, ne globální: mluví se o jednom pull requestu, tak jako
    /// v řádku fronty (`queueRow(for:)`) a v panelu — kdežto karta `Blokuje` na dashboardu
    /// počítá celou frontu, a proto bere globální.
    private func blockingFindingCount(for pr: PRIdentifier) -> Int {
        guard let record = reviewRecords[pr] else { return 0 }
        return Policy.blockingCount(in: record, categories: resolved(for: pr.repo).blockingCategories)
    }

    /// Dotáhne slévatelnost větve. Načtená se drží, dokud se nezmění `updatedAt` — stejná cache
    /// jako u detailu a labelů.
    ///
    /// **Jen na vlastním PR.** Na cizím se sekce nekreslí, takže by to bylo volání za nic — a je to
    /// zrovna to volání, které si na straně GitHubu vyžádá **výpočet** (líné pole `mergeable`).
    ///
    /// **A jen na otevřeném.** Mergnutý a zavřený PR vrací `UNKNOWN` navždycky (změřeno na
    /// `PRism#470`), takže by se na něm vyčerpaly všechny pokusy včetně čekání mezi nimi — a to za
    /// odpověď, kterou `Policy.mergeOffer` stejně přebije stavem PR. Ptá se to tedy až za detailem,
    /// ze kterého je stav vidět.
    ///
    /// **Selhání se neschovává do prázdna.** „Nedá se mergnout“ a „nezjistil jsem, jestli to jde“
    /// jsou dvě různé odpovědi a u nevratné akce je ten rozdíl to podstatné: podle prvního se
    /// tlačítko zašedne s důvodem, podle druhého se nesmí tvrdit nic.
    func loadBranchStatus(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard ownership(of: id) == .mine else { return }
        guard let detail = detail(of: id), detail.state == .open || detail.state == .draft else {
            return
        }
        // Rozdělaný rebase v cache (#466) se hledá **při každém otevření vlastního PR**, ne jen po
        // neúspěšném srovnání: aplikaci zabitou uprostřed rebase nemá kde nic zapsat, takže by
        // o něm okno po restartu mlčelo — a příští akce nad tím PR by se zachovala divně.
        await findUnfinishedRebase(for: id)
        guard !hasCurrentBranchStatus(for: pullRequest) else { return }
        branchStatuses[id] = .loading

        do {
            let status = try await gateway.fetchBranchStatus(
                id: id,
                base: detail.baseRef,
                head: detail.headSha
            )
            branchStatuses[id] = .loaded(status, updatedAt: pullRequest.updatedAt)
        } catch is CancellationError {
            // Maže se **jen** rozdělaný stav: mezitím spuštěné načtení už mohlo doběhnout.
            // Odchod z obrazovky není porucha.
            if branchStatuses[id] == .loading { branchStatuses[id] = nil }
        } catch let error as GitHubError {
            branchStatuses[id] = .failed(error.userDescription)
        } catch {
            branchStatuses[id] = .failed(error.localizedDescription)
        }
    }

    // MARK: - Zápis (jediná cesta ven)

    /// Složí jeden merge — snímek toho, co je teď v panelu.
    ///
    /// `nil` znamená „mergnout teď nejde“ a tlačítko, které to volá, je v takovém stavu zakázané;
    /// kontrola je tady **podruhé** proto, že sheet se nad neproveditelným mergem nemá otevřít
    /// vůbec — a spoléhat se na to, že si to view pohlídá, je o jedno místo k zapomenutí víc.
    /// Tatáž konstrukce jako u `submission(for:)`.
    ///
    /// Publisher se tu **nevyrábí** — jen se předá `gh`, read-only gateway a brána. Vzniká až
    /// v `MergeSubmission.merge()`, viz tvrdá podmínka č. 1.
    func mergeSubmission(for pullRequest: PullRequestSummary) -> MergeSubmission? {
        let id = pullRequest.id
        guard let gh else { return nil }
        guard let section = branchSection(for: id), section.merge.isAllowed else { return nil }
        guard let plan = section.plan else { return nil }
        return MergeSubmission(
            pullRequest: pullRequest,
            plan: plan,
            gh: gh,
            gateway: gateway,
            scope: publishScope,
            afterSuccess: { [weak self] in await self?.pullRequestWasMerged(pullRequest) }
        )
    }

    /// Úklid po mergi: **zavře se záložka toho PR a jeho stav se načte znovu**.
    ///
    /// **Záložku zavírá člověk, ne polling** (#465), a v tom rozdílu je celé zdůvodnění. Pravidlo
    /// z `ContentView` — mergnutý PR jde ještě dočíst a zavřít ho má člověk, ne tik — se tím
    /// **neruší**: mluví o pollingu, tedy o PR, který ze seznamu vypadl, aniž bych s tím cokoli
    /// udělal (mergnul ho někdo jiný, odebrali mě z reviewerů). Ten si záložku drží dál a zavírá
    /// se z prázdného stavu *Pull request zmizel ze seznamu*. Tady je to opačná situace: záložku
    /// zavírá **klik na `Mergnout`**, tedy tentýž člověk tímtéž gestem, kterým ten PR dokončil.
    ///
    /// **Až po úspěchu.** Sem se po selhání nedojde vůbec — `MergeSubmission` volá úklid jedině
    /// nad `.merged` —, takže po `409`, `405` i po spadlé síti zůstává záložka i sheet s hláškou.
    /// Bez toho by se ta hláška neměla kde ukázat.
    ///
    /// **Bez ptaní, i kdyby na PR leželo rozdělané review.** `closeTab` nic nezahazuje: draft
    /// zůstává v `ReviewDraftStore` na disku a s otevřenou záložkou je zpátky, takže by dialog
    /// jen stál v cestě. Na vlastním PR se navíc draft ani nedá založit (#333), takže je to případ,
    /// který skoro nenastane — a mazat ho tady by bylo to jediné nevratné na jinak vratném
    /// zavření.
    ///
    /// **Stav PR se přesto načítá znovu.** Zavřená záložka není konec: PR zůstává v seznamu až do
    /// dalšího tiku, takže se dá otevřít znovu — a se zapamatovaným detailem by v panelu zase
    /// svítilo `Mergnout…` u něčeho, co je mergnuté. Načtením se z něj stane zašedlé tlačítko
    /// s větou „pull request není otevřený — je mergnutý“, tedy odpověď, kterou okno umí dát samo
    /// a hned.
    ///
    /// Cache se zahazuje **ručně**: detail jde podle `updatedAt` shrnutí, a to se mergem v našem
    /// seznamu nezmění. Slévatelnost se **nezahazuje do prázdna, ale nechává být** — načtený stav
    /// popisuje větev před mergem a `Policy.mergeOffer` ho stejně přebije stavem PR; nové načtení
    /// by na mergnutém PR jenom vyčerpalo pokusy o líné pole (proto ho `loadBranchStatus` na
    /// zavřeném PR nedělá vůbec).
    ///
    /// Že s detailem přijdou i checky a commity, je **cena za jednu cestu**: `loadDetail` je
    /// jediné místo, které umí detail načíst správně (razítko hlavy, zápis do dění), a duplikovat
    /// ho tady kvůli dvěma voláním navíc by znamenalo dvě skládání téhož. Merge je akce jednou za
    /// čas, ne tik pollingu.
    func pullRequestWasMerged(_ pullRequest: PullRequestSummary) async {
        // **Jako první, a synchronně**: běží to ještě v tom průchodu, ve kterém se přepnul stav
        // odeslání, takže sheet nemá jak zavřít dřív než záložka pod ním.
        closeTab(pullRequest.id)
        detailStates[pullRequest.id] = nil
        await loadDetail(for: pullRequest)
    }

    private func hasCurrentBranchStatus(for pullRequest: PullRequestSummary) -> Bool {
        guard case .loaded(_, let updatedAt) = branchStatuses[pullRequest.id] else { return false }
        return updatedAt == pullRequest.updatedAt
    }
}
