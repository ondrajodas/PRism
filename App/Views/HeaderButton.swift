import SwiftUI

/// Rozměry tlačítka v pravém koutu hlavičky okna (`.tbtn` z návrhu, sekce 32).
///
/// **Jedno místo, protože se ten rozměr nesmí hnout** (#442). Tlačítko obnovení mění obsah podle
/// toho, jestli se aplikace ptá — a kdyby si prstýnek nesl vlastní rámec, poskočila by hlavička
/// pokaždé, když polling tikne. Číslo je z CSS mockupu 1 : 1.
enum HeaderButtonMetrics {
    static let width: CGFloat = 27
    static let height: CGFloat = 25
    /// Velikost SF Symbolu uvnitř (`.tbtn { font-size: 13px }`).
    static let symbolSize: CGFloat = 13
    /// Mezera mezi tlačítky (`.toolbtns { gap: 3px }`).
    static let spacing: CGFloat = 3
}

/// Tlačítko v hlavičce okna — ikona v pevném rámci, bez pozadí (#180, rozměry #442).
struct HeaderButton: View {
    let symbol: String
    /// Místo ikony se točí prstýnek. Rámec zůstává týž, takže se hlavička nehne.
    var isSpinning = false
    var isEnabled = true
    /// Popisek pro čtečku obrazovky. **Povinný**, ne odvozený z ikony: VoiceOver by u ikonového
    /// tlačítka jinak přečetl jméno symbolu (`sparkles`), což uživateli neřekne nic.
    let label: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: HeaderButtonMetrics.width, height: HeaderButtonMetrics.height)
                .foregroundStyle(Palette.ink2)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(label)
    }

    /// **Ne nový prstýnek, ale ten ze záložek** (#442). `SpinningRing` točí v CoreAnimation
    /// schválně: nekonečná animace ve SwiftUI si vyžádá průchod při každém obtažení obrazovky
    /// a přes `NSHostingView.layout()` rozvrhne celé okno — u prstýnku na záložce z toho bylo
    /// 99 % CPU hlavního vlákna na nečinném okně (#350). Druhá kresba téhož by tu past otevřela
    /// znovu, a k tomu by znamenala, že se „pracuje se“ čte v jednom okně dvěma tvary.
    @ViewBuilder private var glyph: some View {
        if isSpinning {
            SpinningRing()
        } else {
            Image(systemName: symbol).font(.system(size: HeaderButtonMetrics.symbolSize))
        }
    }
}

/// Tlačítko `⟳` v hlavičce okna (#442) — jediné, které mění podobu podle stavu aplikace.
///
/// Existuje jako vlastní typ proto, aby vazba „běží obnovení → točí se prstýnek a klik neprojde“
/// byla **na jednom místě a šla otestovat**. V `ContentView` by to byl `if` v těle okna, kam se
/// testem nedosáhne.
struct RefreshButton: View {
    /// Ptá se polling právě teď? Platí to i pro **automatický** tik, ne jen pro klik.
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        let control = Policy.refreshControl(isRefreshing: isRefreshing)
        HeaderButton(
            symbol: "arrow.clockwise",
            isSpinning: control.isSpinning,
            isEnabled: control.isEnabled,
            label: control.label,
            help: control.help,
            action: refresh
        )
    }
}
