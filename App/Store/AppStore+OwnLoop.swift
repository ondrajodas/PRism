import Foundation

/// Dráha smyčky vlastního PR (#508) — **jen sesbírání vstupů, rozhoduje `Policy`**.
///
/// Sedm stanic se skládá z toho, co store už drží: stav review, razítko předání (#334), stav
/// větve (#465, #466), checky, vyžádaní reviewery (#392) a nabídka merge. **Nic se kvůli dráze
/// nedotahuje navíc** — kdyby se dotahovalo, platila by se hlavička vlastního PR voláním po síti
/// za údaj, který o řádek níž stejně nikdo nemá.
///
/// **Co to stojí při překreslení, a proč se to zatím neměří.** Dvě z těch hodnot se na vlastním PR
/// počítají v témže průchodu ještě jednou — panel si bere `handoffReport(for:)` a `branchSection(for:)`
/// —, takže dráha zdvojí `Policy.handoff` a `Policy.mergeOffer`. Obojí je omezené **jedním** pull
/// requestem (jeho nálezy, vlákna a commity), takže se to k naměřeným 1,5 % vlastní práce
/// v přerovnání okna (#472) chová jako konstanta, ne jako nová třída. **Měřit to bude potřeba u #509**,
/// kde tatáž funkce poběží nad **každým řádkem** seznamu — tam už je to jiný řád a předfiltr
/// (jako `isMergeReadyForLane`) tam nejspíš bude muset být.
extension AppStore {
    /// Kde vlastní pull request stojí ve smyčce. `nil` na cizím — dráha se tam nekreslí vůbec.
    ///
    /// Bere **souhrn**, ne jen identitu: stav pull requestu (`merged`, `closed`) chodí pollingem,
    /// kdežto detail se dotahuje až při zobrazení — a nad mergnutým PR má dráha mlčet hned, ne až
    /// po dotažení detailu.
    func ownLoop(for summary: PullRequestSummary) -> OwnLoop? {
        let pr = summary.id
        let detail = detail(of: pr)
        return Policy.ownLoop(
            ownership: ownership(of: summary),
            state: summary.state,
            review: reviewState(for: pr),
            handoff: handoffReport(for: pr),
            sync: branchSyncState(for: pr),
            status: branchStatusState(for: pr),
            checks: checks[pr],
            // **`nil`, dokud se metadata nenačetla** — prázdné pole je odpověď „nikdo není
            // vyžádaný“ a smíchat ji s „ještě nevím“ je zrovna to, čemu `MetadataState` brání.
            reviewers: metadataState(for: pr)?.metadata?.reviewers,
            merge: detail.map {
                // **Týž `mergeOffer` jako sekce `Větev`**, ne vlastní seznam podmínek: dvě
                // odpovědi na „smí se to mergnout“ by se rozešly. Bez načteného detailu se
                // neskládá vůbec — vyšlo by z něj `factsMissing`, tedy totéž „nevím“ po dvou
                // průchodech mapami (tatáž úvaha jako u `isMergeReadyForLane`).
                Policy.mergeOffer(
                    editing: metadataEditing(for: pr),
                    proposal: Policy.mergeProposal(of: $0, commits: commits[pr]),
                    state: $0.state,
                    status: branchStatusState(for: pr),
                    checks: checks[pr]
                )
            } ?? .blocked([.factsMissing])
        )
    }
}
