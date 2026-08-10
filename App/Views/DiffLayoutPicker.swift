import SwiftUI

/// Přepínač pohledu na diff — segment **s popisky**, jak ho kreslí návrh (`.segbtn`, #219).
///
/// **Ne `Picker(.segmented)`**, kterým to bylo od #98. Systémový přepínač se dvěma ikonami bez
/// popisků neřekne, co která dělá — pozná se to až najetím myší, tedy až po tom, co si člověk
/// vybral, na co najet. Je to tentýž důvod, proč se kreslí sám i přepínač tabů v panelu (#182).
///
/// Sazba je z návrhu: podklad `--panel-3`, aktivní segment na `--panel` se stínem, popisek
/// 11,5 bodu, poloměry 7 (rám) a 5 (segment).
struct DiffLayoutPicker: View {
    @Binding var selection: DiffLayout

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DiffLayout.allCases, id: \.self) { segment($0) }
        }
        .padding(2)
        .background(Palette.raised, in: .rect(cornerRadius: 7))
        // **`fixedSize`, jinak popisky nemá cenu psát.** Přepínač stojí vlevo, tedy mimo
        // `ViewThatFits`, který drží pravou část lišty; bez toho by mu `HStack` v úzkém okně
        // popisky stlačil na `Vedle…` — a právě kvůli nim se od `Picker(.segmented)` odešlo.
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pohled na diff")
        .help("Kreslit diff vedle sebe (starý a nový obsah proti sobě), nebo pod sebou")
    }

    private func segment(_ option: DiffLayout) -> some View {
        let isActive = selection == option
        return Button {
            selection = option
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.symbol)
                    .font(.system(size: 10))
                Text(verbatim: option.displayName)
                    .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Palette.ink : Palette.ink2)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(activeBackground(isActive))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// Stín má jen **aktivní** segment — je to on, kdo v návrhu leží nad podkladem.
    /// Hodnoty odpovídají `--shadow-sm`; `RoundedRectangle` kreslí SwiftUI sám, takže se
    /// vykreslí i offscreen (na rozdíl od AppKit stylů).
    @ViewBuilder private func activeBackground(_ isActive: Bool) -> some View {
        if isActive {
            RoundedRectangle(cornerRadius: 5)
                .fill(Palette.surface)
                .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
        }
    }
}

#Preview {
    @Previewable @State var layout = DiffLayout.unified
    return DiffLayoutPicker(selection: $layout).padding()
}
