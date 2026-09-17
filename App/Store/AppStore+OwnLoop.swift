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
/// nová třída.
///
/// **V seznamu je to jiný řád, a proto se report předává** (#509). Tatáž funkce poběží nad
/// **každým** řádkem, takže zdvojení `Policy.handoff` už není konstanta — je to násobek počtu
/// vlastních PR. Řádek si report skládá tak jako tak (pilulka i novinky z #334 a #335 na něm
/// stojí), takže ho `ownLoop(for:handoff:)` **bere parametrem** a druhý průchod odpadá; naměřeno
/// je to v [`docs/testovani.md`](../../docs/testovani.md). Předfiltr, který zbývá, je
/// **vlastnictví** — a ten je na volajícím, hned vedle řádku, který dnes rozhoduje o `handoff`u.
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
        ownLoop(for: summary, handoff: handoffReport(for: summary.id))
    }

    /// Totéž z **už spočítaného** `HandoffReport`u (#509).
    ///
    /// **Není to zkratka pro pohodlí, je to celá cena té změny.** `Policy.handoff` je nejdražší
    /// vstup dráhy (skládá položky zadání z nálezů, vláken i commitů) a řádek seznamu ho počítá
    /// už dneska — kvůli pilulce (#334) a novinkám (#335). Kdyby si ho dráha vzala sama,
    /// zaplatil by se **dvakrát na každý vlastní řádek**; takhle se platí pořád jednou.
    ///
    /// Ostatní vstupy jsou čtení z map storu; drahé je z nich jedině `summary(of: checks)`
    /// v `Policy.ownLoop`, a to je lineární nad checky **jednoho** pull requestu, tedy nad polem,
    /// které je načtené jen u otevřených záložek.
    func ownLoop(for summary: PullRequestSummary, handoff: HandoffReport) -> OwnLoop? {
        let pr = summary.id
        return Policy.ownLoop(
            ownership: ownership(of: summary),
            state: summary.state,
            review: reviewState(for: pr),
            handoff: handoff,
            sync: branchSyncState(for: pr),
            status: branchStatusState(for: pr),
            checks: checks[pr],
            // **`nil`, dokud se metadata nenačetla** — prázdné pole je odpověď „nikdo není
            // vyžádaný“ a smíchat ji s „ještě nevím“ je zrovna to, čemu `MetadataState` brání.
            reviewers: metadataState(for: pr)?.metadata?.reviewers
        )
    }

    /// Dráha zmenšená do řádku seznamu (#509). `nil` = řádek tečky ani slovo nekreslí.
    ///
    /// **Skládá to `Policy`, ne tenhle getter** — tečky, slovo i odstín hrany odpovídají na
    /// jednu otázku a tři skládání by uměla říct každé něco jiného.
    func ownLoopRow(for summary: PullRequestSummary, handoff: HandoffReport) -> OwnLoopRow? {
        Policy.ownLoopRow(ownLoop(for: summary, handoff: handoff))
    }
}
