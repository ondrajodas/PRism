import SwiftUI

/// Diff **jednoho commitu** v tabu `Commity` (#317) — hlavička a pod ní diff přes celou plochu.
///
/// **Přepnutí obsahu tabu, ne rozbalení pod řádkem seznamu** (návrh, sekce 19, třetí obrazovka).
/// Rozbalený diff pod řádkem by znamenal dvě scrollovací plochy nad sebou a hlavičku commitu,
/// která se odroluje pryč zrovna ve chvíli, kdy se čte kód.
///
/// **Je to prohlížeč, ne review, a je to vidět z toho, co tenhle typ dostane.** Nemá `AppStore`,
/// nemá identifikátor pull requestu a nemá jedinou akci, kterou by šlo něco napsat — takže
/// bublinu nálezu ani rozdělaný komentář v něm nejde vyrobit ani omylem. Důvody jsou dva a oba
/// jsou tvrdé:
///
/// - **Komentář k řádku commitu by potřeboval jiný klíč.** Rozdělaný komentář se váže na
///   `(soubor, řádek)` diffu PR; u commitu by se musel klíčovat i sha, jinak by se dva komentáře
///   k témuž řádku ve dvou commitech přepsaly. A odeslat by ho šla jedině **další metoda
///   v `ReviewPublishing`** — a ten výčet je podle tvrdé podmínky č. 1 krátký schválně (od #392
///   je v něm šest metod, komentář ke commitu mezi ně pořád nepatří). Tím, že je tenhle typ celý
///   čtecí, se podmínky **nedotýká vůbec**.
/// - **Nálezy jsou klíčované `headSha`** (tvrdá podmínka č. 5), takže u staršího commitu by
///   ukazovaly na jiný kód.
///
/// **Panel v tabu od #392 je**, a na tomhle typu se tím nemění nic: kreslí ho
/// `PullRequestDetailView` **vedle** něj, takže composer v panelu píše tělo review proti hlavě PR,
/// ne komentář ke commitu. Že u staršího commitu nálezy nevypadají jako platné, řeší věta a ztlumené
/// karty v panelu (`Policy.findingsHeadNotice`), ne tenhle typ — ten o nálezech nic neví.
///
/// Co **zůstává**: oba pohledy, word-level zvýraznění, sbalování souborů, rozbalování kontextu,
/// kopírování a strom souborů vlevo (`⌘1`) — commit s třiceti soubory ho potřebuje. Všechno
/// z `DiffView`, tedy jedna cesta pro obě obrazovky; druhá by se rozešla první úpravou sazby.
struct CommitDiffView: View {
    let commit: PullRequestCommit
    let state: CommitDiffTabState
    /// `2 ze 7` do hlavičky.
    var position: String?
    /// Adresa commitu na GitHubu.
    var url: URL?
    /// Je v hlavičce vidět tělo zprávy? Předvolba pohledu, tedy globální ve store — proč, je
    /// u `AppStore.isCommitMessageExpanded`.
    @Binding var isMessageExpanded: Bool
    /// Rozbalování kontextu — **z obsahu souboru v tomhle commitu**, ne na hlavě PR. Skládá ho
    /// volající, protože klíč zná store.
    let expansion: DiffExpansionActions
    let folding: DiffFoldingActions
    @Binding var layout: DiffLayout
    let back: () -> Void
    let showFiles: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CommitHeaderView(
                commit: commit,
                position: position,
                facts: facts,
                url: url,
                isMessageExpanded: $isMessageExpanded,
                back: back,
                showFiles: showFiles
            )
            content
        }
        // **Šířku předat, ne vyjednávat** (#220) — pod tímhle uzlem visí celý diff.
        .filling(alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    /// Počty do hlavičky — **jen z neprázdného diffu**. `0 souborů · +0 −0` nad větou „commit nic
    /// nemění“ by bylo totéž řečené dvakrát, jednou jako čísla a jednou jako věta.
    private var facts: CommitDiffFacts? {
        guard case .diff(let diff) = state else { return nil }
        return Policy.commitDiffFacts(of: diff)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            // Tatáž hláška jako u diffu PR, kontrol a seznamu commitů — a schválně bez počtů:
            // dokud diff nedorazil, o commitu nevíme, kolik čeho mění.
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Načítám diff commitu…")
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .diff(let diff):
            reading(diff)
        case .nothing(let empty):
            // **Klidná povaha**: prázdný diff je platná odpověď, ne porucha — a právě to je ten
            // rozdíl, který se z prázdné plochy nedá poznat.
            EmptyStateView(
                nature: .calm,
                symbol: "equal.circle",
                title: empty.title,
                message: empty.message
            )
        case .failed(let reason):
            EmptyStateView(
                nature: .failure,
                symbol: "exclamationmark.triangle",
                title: "Diff commitu se nepodařilo načíst",
                message: "Bez něj není poznat, jestli commit nic nemění, nebo se jen nestáhl.",
                // Text od `gh` zůstává, jak přišel: je to jediné, z čeho se pozná, co dělat dál.
                detail: reason,
                primary: .init(title: "Zkusit znovu", run: retry)
            )
        }
    }

    /// Diff, jak ho tab skládá — **čtecí sada bez čehokoli, čím se dá psát**.
    ///
    /// **`internal` schválně, kvůli testu** (#317): jediné, co na téhle kompozici stojí za
    /// tvrzení, je to, co `DiffView` **nedostane**. Nálezy, vlákna, rozdělané komentáře i panel
    /// tady chybí, a test to musí umět přečíst — jinak by se dala čtecí povaha tabu zrušit jedním
    /// přidaným parametrem a poznalo by se to až na obrazovce.
    ///
    /// Prázdné hodnoty se **nevypisují**: `DiffView` je má jako výchozí, takže vyjmenovat je tady
    /// znovu by znamenalo druhé místo, kde se dá `findings:` omylem naplnit.
    func reading(_ diff: Diff) -> DiffView {
        DiffView(
            diff: diff,
            // Commit, ne pull request: diff commitu je jiný obsah na týchž souřadnicích, takže
            // krabice ploch pro tažení musí poznat, že se kreslí něco jiného (#274). Sha stačí —
            // je jednoznačná napříč repozitáři a tab žádnou identitu PR **nemá schválně**.
            subject: commit.sha,
            // Skáče se jedině v diffu PR (z nálezu, z palety, z anotace CI) a sem žádná z těch
            // cest nevede — kotvy míří na řádky dnešní hlavy, ne tohohle commitu.
            scrollTarget: .constant(nil),
            expansion: expansion,
            folding: folding,
            layout: $layout
        )
    }
}
