import SwiftUI

/// Řada, která se **zalomí, když se nevejde** — `display: flex; flex-wrap: wrap` z návrhu (#333).
///
/// SwiftUI nic takového nemá: `HStack` místo zalomení zkracuje popisky, `LazyVGrid` dělá stejně
/// široké sloupce (odznak `1 blokuje` by pak zabral tolik místa jako `1 komentář pod PR`). Odznaky
/// nad textem zadání ale nesou počty, takže zkrácený odznak (`vynecháno: 1 vyřešen…`) je zrovna ta
/// informace, kvůli které tam je.
///
/// **Polohy se počítají, nevyjednávají** (pravidlo #220): každý prvek dostane svou ideální
/// velikost (`nil` proposal) a `Layout` z nich složí řádky. Prvků je pár, takže tady nejde o cenu —
/// jde o to, že se šířka řady neodvozuje od obsahu ani obsah od řady.
struct FlowRow: Layout {
    var spacing = 7.0
    /// Mezera mezi zalomenými řádky. Vlastní hodnota, ne `spacing`: vodorovná mezera mezi odznaky
    /// je z návrhu (`gap: 7px`), kdežto svislá se řídí sazbou textu nad nimi.
    var lineSpacing = 6.0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, within: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + Double(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(of: subviews, within: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width = 0.0
        var height = 0.0
    }

    /// Rozdělení prvků do řádků. Prvek, který se sám nevejde, dostane **vlastní řádek** — jinak by
    /// se odznak širší než celá řada nenakreslil vůbec.
    private func rows(of subviews: Subviews, within width: Double) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, needed > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(Item(index: index, size: size))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
