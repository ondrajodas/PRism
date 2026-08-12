import SwiftUI

/// Záložky na úrovni PR — podtržené, jako na GitHubu.
///
/// **Ne `Picker(.segmented)`**, kterým to začalo: segmentovaný přepínač vypadá jako volba
/// jedné hodnoty ze sady (tak se v tomhle okně přepínají reviewery a taby panelu), kdežto
/// tohle přepíná **celou obrazovku**. Podtržená záložka to říká na první pohled a je to
/// zvyklost odjinud, takže se to nemusí učit.
///
/// **Které záložky kreslí, se nedá zvenku nastavit** (#306) — je to vždycky celý
/// `PullRequestTab.allCases`. Do #306 to byl parametr, protože `Kontroly` u PR bez CI odpadly
/// (#215), a pruh se tím při každém otevření PR **přeskládal**: nejdřív pět záložek, pak šest.
/// Parametr zmizel schválně a je to ta podstatná část opravy: dokud existoval, dal se počet
/// záložek znovu udělat funkcí dat, a mizející záložka je horší než jedna prázdná.
struct PullRequestTabBar: View {
    @Binding var selection: PullRequestTab
    /// Co je v tabu k vidění. `nil` = bez odznaku.
    ///
    /// Od #218 se ptá **u všech záložek**, ne jen u `Konverzace`: odznak jen u jedné vypadal
    /// jako vlastnost té záložky, ne jako počet. Od #242 to není `Int?`, ale `PullRequestTabBadge`
    /// — u `Nálezů` musí být poznat, že něco blokuje, a u `Průběhu` je „běží“ stav, ne množství.
    var badge: (PullRequestTab) -> PullRequestTabBadge? = { _ in nil }
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
            ForEach(Array(PullRequestTab.allCases.enumerated()), id: \.element) { index, tab in
                if needsSeparator(before: index) { separator }
                item(tab)
            }
            Spacer(minLength: 8)
            if let diffCounts { diffstat(diffCounts) }
        }
        .padding(.horizontal, 12)
        // **Ne `Divider()`.** Ten si orientaci bere z okolní osy a v `overlay` žádná není,
        // takže by se vykreslil svisle — tatáž past jako u hlaviček souborů v diffu.
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 1) }
    }

    /// Patří před tuhle záložku dělič? (#242, `.tsep`)
    ///
    /// Rozhoduje **vlastnost tabu**, ne jeho index: `Kontroly` (#215) sedí nalevo doprostřed,
    /// takže zadrátovaná pozice by dělič posunula o jedno místo vedle. Od #306 je pruh konstantní,
    /// takže by se dala spočítat i z indexu — vlastnost přesto zůstává, protože o tom, kde dělič
    /// patří, rozhoduje **čí výstup záložka ukazuje**, a to je odpověď, která přežije i sedmou
    /// záložku vloženou doprostřed.
    private func needsSeparator(before index: Int) -> Bool {
        guard index > 0 else { return false }
        let tabs = PullRequestTab.allCases
        return tabs[index].isReviewerOutput && !tabs[index - 1].isReviewerOutput
    }

    /// Dělič v pruhu záložek: nalevo je to, co je na PR (a co má i GitHub), napravo to, co s ním
    /// udělaly naše reviewery. Bez něj vypadá řada záložek jako jeden dlouhý seznam.
    ///
    /// **Ne `Divider()`** — ten si orientaci bere z okolní osy, takže by ve vodorovném `HStack`u
    /// vyšel naležato; tady je potřeba svislá čárka. Tatáž past jako u linky pod záložkami.
    private var separator: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(width: 1, height: 15)
            .padding(.horizontal, 9)
            .accessibilityHidden(true)
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
            if let badge = badge(tab) { mark(badge) }
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

    /// Odznak u záložky (`.stab .cnt`, `.stab .live`).
    ///
    /// Počet je mono kapsle na tiché ploše — tlumeně schválně, je to počet, ne upozornění. **Až
    /// na blokující nález** (#242): ten je červený, protože „3“ v tiché kapsli se čte jako údaj
    /// o množství a přesně tohle množství množstvím není.
    @ViewBuilder private func mark(_ badge: PullRequestTabBadge) -> some View {
        switch badge {
        case .count(let count): pill("\(count)", tint: Palette.ink2, background: Palette.raised)
        case .blocking(let count):
            pill("\(count)", tint: Palette.crit, background: Palette.crit.opacity(0.15))
        case .live: liveDot
        }
    }

    private func pill(_ text: String, tint: Color, background: Color) -> some View {
        Text(verbatim: text)
            .font(.system(.caption2, design: .monospaced))
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(background, in: .capsule)
            .foregroundStyle(tint)
    }

    /// Puntík u záložky `Průběh`: „něco běží“ má být vidět, aniž by se do ní chodilo — a je to
    /// **stav, ne množství**, takže tam nepatří číslo.
    ///
    /// Halo z návrhu (`box-shadow 0 0 0 3px`) kreslí **větší kruh pod puntíkem**, ne obtažení: to
    /// se vykreslí dovnitř sedmibodového kruhu, takže puntík přebarví a zvenku není vidět nic —
    /// chyceno offscreen renderem.
    private var liveDot: some View {
        Circle()
            .fill(Palette.find)
            .frame(width: 7, height: 7)
            .background { Circle().fill(Palette.find.opacity(0.2)).frame(width: 13, height: 13) }
            .frame(width: 13, height: 13)
            .accessibilityLabel("běží")
    }

    /// Ikony jsou ve view, ne v modelu: `PullRequestTab` je volba pohledu, ne obrázek —
    /// a `ReviewStateBadge` mapuje stav na symbol taky u sebe.
    private func symbol(of tab: PullRequestTab) -> String {
        switch tab {
        // `Přehled` je od #183 popis a fakta, takže dokument; mluví se v `Konverzaci`.
        case .overview: "doc.text"
        case .filesChanged: "plus.forwardslash.minus"
        case .conversation: "bubble.left.and.bubble.right"
        // Seznam s odškrtnutím, ne `checkmark.circle`: kolečko se v hlavičce používá na **výsledek**
        // (zelené prošlo, červené spadlo), kdežto ikona záložky má říkat, co v ní je — a to je
        // seznam kontrol, ať dopadly jakkoli.
        case .checks: "checklist"
        // Lupa nad textem je tentýž symbol, jakým se v ose hlásí `ReportFindings` — nálezy mají
        // v okně jednu ikonu, ne dvě.
        case .findings: "text.magnifyingglass"
        case .progress: "chart.bar.doc.horizontal"
        }
    }
}

#Preview {
    @Previewable @State var selection = PullRequestTab.filesChanged

    return VStack(spacing: 0) {
        PullRequestTabBar(selection: $selection) { tab in
            switch tab {
            case .overview: .count(3)
            case .findings: .blocking(2)
            case .progress: .live
            default: nil
            }
        }
        Text(verbatim: selection.czechLabel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 520, height: 200)
}
