import SwiftUI

/// Svislý rail vlevo (#180) — navigace v aplikaci, ne v pull requestu.
///
/// Nahradil toolbar bočního panelu. Rozdíl je v tom, na co se ptá: toolbar nabízel akce nad
/// seznamem (obnovit, filtrovat), rail přepíná **co je v okně vidět**. Akce zůstaly nad obsahem,
/// kterého se týkají.
///
/// Šířka je 52 bodů a je to celé místo, které si bere: ikony se popiskem by z něj udělaly druhý
/// sloupec vedle seznamu, a ten už jednou v okně je.
struct SidebarRail: View {
    @Binding var section: RailSection
    /// Kolik PR čeká ve frontě. `nil` = ještě se nenačetlo; nula se **nekreslí**, protože
    /// odznak s nulou tvrdí, že je co dělat.
    var queueCount: Int?
    /// Kolik PR má rozdělané review.
    var draftCount: Int?

    var body: some View {
        VStack(spacing: 4) {
            ForEach(RailSection.allCases) { item(for: $0) }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(.bar)
        .overlay(alignment: .trailing) { Rectangle().fill(.separator).frame(width: 1) }
    }

    private func item(for item: RailSection) -> some View {
        let isActive = section == item
        return Button { section = item } label: {
            Image(systemName: item.symbol)
                .font(.system(size: 15))
                .frame(width: 34, height: 30)
                .background(isActive ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .overlay(alignment: .topTrailing) { badge(count(of: item)) }
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// Odznak s počtem. **Nula se nekreslí** — prázdná fronta je dobrá zpráva, ne položka
    /// k vyřízení; a `nil` (nenačteno) se od nuly musí lišit, jinak by okno po startu tvrdilo
    /// „nic tu není“ nad daty, která ještě nedorazila.
    @ViewBuilder private func badge(_ count: Int?) -> some View {
        if let count, count > 0 {
            Text(verbatim: "\(count)")
                .font(.system(size: 9, weight: .bold))
                .monospacedDigit()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.tint, in: .capsule)
                .foregroundStyle(.white)
                .offset(x: 6, y: -2)
        }
    }

    private func count(of item: RailSection) -> Int? {
        switch item {
        case .queue: queueCount
        case .drafts: draftCount
        }
    }

}
