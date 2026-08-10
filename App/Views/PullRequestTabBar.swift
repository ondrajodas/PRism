import SwiftUI

/// Záložky na úrovni PR — podtržené, jako na GitHubu.
///
/// **Ne `Picker(.segmented)`**, kterým to začalo: segmentovaný přepínač vypadá jako volba
/// jedné hodnoty ze sady (tak se v tomhle okně přepínají reviewery a taby panelu), kdežto
/// tohle přepíná **celou obrazovku**. Podtržená záložka to říká na první pohled a je to
/// zvyklost odjinud, takže se to nemusí učit.
struct PullRequestTabBar: View {
    @Binding var selection: PullRequestTab
    /// Kolik je v tabu k přečtení. `nil` i nula znamenají „bez odznaku“ — `0` by tvrdilo,
    /// že je co číst.
    ///
    /// Od #218 se ptá **u všech záložek**, ne jen u `Konverzace`: odznak jen u jedné vypadal
    /// jako vlastnost té záložky, ne jako počet.
    var count: (PullRequestTab) -> Int? = { _ in nil }
    /// Rozsah změny (#174) — `+X −Y` vpravo v řadě záložek. `nil`, dokud diff nedorazí:
    /// nuly by tvrdily, že PR nic nemění.
    private(set) var diffCounts: (additions: Int, deletions: Int)?

    /// Doplní rozsah změny. Vlastní metoda, ne parametr v `init`u: volající ho počítá až
    /// z načteného diffu, takže by jinak musel psát `nil` i tam, kde ho nemá odkud vzít.
    func diffCounts(_ counts: (additions: Int, deletions: Int)?) -> PullRequestTabBar {
        var copy = self
        copy.diffCounts = counts
        return copy
    }

    /// Kvůli podtržení, které mezi záložkami **přejede**, ne přeskočí. Jedna instance
    /// v aktivní záložce, takže se animuje přesun ze zmizelé do nové.
    @Namespace private var underline
    @State private var hovered: PullRequestTab?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PullRequestTab.allCases, id: \.self) { item($0) }
            Spacer(minLength: 8)
            if let diffCounts { diffstat(diffCounts) }
        }
        .padding(.horizontal, 12)
        // **Ne `Divider()`.** Ten si orientaci bere z okolní osy a v `overlay` žádná není,
        // takže by se vykreslil svisle — tatáž past jako u hlaviček souborů v diffu.
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 1) }
    }

    /// Rozsah změny vpravo v řadě záložek (`.diffstat`).
    ///
    /// Stojí u záložek, ne v hlavičce: mluví o tom, co je v `Změněných souborech`, a je to
    /// tentýž údaj, jaký po souborech rozepisují hlavičky v diffu — proto `DiffCounts`, ne
    /// vlastní skládání, které by se s ním jednou rozešlo. (Souhrn nad diffem, se kterým to
    /// sedělo dřív, u #219 zmizel.)
    private func diffstat(_ counts: (additions: Int, deletions: Int)) -> some View {
        HStack(spacing: 8) {
            DiffCounts.text(additions: counts.additions, deletions: counts.deletions)
                .font(.caption)
                .monospacedDigit()
            blocks(counts)
        }
        .padding(.trailing, 4)
        .help("Kolik řádků PR přidává a ubírá — a v jakém poměru")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rozsah změny")
        .accessibilityValue("přidáno \(counts.additions), odebráno \(counts.deletions)")
    }

    /// Čtverečky poměru za počty (#218, `.diffstat .blocks`). Poměr počítá `Policy`, aby se
    /// dal vyčerpat výčtem — je to jediné místo, kde se z čísel rozhoduje o obrázku.
    private func blocks(_ counts: (additions: Int, deletions: Int)) -> some View {
        HStack(spacing: 2) {
            let blocks = Policy.diffstatBlocks(
                additions: counts.additions,
                deletions: counts.deletions
            )
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(of: block))
                    .frame(width: 8, height: 8)
            }
        }
        // Čtverečky říkají totéž co `+X −Y` vedle nich, jen obrázkem — odečítat je dvakrát
        // nemá cenu.
        .accessibilityHidden(true)
    }

    /// Barvy z **téhož zdroje** jako znak změny v řádku diffu (#156): dvě sady by se rozešly
    /// a `+` v řádku by bylo jinak zelené než čtvereček nad ním.
    private func color(of block: DiffstatBlock) -> Color {
        switch block {
        case .added: DiffLineView.signColor(of: .added)
        case .removed: DiffLineView.signColor(of: .removed)
        case .neither: Palette.line
        }
    }

    private func item(_ tab: PullRequestTab) -> some View {
        let isActive = selection == tab
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { selection = tab }
        } label: {
            content(tab, isActive: isActive)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? tab : (hovered == tab ? nil : hovered) }
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    private func content(_ tab: PullRequestTab, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol(of: tab))
                .font(.caption)
            Text(verbatim: tab.czechLabel)
                .font(.callout.weight(isActive ? .semibold : .regular))
            if let count = count(tab), count > 0 { badge(count) }
        }
        .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 10)
        .padding(.top, 7)
        // Pod textem je místo na podtržení, ať se obsah nehýbe podle toho, co je aktivní.
        .padding(.bottom, 8)
        .background(alignment: .bottom) { marker(isActive: isActive) }
        .background(hover(tab, isActive: isActive))
        .contentShape(.rect)
    }

    @ViewBuilder private func marker(isActive: Bool) -> some View {
        if isActive {
            RoundedRectangle(cornerRadius: 1)
                .fill(.tint)
                .frame(height: 2)
                .matchedGeometryEffect(id: "underline", in: underline)
        }
    }

    /// Zvýraznění pod kurzorem jen u **neaktivní** záložky: u aktivní by to naznačovalo, že
    /// se dá zapnout ještě víc.
    @ViewBuilder private func hover(_ tab: PullRequestTab, isActive: Bool) -> some View {
        if hovered == tab && !isActive {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .padding(.bottom, 2)
        }
    }

    /// Odznak počtu (`.stab .cnt`) — mono kapsle na tiché ploše, jak ho má návrh. Tlumeně
    /// schválně: je to počet, ne upozornění.
    private func badge(_ count: Int) -> some View {
        Text(verbatim: "\(count)")
            .font(.system(.caption2, design: .monospaced))
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Palette.raised, in: .capsule)
            .foregroundStyle(Palette.ink2)
    }

    /// Ikony jsou ve view, ne v modelu: `PullRequestTab` je volba pohledu, ne obrázek —
    /// a `ReviewStateBadge` mapuje stav na symbol taky u sebe.
    private func symbol(of tab: PullRequestTab) -> String {
        switch tab {
        // `Přehled` je od #183 popis a fakta, takže dokument; mluví se v `Konverzaci`.
        case .overview: "doc.text"
        case .filesChanged: "plus.forwardslash.minus"
        case .conversation: "bubble.left.and.bubble.right"
        }
    }
}

#Preview {
    @Previewable @State var selection = PullRequestTab.filesChanged

    return VStack(spacing: 0) {
        PullRequestTabBar(selection: $selection) { $0 == .overview ? 3 : nil }
        Text(verbatim: selection.czechLabel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 520, height: 200)
}
