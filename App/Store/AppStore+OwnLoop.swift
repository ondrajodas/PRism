import Foundation

/// Dráha smyčky vlastního PR (#508) — **jen sesbírání vstupů, rozhoduje `Policy`**.
///
/// Pět stanic se skládá z toho, co store už drží: stav review, razítko předání (#334), stav
/// větve (#465, #466), checky a vyžádaní reviewery (#392). **Nic se kvůli dráze nedotahuje
/// navíc** — kdyby se dotahovalo, platila by se hlavička vlastního PR voláním po síti za údaj,
/// který o řádek níž stejně nikdo nemá.
///
/// **Co to stojí při překreslení.** Jediná hodnota, která se na vlastním PR počítá v témže
/// průchodu ještě jednou, je `handoffReport(for:)` (bere si ji panel), takže dráha zdvojí
/// `Policy.handoff`. Je omezená **jedním** pull requestem (jeho nálezy, vlákna a commity), takže
/// se to k naměřeným 1,5 % vlastní práce v přerovnání okna (#472) chová jako konstanta, ne jako
/// nová třída. **Měřit to bude potřeba u #509**, kde tatáž funkce poběží nad **každým řádkem**
/// seznamu — tam už je to jiný řád a předfiltr (jako `isMergeReadyForLane`) tam nejspíš bude
/// muset být.
///
/// **`Policy.mergeOffer` se tady od čtvrtého kola #508 neskládá.** Stanice `Merge` z dráhy odešla
/// (nikdy nic neukázala, stála na celém kole), a s ní i celý ten druhý průchod mapami — merge se
/// dál skládá jedině tam, kde se merguje, tedy v sekci `Větev`.
extension AppStore {
    /// Kde vlastní pull request stojí ve smyčce. `nil` na cizím — dráha se tam nekreslí vůbec.
    ///
    /// Bere **souhrn**, ne jen identitu: stav pull requestu (`merged`, `closed`) chodí pollingem,
    /// kdežto detail se dotahuje až při zobrazení — a nad mergnutým PR má dráha mlčet hned, ne až
    /// po dotažení detailu.
    func ownLoop(for summary: PullRequestSummary) -> OwnLoop? {
        let pr = summary.id
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
            reviewers: metadataState(for: pr)?.metadata?.reviewers
        )
    }
}
