import SwiftUI

/// Mapa PR — pás pod hlavičkou, ve kterém je každý soubor segment (#501, návrh sekce 42).
///
/// Odpovídá na „jak velký a jak zlý je tenhle PR“ **dřív, než se otevře první soubor**:
/// šířka segmentu roste s logaritmem změněných řádků, barva je nejhorší nález v souboru, nový
/// soubor má tón `ok`, prošlý je tlumený, vlákno je svislá čárka a soubor pod výřezem má obrys.
/// **Nahrazuje pilulku `+248 −96` s pěti čtverečky** v pruhu záložek — říká totéž a víc.
///
/// **Šířky počítá `Policy`, ne rozvržení** (#220, #501): `PullRequestMapStrip` je `Layout`, který
/// se zeptá `Policy.mapWidths(of:in:)` a segmenty umístí. `HStack` umí jen rovným dílem a poměr
/// s minimem by se `frame`y skládat nedal — je to tentýž důvod, proč existuje
/// `ProportionalColumns`.
struct PullRequestMapView: View {
    let map: PullRequestMap
    /// Soubory toho diffu, který je v tabu vidět. Sonda si podle nich hledá rozsahy v obsahu
    /// (`DiffFileExtents` je klíčovaná `FileDiff.id`), pás sám je nepotřebuje.
    let files: [FileDiff]
    let tracking: DiffTracking
    /// Skok na soubor — **tou cestou, kterou skáče paleta** (#184): rozbalit soubor, přepnout na
    /// `Změněné soubory` a odscrollovat na hlavičku.
    let jump: (PullRequestMapSegment) -> Void

    /// Výška pásu z návrhu (`.rv-prmap .strip { height: 10px }`).
    static let stripHeight = 10.0
    /// Mezera mezi segmenty (`gap: 2px`) — a zároveň to, co `Policy` odečítá z dostupné šířky.
    static let stripSpacing = 2.0
    /// Odsazení pásu na stranu. **Stejné jako u hlavičky nad ním** (`controls`), takže pás začíná
    /// pod prvním znakem titulku — změřeno na běžící aplikaci: obojí na x = 68.
    static let horizontalPadding = 16.0
    /// Mezera mezi pásem a popiskem (`gap: 12px`).
    static let summaryGap = 12.0

    /// Šířka celé řádky. Měří se, protože **`availableWidth` sem nedosáhne**: nasazuje se až na
    /// hranici obsahu tabu (`PullRequestDetailView`), a pás stojí nad pruhem záložek. Rozhoduje
    /// o jediné věci — jestli se vejde popisek.
    @State private var rowWidth: Double?

    var body: some View {
        HStack(spacing: Self.summaryGap) {
            strip
                // Jediné vyjednávání v celém pásu, a je na jeho hranici: `Layout` uvnitř dostane
                // konkrétní šířku a od ní už se všechno **počítá** (#220). Bez tohohle by pás
                // v `HStack`u vyšel jako nepružný (na neurčitý dotaz odpovídá minimem), takže by
                // se stáhl do součtu minim a vpravo by zbyl prázdný pruh.
                .frame(maxWidth: .infinity)
                .frame(height: Self.stripHeight)
                // V úzké podobě nese souhrn nápověda — jinak by se `3 prošlé` nedalo přečíst
                // nikde jinde než v hlavičce stromu. Tentýž vzorec jako u `IncrementalDiffBar`.
                .modifier(SummaryTooltip(text: showsSummary ? nil : map.summary))
            if showsSummary {
                Text(verbatim: map.summary)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .fixedSize()
            }
        }
        // **Výšku řádky drží pás, ne popisek** — jinak by se hlavička při složení panelu posunula
        // o tři body, protože řádka mono textu je 13 vysoká a pás 10. Popisek se přes rámec
        // přelije o půldruhého bodu na stranu, což padne do odsazení nad i pod ním (8 a 10)
        // a nikde se neořeže. Změřeno: 20 bodů v obou podobách proti 23 a 20 předtím.
        .frame(height: Self.stripHeight)
        .padding(.horizontal, Self.horizontalPadding)
        // Nahoře nic: hlavička nad pásem má vlastní `padding(.bottom, 8)`, tedy přesně tu mezeru,
        // jakou má návrh mezi `.pr-head` a `.rv-prmap`. Druhé odsazení by ji zdvojilo.
        .padding(.bottom, 10)
        // Šířka se čte **do stavu**, ne v každém snímku: `onGeometryChange` se při nezměněné
        // hodnotě nespustí (#361), takže to není bezpodmínečný zápis z každého průchodu (#358).
        .onGeometryChange(for: Double.self) { $0.size.width } action: { rowWidth = $0 }
        .background(alignment: .topLeading) { probe }
        .background(alignment: .topLeading) { shortcuts }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mapa souborů")
        .accessibilityValue(map.summary)
    }

