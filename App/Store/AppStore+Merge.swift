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
            sync: branchSyncStates[pr],
            // Konflikt je od #467 překážka jedině tehdy, když ho **nemá kdo slít** — tedy když
            // aplikace nenašla `claude`.
            resolvesConflicts: conflicts != nil,
            // Stav odesílání metadat (#482): `Připravit k review` jde touž branou jako labely,
            // takže se druhé odeslání nad jedním PR nenabízí.
            action: metadataActionState(for: pr)
        )
    }

    /// Je vlastní PR **bez známé překážky k merge** (#515)? Čte to deska na domácí záložce.
    ///
    /// **Předfiltr, ne úplný `branchSection`.** Deska se na to ptá u **každého** vlastního PR při
    /// každém průchodu tělem, kdežto `branchSection(for:)` k tomu skládá i řádky stavu, plán
    /// merge a nabídku rebase — tedy práci za odpověď, kterou tady nikdo nepřečte. Bez načteného
    /// detailu se `mergeOffer` neskládá vůbec: bez plánu by z něj vyšlo `factsMissing`, což je
    /// totéž `false`, jen po dvou průchodech mapami.
    ///
    /// Že brána odesílání není překážka **pull requestu**, rozhoduje `Policy.isMergeReady(_:)` —
    /// s výchozím (vypnutým) odesíláním by jinak byl pruh `K merge` navždycky prázdný.
    func isMergeReadyForLane(_ pr: PRIdentifier) -> Bool {
        guard let detail = detail(of: pr) else { return false }
        return Policy.isMergeReady(
            Policy.mergeOffer(
                editing: metadataEditing(for: pr),
                plan: Policy.mergePlan(of: detail, commits: commits[pr]),
                state: detail.state,
                status: branchStatusState(for: pr),
                checks: checks[pr],
                blockingFindings: blockingFindingCount(for: pr)
            )
        )
    }

    /// Načtený detail PR, nebo `nil`. Zvlášť proto, že `detailStates` drží i „načítá se“
    /// a „nepovedlo se“ — a z obojího plyne pro sekci `Větev` totéž: plán se nesestaví.
    ///
    /// **Ne `private`**, protože totéž potřebuje i srovnání větve (#466): hledání rozdělané práce
    /// v cache se ptá na hlavu a základ z **načteného** detailu. Dvě kopie téhle jedné podmínky by
    /// znamenaly dvě různá „nevím“ nad tou samou sekcí.
    func detail(of pr: PRIdentifier) -> PullRequest? {
        guard case .loaded(let detail, _) = detailStates[pr] else { return nil }
        return detail
    }

    /// Kolik platných nálezů na tomhle PR blokuje.
    ///
    /// **Sada kategorií per repo**, ne globální: mluví se o jednom pull requestu, tak jako
    /// v řádku fronty (`queueRow(for:)`) a v panelu — kdežto souhrn ve stavovém řádku
    /// (`Policy.summary`, do #515 i karta `Blokuje`) počítá celou frontu, a proto bere globální.
    func blockingFindingCount(for pr: PRIdentifier) -> Int {
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
        // Rozdělaná práce po srovnání větve (#466) se hledá **při každém otevření vlastního PR**,
        // ne jen po neúspěšném pokusu: aplikaci zabitou uprostřed rebase — a stejně tak zavřenou
        // mezi rebasem a potvrzením přetlačení — nemá kde nic zapsat, takže by o té práci okno po
        // restartu mlčelo a příští akce nad tím PR by se nad ní zachovala divně.
        await findUnfinishedSync(for: id)
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

    /// Přeptá se na **polohu větve proti základu** u otevřeného vlastního PR (#466, z proklikání).
    ///
    /// **Obnovuje jen levnou polovinu stavu.** Razítko `updatedAt` u `branchStatuses` se schválně
    /// **nemění** — drahá polovina (`mergeable`, `mergeStateStatus`) se tím dál obnovuje jedině
    /// tehdy, když se pohnul pull request, takže stráž z #465 zůstává, jak byla. Přepisuje se
    /// **pole `divergence` uvnitř** už načteného stavu: jeden stav, jedna cache, jen druhé volání.
    ///
    /// **Ptá se jedině tehdy, když už stav načtený je.** Když není, není co obnovovat a načte ho
    /// `loadBranchStatus` — dvě místa, která tahají tentýž stav od nuly, by znamenala dva souběžné
    /// dotazy hned po otevření PR.
    ///
    /// **Selhání nic nemaže.** Odpověď, kterou máme, je pořád lepší než prázdno, a příští tik to
    /// zkusí znovu — tatáž nesymetrie jako u razítek rozhlídky (#335). Do okna se to nehlásí:
    /// stav GitHubu drží stavový řádek z pollingu.
    func refreshOpenDivergence() async {
        guard let id = Policy.divergenceProbe(open: activeTab, ownership: { ownership(of: $0) })
        else { return }
        guard case .loaded(let status, let updatedAt) = branchStatuses[id] else { return }
        guard let detail = detail(of: id), detail.state == .open || detail.state == .draft else {
            return
        }

        let divergence: BranchDivergence?
        do {
            divergence = try await gateway.fetchDivergence(
                id: id,
                base: detail.baseRef,
                head: detail.headSha
            )
        } catch {
            // **Spolknuto schválně, a uživatel o to nepřijde.** Je to obnovení hodnoty, kterou už
            // v panelu má — ne první načtení —, takže „nepovedlo se přeptat“ nemá co nakreslit:
            // stará odpověď platí dál a příští tik to zkusí znovu. Že GitHub neodpovídá, drží
            // stavový řádek z pollingu. Tatáž nesymetrie jako u razítek rozhlídky (#335)
            // a u `refreshStaleHeads`.
            return
        }

        // Mezitím se mohlo přepnout PR nebo doběhnout plné načtení, takže se zapisuje jedině do
        // toho stavu, nad kterým se ptalo — jinak by odpověď přepsala novější data.
        guard case .loaded(let current, let currentUpdatedAt) = branchStatuses[id],
            current == status, currentUpdatedAt == updatedAt
        else { return }
        var refreshed = status
        // **`nil` se zapisuje, chyba ne** — a ten rozdíl je záměr, ne nedůslednost. `nil` je
        // odpověď („zeptal jsem se a GitHub polohu neurčil“, typicky smazaný ref), takže držet nad
        // ní starou hodnotu by znamenalo tvrdit polohu, kterou nikdo nepotvrdil. Chyba je naopak
        // „nezeptal jsem se“ — a tam je stará odpověď pořád ta nejlepší, kterou máme.
        refreshed.divergence = divergence
        branchStatuses[id] = .loaded(refreshed, updatedAt: updatedAt)
    }
}
