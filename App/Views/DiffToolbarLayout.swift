import SwiftUI

/// Kterým prvkem lišty nad diffem podview je (#593). `nil` = prvek, o kterém se nerozhoduje;
/// dostane, oč si řekne, a stojí vpravo.
struct DiffToolbarItemKey: LayoutValueKey {
    static let defaultValue: Policy.DiffToolbarItem? = nil
}

extension View {
    /// Označí podview lišty, aby o jeho šířce mohla rozhodnout `Policy`.
    func diffToolbarItem(_ item: Policy.DiffToolbarItem) -> some View {
        layoutValue(key: DiffToolbarItemKey.self, value: item)
    }
}

/// Rozvržení lišty nad diffem — **jeden průchod, ve kterém se šířka spočítá a předá** (#593).
///
/// Do #593 byla lišta `HStack` se `Spacer`em a o tom, co v tísni ustoupí, rozhodovalo, který
/// prvek zapomněl `fixedSize()`. To není rozhodnutí, to je shoda okolností — a projeví se až
/// v podlahovém okně, kde si lišta v plné výbavě říká o 923 bodů do štěrbiny 572.
///
/// `Layout` je tu proto, že **umí změřit svoje podviews a pak jim šířku předat** (#220, #236):
/// zeptá se každého prvku, oč si říká celý (`.unspecified`) a na co se srazí (proposal 0),
/// nechá `Policy.diffToolbarRoom` vybrat a podle výběru prvky položí. `HStack` nic z toho neumí
/// — přetečení nehlásí, jen ho nakreslí.
///
/// Levá skupina (pohled, procházení) se pokládá od levé hrany, pravá od pravé; mezi nimi je
/// mezera, která zbyde, nejmíň ale `groupGap`. **Nic se nepokládá za hranu**: když se ani po
/// celém ustoupení nevejde, ubere `Policy` z nejširšího prvku vpravo, nikdy ne pod
/// `Policy.diffToolbarItemFloor`.
struct DiffToolbarLayout: Layout {
    /// Mezera mezi prvky v jedné skupině.
    var spacing = 9.0
    /// Nejmenší mezera mezi levou a pravou skupinou. **27, ne 9**: `HStack` se `Spacer(minLength: 9)`
    /// držel devítku na každé straně mezerníku, takže se tím lišta kreslí přesně jako dřív —
    /// a šířka, oč si říká, zůstane srovnatelná s měřením z #524.
    var groupGap = 27.0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measures = Self.measures(of: subviews)
        let ideal = measures.map(\.full).reduce(0, +) + fixedSpacing(of: subviews)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        guard let width = proposal.width, width.isFinite else {
            return CGSize(width: ideal, height: height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let measures = Self.measures(of: subviews)
        let room = Policy.diffToolbarRoom(
            available: bounds.width - fixedSpacing(of: subviews),
            measures: measures.compactMap(\.measure)
        )
        let widths = measures.map { entry in
            entry.item.map(room.width(of:)) ?? entry.full
        }

        let leading = measures.indices.filter { measures[$0].side == .leading }
        let trailing = measures.indices.filter { measures[$0].side == .trailing }

        var x = bounds.minX
        for index in leading {
            place(subviews[index], at: x, width: widths[index], in: bounds)
            x += widths[index] + spacing
        }

        let trailingWidth = trailing.map { widths[$0] }.reduce(0, +)
            + spacing * Double(max(trailing.count - 1, 0))
        // **Nikdy nepřes levou skupinu**: kdyby se ani ta nevešla, je poctivější lištu přeplnit
        // vpravo než položit procházení nálezů pod přepínač pohledu.
        var trailingX = max(bounds.maxX - trailingWidth, x)
        for index in trailing {
            place(subviews[index], at: trailingX, width: widths[index], in: bounds)
            trailingX += widths[index] + spacing
        }
    }

    private func place(_ subview: LayoutSubview, at x: Double, width: Double, in bounds: CGRect) {
        subview.place(
            at: CGPoint(x: x, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: width, height: bounds.height)
        )
    }

    /// Mezery, které se z šířky odečtou vždycky: mezi prvky v každé skupině a mezi skupinami.
    private func fixedSpacing(of subviews: Subviews) -> Double {
        let sides = subviews.map { Self.side(of: $0) }
        let leading = sides.count { $0 == .leading }
        let trailing = sides.count { $0 == .trailing }
        let within = spacing * Double(max(leading - 1, 0) + max(trailing - 1, 0))
        // Jedna skupina prázdná znamená, že se mezera mezi skupinami degraduje na odsazení —
        // 27 bodů volna u hrany by vypadalo jako chyba, ne jako mezera.
        guard leading > 0, trailing > 0 else { return within + (sides.isEmpty ? 0 : spacing) }
        return within + groupGap
    }

    // MARK: - Měření

    /// Co si který prvek řekne celý a na co se srazí. **Měří se na tom, na čem se kreslí**
    /// (#236): odpovídá podview samo, ne tabulka konstant vedle.
    ///
    /// Není `private`, protože **na tomhle měření stojí sonda i testy** — a druhá kopie téhož
    /// měření v `Tests/` by měřila něco jiného než aplikace.
    struct Entry {
        let item: Policy.DiffToolbarItem?
        let side: Policy.DiffToolbarSide
        let full: Double
        let floor: Double

        var measure: Policy.DiffToolbarMeasure? {
            item.map { Policy.DiffToolbarMeasure($0, full: full, floor: floor) }
        }
    }

    static func measures(of subviews: Subviews) -> [Entry] {
        subviews.map { subview in
            let item = subview[DiffToolbarItemKey.self]
            let full = subview.sizeThatFits(.unspecified).width
            // **O bod méně, ne nula**, a je to ta část měření, která se dá splést: proposal 0 by
            // z `ViewThatFits` vybral sraženou podobu, ale vrátil by její **minimum** — tedy
            // u zkráceného textu šířku samotné výpustky. `full - 1` sraženou podobu vybere taky
            // (celá se do ní nevejde), zato je pro ni proposal štědrý, takže odpoví svým
            // **ideálem**. Prvek bez sražené podoby odpoví touž šířkou a tím sám řekne, že
            // neustupuje.
            let floor = subview.sizeThatFits(
                ProposedViewSize(width: max(full - 1, 0), height: nil)
            ).width
            return Entry(item: item, side: side(of: subview), full: full, floor: min(floor, full))
        }
    }

    private static func side(of subview: LayoutSubview) -> Policy.DiffToolbarSide {
        subview[DiffToolbarItemKey.self].map(Policy.diffToolbarSide) ?? .trailing
    }
}