    /// Vejde se vedle pásu popisek? Rozhoduje `Policy`; šířku popisku měří `TextWidth` **tím
    /// písmem, kterým se kreslí** — jinak by se počítalo s jinou sazbou, než jaká je na obrazovce
    /// (#236).
    private var showsSummary: Bool {
        Policy.mapShowsSummary(
            available: rowWidth.map { $0 - 2 * Self.horizontalPadding },
            label: Self.summaryWidth(of: map.summary),
            gap: Self.summaryGap
        )
    }

    static func summaryWidth(of summary: String) -> Double {
        TextWidth.of(summary, font: .monospacedSystemFont(ofSize: 10.5, weight: .regular))
    }

    /// Nápověda, která tam **buď je, nebo není** — `help("")` by na `NSView` nechalo prázdný
    /// tooltip, tedy obdélník bez textu. Tentýž typ má i pruh záložek.
    private struct SummaryTooltip: ViewModifier {
        let text: String?

        @ViewBuilder func body(content: Content) -> some View {
            if let text { content.help(text) } else { content }
        }
    }

    private var strip: some View {
        PullRequestMapStrip(segments: map.segments, spacing: Self.stripSpacing) {
            ForEach(map.segments) { segment in
                Button { jump(segment) } label: { shape(of: segment) }
                    .buttonStyle(.plain)
                    .help(Policy.mapTooltip(of: segment))
                    .accessibilityLabel(Policy.mapTooltip(of: segment))
            }
        }
    }

    /// Jeden segment: plocha v barvě nejhoršího nálezu, čárky vláken a u toho pod výřezem obrys.
    private func shape(of segment: PullRequestMapSegment) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fill(of: segment))
            // **Prošlý se tlumí krytím, ne jinou barvou** — je to tatáž plocha, jen odbytá práce;
            // druhý odstín na každou barvu by ze škály udělal šest hodnot místo tří.
            // `changed` tlumený **není** (#500): je to práce, která se vrátila.
            .opacity(segment.readState.isRead ? 0.35 : 1)
            .overlay { ticks(of: segment) }
            .overlay { outline(of: segment) }
            .contentShape(.rect)
    }

    /// Barva segmentu. **Nejhorší nález přebíjí druh souboru**: nový soubor s blokujícím nálezem
    /// je červený, ne zelený — pás se čte podle závažnosti.
    private func fill(of segment: PullRequestMapSegment) -> Color {
        switch segment.marker {
        case .blocking: Palette.crit
        case .findings: Palette.find
        case nil: segment.isNew ? Palette.okWash : Palette.raised
        }
    }

    /// Čárky vláken (`.seg .tick`) — akcentem, 2 body široké a **o 4 body vyšší na každou stranu**
    /// než pás, jak je má návrh. Přesah je vidět: uvnitř desetibodového segmentu by se čárka
    /// v plné barvě ztratila.
    @ViewBuilder private func ticks(of segment: PullRequestMapSegment) -> some View {
        if !segment.threads.isEmpty {
            PullRequestMapTicks(fractions: segment.threads) {
                // `id: \.offset`, a je to ta správná identita: čárky jsou nerozlišitelné a dvě
                // vlákna na témž místě mají týž podíl, takže pořadí je jediné, co je odliší.
                // Payload se přes `offset` nekopíruje (#361) a pás navíc není líný seznam.
                ForEach(Array(segment.threads.enumerated()), id: \.offset) { _, _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.accent)
                        .frame(width: 2, height: Self.stripHeight + 8)
                }
            }
        }
    }

    /// Obrys souboru pod výřezem (`outline: 2px solid accent; outline-offset: 2px`).
    ///
    /// `stroke` leží **na** cestě, takže se cesta rozšíří o 3 body — obtah pak sedí 2 až 4 body
    /// od hrany segmentu, jak to má `outline-offset`. Poloměr je poloměr segmentu plus odstup.
    @ViewBuilder private func outline(of segment: PullRequestMapSegment) -> some View {
        if tracking.cursor.path == segment.path {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Palette.accent, lineWidth: 2)
                .padding(-3)
        }
    }

    /// `⌥←`/`⌥→` — předchozí a další soubor od toho, který je pod výřezem.
    ///
    /// Zkratky žijí **tady, ne v detailu PR**: cesta pod výřezem se čte z `DiffFileCursor`, a kdo
    /// ji čte, ten se při jejím posunu překresluje. V těle detailu by to znamenalo přeložit při
    /// každé hranici souboru celé okno.
    ///
    /// Bez souboru pod výřezem (rozsahy ještě nikdo nezměřil) a na krajích pásu je tlačítko
    /// **zakázané** — a zakázané klávesu nebere, takže propadne dál.
    private var shortcuts: some View {
        let current = map.segments.firstIndex { $0.path == tracking.cursor.path }
        return VStack(spacing: 0) {
            WindowShortcutButtons(action: .previousFile, isEnabled: target(from: current, .backward) != nil) {
                step(from: current, .backward)
            }
            WindowShortcutButtons(action: .nextFile, isEnabled: target(from: current, .forward) != nil) {
                step(from: current, .forward)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Neviditelná sonda, která do `DiffFileCursor` zapisuje cestu souboru pod výřezem.
    private var probe: some View {
        PullRequestMapProbe(files: files, tracking: tracking)
    }

    private func target(from current: Int?, _ direction: NavigationStep) -> PullRequestMapSegment? {
        Policy.mapStep(from: current, direction, count: map.segments.count)
            .map { map.segments[$0] }
    }

    private func step(from current: Int?, _ direction: NavigationStep) {
        guard let segment = target(from: current, direction) else { return }
        jump(segment)
    }
}

/// Pás segmentů: šířky ze `Policy`, umístění odsud (#501).
///
/// Vlastní `Layout` ze stejného důvodu jako `ProportionalColumns`: `HStack` umí rozdělit místo
/// jen rovným dílem a `frame(width:)` na každém segmentu by potřeboval znát celkovou šířku, tedy
/// druhé měření vedle toho, které rozvržení dělá samo.
struct PullRequestMapStrip: Layout {
    let segments: [PullRequestMapSegment]
    let spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = proposal.height ?? PullRequestMapView.stripHeight
        // **Bez konečné šířky se podíl nemá z čeho počítat.** Pás nemá přirozenou šířku — roste
        // do té, kterou dostane —, takže se na neurčitý dotaz odpoví **součtem minim**: je to
        // nejmenší šířka, ve které pás ještě říká pravdu o počtu souborů.
        guard let total = proposal.width, total.isFinite, total > 0 else {
            return CGSize(width: minimumWidth(count: subviews.count), height: height)
        }
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, Policy.mapWidths(of: segments, in: bounds.width, spacing: spacing)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func minimumWidth(count: Int) -> Double {
        guard count > 0 else { return 0 }
        // Minimum se bere z `Policy`, ne z vlastní konstanty: dvě pravdy o tom, kdy je pás ještě
        // pás, by znamenaly, že `Layout` odpovídá na neurčitý dotaz jinak, než jak se pak dělí.
        return Policy.mapSegmentMinimum * Double(count) + spacing * Double(count - 1)
    }
}

/// Čárky vláken na podílu své polohy v segmentu (#501).
///
/// Vlastní `Layout`, protože podíl se dá umístit jedině z **šířky, kterou segment doopravdy má** —
/// a tu zná až rozvržení. `offset(x:)` by potřeboval tu šířku změřit podruhé, tedy druhou pravdu
/// o jednom čísle (#236).
struct PullRequestMapTicks: Layout {
    /// Podíl `0…1` na šířce segmentu, jeden na čárku. Pořadí sedí na pořadí dětí.
    let fractions: [Double]

    /// Čárky nic nenafukují — vrší se **nad** segment, takže si berou jeho rozměr.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            guard index < fractions.count else { break }
            let size = subview.sizeThatFits(.unspecified)
            // Vystředěná na svém podílu a **ořezaná do segmentu**: čárka na `1,0` by jinak visela
            // půlkou v mezeře vedle a čtla by se jako patřící sousedovi. Ořez zároveň drží
            // i podíl mimo `0…1`, kdyby ho někdy `Policy` vydala.
            let center = bounds.minX + fractions[index] * bounds.width
            subview.place(
                at: CGPoint(
                    x: min(max(center - size.width / 2, bounds.minX), bounds.maxX - size.width),
                    y: bounds.midY - size.height / 2
                ),
                proposal: ProposedViewSize(size)
            )
        }
    }
}

