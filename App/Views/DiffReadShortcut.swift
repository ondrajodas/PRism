import SwiftUI

/// `⌥V` na soubor, jehož hlavička je zrovna ukotvená nahoře (#500).
///
/// **Vlastní view, ne `@ViewBuilder` v `DiffView` — a je to výkonová podmínka**, tatáž jako
/// u `DiffPinnedHeader`: čte `DiffViewport.top`, tedy hodnotu, která se mění při **každém**
/// otočení kolečka. Kdyby se to čtení odehrálo v těle `DiffView`, překládalo by se při každém
/// snímku celé tělo diffu i s řádky všech souborů. Takhle se překresluje jedno průhledné
/// tlačítko.
///
/// Průhledné tlačítko, ne `.hidden()`: skryté view z hierarchie zmizí i se zkratkou — tentýž
/// vzorec jako `⌘1` (strom) a `⌘F` (hledání) v `DiffView`.
struct DiffReadShortcut: View {
    let files: [FileDiff]
    let extents: DiffFileExtents
    let viewport: DiffViewport
    let toggle: (FileDiff) -> Void

    /// Výška hlavičky se tu **nemá kde vzít a nepotřebuje se**: `Policy.pinnedFileHeader`
    /// odpovídá na „který soubor je u horní hrany“ i s nulovou výškou — ta rozhoduje jen o tom,
    /// jak daleko se ukotvená hlavička vysune, když ji tlačí ta následující.
    private var current: FileDiff? {
        guard
            let pinned = Policy.pinnedFileHeader(
                files: extents.ordered(of: files),
                top: viewport.top,
                headerHeight: 0
            ),
            files.indices.contains(pinned.index)
        else { return nil }
        return files[pinned.index]
    }

    var body: some View {
        let file = current
        Button(Policy.windowShortcut(.toggleFileRead).title) {
            if let file { toggle(file) }
        }
        .windowShortcut(.toggleFileRead)
        // Bez ukotveného souboru (rozsahy ještě nikdo nezměřil, diff je prázdný) je tlačítko
        // **zakázané** — a zakázané klávesu nebere, takže propadne dál, místo aby zaškrtlo
        // něco jiného, než na co se člověk dívá.
        .disabled(file == nil)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
