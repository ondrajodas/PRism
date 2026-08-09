import SwiftUI

/// Sloupce v pevném poměru šířek — `grid-template-columns: 1.45fr 1fr` z návrhu (#181).
///
/// `HStack` umí jen rovným dílem, `Grid` poměr sloupců neumí vůbec, a pevná šířka pravého
/// sloupce se s oknem rozejde: v úzkém sežere půlku, v širokém z něj zbude proužek. Poměr
/// je proto vlastní `Layout` — je to deset řádků a jinak by se návrh nedal dodržet.
///
/// Sloupce se sázejí od horní hrany (`align-items: start`), takže kratší z nich nedorovnává
/// výšku toho vedle.
struct ProportionalColumns: Layout {
    /// Poměr šířek, jeden údaj na sloupec. Sloupec navíc, na který se nedostalo, dostane `1`.
    let ratios: [Double]
    let spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // **Bez konečné navržené šířky se poměr nemá z čeho počítat.** Dosadit nulu by znamenalo
        // změřit sloupce v nulové šířce — tedy vrátit výšku textu zalomeného po písmenech, což je
        // číslo, které s ničím nesouvisí. Volající se na to ptá při zjišťování přirozené velikosti
        // (`.unspecified`, `.infinity`), takže se odpoví přirozenou šířkou sloupců.
        guard let total = proposal.width, total.isFinite, total > 0 else {
            let sizes = subviews.map { $0.sizeThatFits(proposal) }
            return CGSize(
                width: sizes.map(\.width).reduce(0, +) + spacing * Double(max(subviews.count - 1, 0)),
                height: sizes.map(\.height).max() ?? 0
            )
        }
        let heights = zip(subviews, widths(in: total, count: subviews.count)).map {
            $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height
        }
        return CGSize(width: total, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(in: bounds.width, count: subviews.count)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: nil)
            )
            x += width + spacing
        }
    }

    /// Šířky sloupců z toho, co zbude po mezerách.
    ///
    /// `internal`, ne `private`: je to jediná počítaná část layoutu a jinak by se nedala změřit —
    /// `Layout` se bez hostitelského okna vykreslit nedá.
    func widths(in total: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let ratios = (0..<count).map { $0 < self.ratios.count ? self.ratios[$0] : 1 }
        let sum = ratios.reduce(0, +)
        guard sum > 0 else { return Array(repeating: 0, count: count) }
        let available = max(0, total - spacing * Double(count - 1))
        return ratios.map { available * $0 / sum }
    }
}