/// Kdo je pod výřezem — neviditelné view, které to zapisuje do `DiffFileCursor` (#501).
///
/// **Vlastní view, ne kus těla mapy, a je to výkonová podmínka** — tatáž jako u `DiffPinnedHeader`
/// a `DiffReadShortcut` (#469, #500): čte `DiffViewport.top`, tedy hodnotu, která se mění při
/// **každém** otočení kolečka. Kdyby ji čtelo tělo pásu, přeložilo by se při každém snímku i se
/// všemi segmenty, jejich nápovědami a čárkami.
///
/// Odpověď je **kvantovaná**: `Policy.mapCurrentSegment` vydá tentýž soubor po celou dobu, co je
/// pod hranou, takže se do krabice zapíše jen na hranici souborů — a jedině tehdy se překreslí
/// pás. Zápis je proto podmíněný (`onChange`), ne bezpodmínečný (#358).
struct PullRequestMapProbe: View {
    let files: [FileDiff]
    let tracking: DiffTracking

    var body: some View {
        let path = current
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: path, initial: true) { _, new in tracking.cursor.path = new }
    }

    /// Který soubor drží horní hranu výřezu. **Tatáž odpověď, jakou dostane ukotvená hlavička
    /// a `⌥V`** — `Policy.pinnedFileHeader` s nulovou výškou hlavičky, protože ta rozhoduje jen
    /// o vysunutí, ne o tom, který soubor to je.
    private var current: String? {
        guard
            let index = Policy.mapCurrentSegment(
                extents: tracking.extents.ordered(of: files),
                top: tracking.viewport.top
            ),
            files.indices.contains(index)
        else { return nil }
        return files[index].displayPath
    }
}
