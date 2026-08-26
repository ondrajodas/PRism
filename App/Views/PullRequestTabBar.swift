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
        // **Čtyři podoby, ne zúžení jednoho pruhu** (#316, třetí od #318, čtvrtá od #452). Co
        // ustupuje a v jakém pořadí, je u `Layout`.
        //
        // **`ViewThatFits` měří ideální šířku každé podoby**, a ta je u pruhu bez `lineLimit`u
        // šířka nezalomeného textu — přesně to, co potřebujeme vědět. **Že to tady doopravdy
        // platí, je změřené**, ne předpokládané (`TabStripWidthTests`): pruh v tabu 1347 b nakreslí
        // `bar(.full)`, v 1097 b `bar(.labels)` a v 647 b `bar(.icons)`, pixel po pixelu. To je ten
        // rozdíl proti #284, kde `ViewThatFits` vybíral pořád nejširší variantu a rozhodovat musela
        // spočítaná šířka (`TextWidth`): tam byly popisky v řadě se `lineLimit`em, takže se
        // **zkracovaly** a ideální šířka o zúžení nic neřekla. Tady se pruh **zalomí**, a proto
        // ideální šířka zůstává šířkou celého popisku.
        //
        // Podoby jsou vypsané, ne `ForEach` přes `Layout.allCases`: `ViewThatFits` vybírá mezi
        // **svými dětmi**, a jedna `ForEach` je jedno dítě — kandidáti by se z ní stali leda
        // shodou okolností, kterou by nikdo nekontroloval.
        ViewThatFits(in: .horizontal) {
            bar(.full)
            bar(.labels)
            bar(.icons)
            bar(.compact)
        }
    }

    /// Jedna podoba i s okrajem a linkou pod sebou — tedy **celý** pruh, ne jen jeho obsah.
    ///
    /// Okraj je uvnitř kandidáta schválně: je to šířka, která se taky musí vejít, takže patří
    /// k tomu, co `ViewThatFits` porovnává. A `internal` je proto, aby se dala **změřit
    /// a vyrendrovat jedna podoba** bez toho, aby si test skládal okraj a linku sám — dvě místa
    /// s toutéž chromí by znamenala, že měření kontroluje něco jiného, než co se kreslí (#236).
    func bar(_ layout: Layout) -> some View {
        strip(layout)
            .padding(.horizontal, 12)
            // **Ne `Divider()`.** Ten si orientaci bere z okolní osy a v `overlay` žádná není,
            // takže by se vykreslil svisle — tatáž past jako u hlaviček souborů v diffu.
            .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 1) }
    }

    /// Co z pruhu zbyde, jak se okno zužuje. **Pořadí je rozhodnutí**, ne vedlejší efekt: bere se
    /// první podoba, která se vejde, takže pořadí říká, co ustupuje dřív.
    ///
    /// **`+X −Y` jde první** (#316) — mluví o rozsahu **celého PR**, což je odpověď na otázku
    /// `Změněných souborů`; v `Commitech`, `Kontrolách` ani `Průběhu` není o čem. Záložka je proti
    /// tomu cesta k obsahu, který jinudy vidět není.
    ///
    /// **Popisky jdou druhé, a všechny naráz** (#318). Ustupovat po jednom (nejdřív `Změněné
    /// soubory`, pak `Konverzace`…) by znamenalo pruh, ve kterém část záložek má text a část ne —
    /// tedy sedm různých podob podle šířky místo tří, a v každé jinak dlouhý skok mezi sousedy.
    ///
    /// **Popisek u aktivní záložky zůstává**, protože odpovídá na jinou otázku než ostatní: ne
    /// „kam se dá jít“, ale „kde jsem“. Podtržení to říká taky, jenže samo o sobě jen u jedné ze
    /// sedmi ikon — a to je zrovna ten údaj, kvůli kterému se do pruhu kouká nejčastěji.
    ///
    /// **Čtvrtá podoba přibyla u #452 — a je to změna měření, ne změna názoru.** Do té doby tady
    /// stálo, že samotné ikony bez popisku i u aktivní záložky **nevzniknou**, protože se na ně
    /// nedá přijít: se sedmi záložkami se `icons` vešly do tabu od 564 b (okno 617) a i
    /// s trojmístnými odznaky u všech od 636 b (okno 689), tedy pod podlahu okna 700.
    ///
    /// Osmá záložka (`Zeptat se`, #452) to posunula: `icons` s trojmístnými odznaky chtějí podle
    /// nového měření **645 až 711 b** podle toho, která záložka je aktivní — a tab v nejužším okně
    /// má 647. Šest z osmi podob se tedy nevejde a pruh by se v tom krajním stavu **zalomil**, což
    /// je přesně ta porucha, kterou #318 opravovalo. Kód, který nikdo neuvidí, je horší než měření;
    /// tady ale to měření říká, že se na něj přijít **dá**.
    enum Layout: CaseIterable {
        /// Jak to má být: popisky u všech záložek a vpravo `+X −Y`.
        case full
        /// Bez rozsahu změny. Popisky zůstávají.
        case labels
        /// Ikony s odznaky; popisek jen u aktivní záložky.
        case icons
        /// Jen ikony s odznaky — **ani u aktivní záložky popisek není**.
        ///
        /// Poslední záchrana pro krajní stav (trojmístné odznaky v nejužším okně). Ztrácí se v ní
        /// jediná vypsaná odpověď na „kde jsem“, ale zbývá podtržení — a zalomený pruh je horší:
        /// ztrojnásobí výšku a odsune obsah, kvůli kterému je okno otevřené.
        case compact

        /// Kreslí se v téhle podobě popisek? Vyčerpávající `switch`, ne `!= .icons`: pátá podoba
        /// by jinak mlčky dostala popisky podle toho, kam ji někdo napsal.
        func showsLabel(isActive: Bool) -> Bool {
            switch self {
            case .full, .labels: true
            case .icons: isActive
            case .compact: false
            }
        }
    }

    /// Jedna podoba pruhu. Záložky jsou ve všech tytéž — liší se **jen** tím, co se u nich
    /// nakreslí; kdyby se lišilo i něco jiného, byly by to tři obrazovky místo jedné.
    private func strip(_ layout: Layout) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(PullRequestTab.allCases.enumerated()), id: \.element) { index, tab in
                if needsSeparator(before: index) { separator }
                item(tab, layout: layout)
            }
            Spacer(minLength: 8)
            if layout == .full, let diffCounts { diffstat(diffCounts) }
        }
    }

    /// Patří před tuhle záložku dělič? (#242, `.tsep`)
    ///
    /// Rozhoduje **vlastnost tabu**, ne jeho index: `Kontroly` (#215) sedí nalevo doprostřed,
    /// takže zadrátovaná pozice by dělič posunula o jedno místo vedle. Od #306 je pruh konstantní,
    /// takže by se dala spočítat i z indexu — vlastnost přesto zůstává, protože o tom, kde dělič
    /// patří, rozhoduje **do které skupiny záložka patří**, a to je odpověď, která přežije i další
    /// záložku vloženou doprostřed.
    ///
    /// **Porovnává se skupina, ne příznak** (#452): od `Zeptat se` jsou skupiny tři, takže dělič
    /// je všude, kde se skupina změní — a `Bool` z #242 by ten druhý předěl nedokázal popsat.
    private func needsSeparator(before index: Int) -> Bool {
        guard index > 0 else { return false }
        let tabs = PullRequestTab.allCases
        return tabs[index].group != tabs[index - 1].group
    }

    /// Dělič v pruhu záložek: nalevo je to, co je na PR (a co má i GitHub), uprostřed to, co s ním
    /// udělaly naše reviewery, vpravo rozhovor (#452). Bez něj vypadá řada záložek jako jeden
    /// dlouhý seznam.
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

    private func item(_ tab: PullRequestTab, layout: Layout) -> some View {
        let isActive = selection == tab
        let showsLabel = layout.showsLabel(isActive: isActive)
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { selection = tab }
        } label: {
            content(tab, isActive: isActive, showsLabel: showsLabel)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? tab : (hovered == tab ? nil : hovered) }
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        // Bez popisku je ikona jediné, co záložku pojmenovává — a to je na kurzor málo. Nápověda
        // se proto přidává **jen v úzkém pruhu**; nad vypsaným popiskem by opakovala, co je vidět.
        .modifier(TabTooltip(label: showsLabel ? nil : tab.czechLabel))
    }

    /// Nápověda, která tam **buď je, nebo není** — `help("")` by na `NSView` nechalo prázdný
    /// tooltip, tedy obdélník bez textu.
    private struct TabTooltip: ViewModifier {
        let label: String?

        @ViewBuilder func body(content: Content) -> some View {
            if let label { content.help(label) } else { content }
        }
    }

    /// Jméno pro odečítání na ikoně — taky **buď, anebo**. Prázdný řetězec by u ikony nastavil
    /// prázdné jméno, a tím by se v širokém pruhu měnilo chování, které se měnit nemá: tam popisek
    /// je a ikona má zůstat tichá přesně tak, jako byla.
    private struct TabIconName: ViewModifier {
        let label: String?

        @ViewBuilder func body(content: Content) -> some View {
            if let label { content.accessibilityLabel(label) } else { content }
        }
    }

    private func content(_ tab: PullRequestTab, isActive: Bool, showsLabel: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol(of: tab))
                .font(.caption)
                // **Jméno záložky nesmí zmizet i pro odečítání** (#318). Když se popisek nekreslí,
                // převezme ho ikona — jinak by VoiceOver četl jen odznak, tedy „3“ bez toho, čeho
                // tři. Nad vypsaným popiskem se nenastavuje nic, ať se jméno nečte dvakrát.
                .modifier(TabIconName(label: showsLabel ? nil : tab.czechLabel))
            if showsLabel {
                Text(verbatim: tab.czechLabel)
                    .font(.callout.weight(isActive ? .semibold : .regular))
            }
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
        // Cesta od bodu k bodu — `Commity` jsou **postup**, ne historie. Hodiny by mluvily o čase,
        // což je otázka `Konverzace`, a větev (`arrow.trianglehead.branch`) o topologii, kterou tab
        // neukazuje. Je to zároveň nejužší z uvažovaných (13 b proti 14–17), a šířka je u sedmé
        // záložky to jediné, co doopravdy stojí.
        case .commits: "point.topleft.down.to.point.bottomright.curvepath"
        case .conversation: "bubble.left.and.bubble.right"
        // Seznam s odškrtnutím, ne `checkmark.circle`: kolečko se v hlavičce používá na **výsledek**
        // (zelené prošlo, červené spadlo), kdežto ikona záložky má říkat, co v ní je — a to je
        // seznam kontrol, ať dopadly jakkoli.
        case .checks: "checklist"
        // Lupa nad textem je tentýž symbol, jakým se v ose hlásí `ReportFindings` — nálezy mají
        // v okně jednu ikonu, ne dvě.
        case .findings: "text.magnifyingglass"
        case .progress: "chart.bar.doc.horizontal"
        // Bublina s otazníkem: je to **otázka**, ne diskuze — `bubble.left.and.bubble.right`
        // patří `Konverzaci` a dvě bubliny v jednom pruhu by se pletly. Otazník uvnitř říká, že
        // se tu ptám já, ne že si tu píšou kolegové.
        case .ask: "questionmark.bubble"
        }
    }
}

#Preview {
    @Previewable @State var selection = PullRequestTab.filesChanged

    // Přes pásmo šířek, ať jsou všechny tři podoby vedle sebe: 1047 je výchozí okno bez railu,
    // 947 je pásmo bez `+X −Y` a 647 je nejužší povolené okno, tedy stupeň s ikonami.
    return VStack(spacing: 24) {
        ForEach([1047.0, 947.0, 647.0] as [CGFloat], id: \.self) { width in
            PullRequestTabBar(selection: $selection) { tab in
                switch tab {
                case .overview: .count(3)
                case .filesChanged: .count(7)
                case .findings: .blocking(2)
                case .progress: .live
                default: nil
                }
            }
            .diffCounts((additions: 248, deletions: 96))
            .frame(width: width)
        }
        Text(verbatim: selection.czechLabel)
    }
    .padding(.vertical, 20)
}
