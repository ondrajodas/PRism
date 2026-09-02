import SwiftUI

/// Hlásí, kde stojí výřez diffu — jako **soubor a řádek** (#527).
///
/// **Vlastní view, ne kus těla `DiffView`u, a je to výkonová podmínka** — tatáž jako
/// u `DiffPinnedHeader` a `DiffReadShortcut`: čte `DiffViewport.top`, tedy hodnotu, která se mění
/// při **každém** otočení kolečka. V těle diffu by se při každém snímku skládaly řádky všech
/// souborů (`DiffRow.rows(of:)`), což je zakázaná třída (#469). Takhle se přepočítá jedno
/// průhledné view.
///
/// **Co v něm při každém snímku doopravdy je**, protože „vlastní view“ samo nic neslibuje:
/// jeden průchod přes rozsahy souborů (desítky) a jeden přes přeměřené rámečky řádků (řádově
/// tisíc). Je to **aritmetika nad krabicemi mimo observable stav**, ne dotaz do grafu SwiftUI —
/// a právě tenhle rozdíl byl u #469 ten drahý: dotazy na rámečky **v souřadnicích výřezu** stály
/// 3,5 s CPU proti 0,19 s, protože se scrollováním mění. Souřadnice **obsahu** se scrollováním
/// nemění, takže se za ně neplatí.
///
/// **Hlášení jde do paměti store, ne na disk.** Na disk to jde s příští změnou záložky nebo při
/// ukončení aplikace (`AppStore.persistOpenTabs()`), takže se při scrollování nesahá na soubor.
/// A cíl **není** sledovaná vlastnost (`AppStore.diffScrollAnchors` je `@ObservationIgnored`),
/// takže zápis nikoho nepřekresluje.
struct DiffAnchorReporter: View {
    let files: [FileDiff]
    let extents: DiffFileExtents
    let frames: DiffRowFrames
    let viewport: DiffViewport
    let report: (DiffScrollAnchor?) -> Void

    var body: some View {
        // **Prázdné view s `onChange`, ne výpočet v `body`**: hlášení je vedlejší efekt a ten do
        // těla nepatří — z `body` se nesmí zapisovat do stavu. `of:` closure přitom běží uvnitř
        // aktualizace grafu (#438), takže se závislost na `viewport.top` zaregistruje a akce se
        // spustí jedině tehdy, když se hrana **doopravdy** pohnula.
        //
        // `initial: true`, protože první poloha je taky poloha: PR otevřený a hned zavřený by
        // jinak zůstal ve snímku bez kotvy a po restartu by se obnovil na začátku diffu.
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: viewport.top, initial: true) { report(anchor) }
            .accessibilityHidden(true)
    }

    /// Kotva podle toho, co je právě přeměřené. `nil` = ještě se neví ani soubor.
    ///
    /// Rozsahy souborů se berou **týmž voláním jako ukotvená hlavička** (`ordered(of:)`), takže
    /// „který soubor drží horní hranu“ má v okně jednu odpověď. Řádky se hledají jedině v rozsahu
    /// **toho** souboru — jinak by kotva spárovala soubor s číslem řádku z toho následujícího.
    private var anchor: DiffScrollAnchor? {
        let ordered = extents.ordered(of: files)
        return Policy.diffScrollAnchor(
            top: viewport.top,
            files: files.map(\.displayPath),
            extents: ordered,
            rows: { _, extent in frames.scrollRows(in: extent) }
        )
    }
}
