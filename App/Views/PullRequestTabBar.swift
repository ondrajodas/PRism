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
    var count: (PullRequestTab) -> Int? = { _ in nil }

    /// Kvůli podtržení, které mezi záložkami **přejede**, ne přeskočí. Jedna instance
    /// v aktivní záložce, takže se animuje přesun ze zmizelé do nové.
    @Namespace private var underline
    @State private var hovered: PullRequestTab?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PullRequestTab.allCases, id: \.self) { item($0) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        // **Ne `Divider()`.** Ten si orientaci bere z okolní osy a v `overlay` žádná není,
        // takže by se vykreslil svisle — tatáž past jako u hlaviček souborů v diffu.
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 1) }
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

    private func badge(_ count: Int) -> some View {
        Text(verbatim: "\(count)")
            .font(.caption2)
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: .capsule)
            .foregroundStyle(.secondary)
    }

    /// Ikony jsou ve view, ne v modelu: `PullRequestTab` je volba pohledu, ne obrázek —
    /// a `ReviewStateBadge` mapuje stav na symbol taky u sebe.
    private func symbol(of tab: PullRequestTab) -> String {
        switch tab {
        case .overview: "text.bubble"
        case .filesChanged: "plus.forwardslash.minus"
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
