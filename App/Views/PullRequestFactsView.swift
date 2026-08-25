import SwiftUI

/// Dlaždice s fakty o PR v `Přehledu` (#198).
///
/// Rozměry z návrhu: poloměr 7, padding 9/11, popisek mono 9,5 s prostrkáním, hodnota 13
/// polotučně, dovětek 11 drobně.
struct PullRequestFactsView: View {
    let facts: PullRequestFacts

    var body: some View {
        // **Mřížka čtyř sloupců, ne `HStack`** (`grid-template-columns: repeat(4, 1fr)`).
        // V `HStacku` se dvě dlaždice roztáhnou přes celou šířku a číslo v nich plave uprostřed
        // prázdna; v mřížce si drží čtvrtinu bez ohledu na to, kolik jich zrovna je.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4), spacing: 9) {
            ForEach(facts.tiles) { tile in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: tile.caption.uppercased())
                        .font(.system(size: 9.5, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Palette.ink3)
                    HStack(spacing: 4) {
                        Text(verbatim: tile.value)
                            .font(
                                tile.isMonospaced
                                    ? .system(size: 11.5, design: .monospaced)
                                    : .system(size: 13, weight: .semibold)
                            )
                            .monospacedDigit()
                            // Zastaralá sha je okrová jako stav `zastaralé` v řádku fronty —
                            // stejná škála v celém okně, a od #432 doslova tentýž token
                            // (`Palette.stale`). Do #432 tu stála systémová `.yellow`, takže
                            // ta věta o „stejné škále“ přestala platit ve chvíli, kdy #383
                            // převedlo řádek fronty na token — a nikdo si toho nevšiml.
                            .foregroundStyle(tile.isStale ? Palette.stale : Palette.ink)
                        if let note = tile.note {
                            Text(verbatim: "· \(note)")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.ink3)
                        }
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Palette.chrome, in: .rect(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1) }
            }
        }
    }
}
