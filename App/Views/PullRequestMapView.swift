import SwiftUI

/// Mapa PR — pás pod hlavičkou, ve kterém je každý soubor segment (#501, návrh sekce 42).
///
/// Odpovídá na „jak velký a jak zlý je tenhle PR“ **dřív, než se otevře první soubor**:
/// šířka segmentu roste s logaritmem změněných řádků, barva je nejhorší nález v souboru, nový
/// soubor má tón `ok`, prošlý je tlumený, vlákno je svislá čárka a soubor pod výřezem má obrys.
/// **Nahrazuje pilulku `+248 −96` s pěti čtverečky** v pruhu záložek — říká totéž a víc.
///
/// **Pás je jedna kresba, ne řada tlačítek — a je to výkonová podmínka** (#252, #501). První
/// podoba dělala ze segmentu `Button` s nápovědou, dvěma `overlay`y a `contentShape`; u PR
/// o 158 souborech to je 158 tlačítek a přes tisíc views v hlavičce, které se **při každém
/// přerovnání okna znovu umisťují**. Naměřeno na ostrých datech (`cli/cli#14320`, 158 souborů):
/// přerovnání okna stálo **70 ms** proti 14 ms nad týmž oknem s ablovaným pásem a přepnutí tabu
/// **bez diffu** 162 ms proti 57 — tedy cena, která roste **s počtem souborů**, ne s výřezem.
/// Po přepsání je to 19, resp. 63 ms.
/// Od té doby kreslí pás jediný `Canvas`, polohu segmentů počítá `PullRequestMapGeometry`
/// a nápovědu i klik obstarává **jedno** gesto.
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
    /// O kolik čárka vlákna přečnívá pás na každou stranu (`top: -4px; bottom: -4px`).
    static let tickOverhang = 4.0
    /// Plocha, na kterou se kreslí. **Vyšší než pás**, protože čárka vlákna i obrys přečnívají —
    /// `Canvas` si kresbu ořezává do svého rámce, takže by se jinak zarovnaly s hranou pásu.
    /// Řádka zůstává vysoká `stripHeight` a plocha z ní přečnívá, takže se výška hlavičky nemění.
    static var canvasHeight: Double { stripHeight + 2 * tickOverhang }

    /// Šířka celé řádky. Měří se, protože **`availableWidth` sem nedosáhne**: nasazuje se až na
    /// hranici obsahu tabu (`PullRequestDetailView`), a pás stojí nad pruhem záložek. Rozhoduje
    /// o jediné věci — jestli se vejde popisek.
    @State private var rowWidth: Double?
    /// Šířka samotného pásu. Kresba si ji bere z `Canvas`u (tam je vždycky přesná), tahle kopie
    /// je pro **nápovědu a klik**: gesto hlásí polohu, ne velikost, takže se poloha musí umět
    /// přeložit na segment i mimo kreslicí uzávěr.
    @State private var stripWidth = 0.0
    /// Segment pod kurzorem. Zapisuje se **jen při změně** (`Policy.hoverChange`, #358) — jinak by
    /// každý hover update překreslil pás.
    @State private var hovered: Int?

    var body: some View {
        HStack(spacing: Self.summaryGap) {
            strip
            if showsSummary {
                Text(verbatim: map.summary)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .fixedSize()
            }
        }
        // **Výšku řádky drží pás, ne popisek ani kreslicí plocha** — jinak by se hlavička při
        // složení panelu posunula o tři body (řádka mono textu je 13 vysoká, pás 10) a čárka
        // vlákna by ji zvedla o dalších osm. Obojí z rámce přečnívá a nikde se to neořeže.
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
        .accessibilityElement()
        .accessibilityLabel("Mapa souborů")
        .accessibilityValue(map.summary)
    }

    /// Pás jako **jedna kresba**. `Canvas` dostane šířku, kterou mu dá řádka, a od ní se všechno
    /// **počítá** (#220) — geometrie je `PullRequestMapGeometry`, tedy tentýž zdroj, ze kterého se
    /// trefuje kurzor i klik.
    private var strip: some View {
        // **Cesta pod výřezem se čte tady, ne v kreslicím uzávěru**, a je to podmínka, ne styl:
        // uzávěr `Canvas`u se vyhodnocuje při kreslení, tedy **mimo** sledování, které si SwiftUI
        // zapisuje při průchodu tělem. Kdyby si `cursor.path` přečetl on, závislost by se
        // nezaregistrovala a obrys by se po přejezdu na jiný soubor **nepřekreslil** — dokud by
        // tutéž hodnotu nečetlo něco jiného v témže těle (dnes `shortcuts`, tedy náhodou).
        let current = tracking.cursor.path
        return Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            draw(in: &context, size: size, current: current)
        }
        // **Jediné vyjednávání v celém pásu, a je na jeho konci** (#220): pod tímhle rámcem už
        // není nic, čemu by se nabídka předávala — `Canvas` je list a od jeho šířky se všechno
        // dál **počítá**. Bez toho by pás v `HStack`u vyšel jako plocha o nulové šířce, protože
        // `Canvas` si o šířku sám neříká.
        .frame(maxWidth: .infinity)
        .frame(height: Self.canvasHeight)
        // Šířka **pro gesta**: kresba ji má z uzávěru, ale nápověda a klik hlásí jen polohu.
        // Čte se do stavu, ne v každém snímku — při nezměněné hodnotě se akce nespustí (#361).
        .onGeometryChange(for: Double.self) { $0.size.width } action: { stripWidth = $0 }
        // Nápověda je **jedna**, ne na segment: `Canvas` je jediné view, takže se text mění podle
        // toho, co je pod kurzorem. Nad prázdným místem nese souhrn — v úzké podobě je to jediné
        // místo, kde se `3 prošlé` dá přečíst.
        .help(hoveredTooltip)
        .onContinuousHover(coordinateSpace: .local) { phase in
            let next: Int? = if case .active(let point) = phase { geometry.index(at: point.x) } else { nil }
            if case .write(let value) = Policy.hoverChange(from: hovered, to: next) { hovered = value }
        }
        .gesture(SpatialTapGesture(coordinateSpace: .local).onEnded { value in
            guard let index = geometry.index(at: value.location.x),
                  map.segments.indices.contains(index)
            else { return }
            jump(map.segments[index])
        })
    }

    /// Geometrie pásu ze **změřené** šířky. Kresba používá tu z `Canvas`u (je vždycky přesná);
    /// tahle je pro gesta, která hlásí polohu, ne velikost.
    private var geometry: PullRequestMapGeometry {
        PullRequestMapGeometry(segments: map.segments, width: stripWidth, spacing: Self.stripSpacing)
    }

    private var hoveredTooltip: String {
        guard let hovered, map.segments.indices.contains(hovered) else { return map.summary }
        return Policy.mapTooltip(of: map.segments[hovered])
    }

    /// Jeden průchod kresbou: plochy segmentů, čárky vláken a obrys u toho pod výřezem.
    private func draw(in context: inout GraphicsContext, size: CGSize, current: String?) {
        let geometry = PullRequestMapGeometry(
            segments: map.segments,
            width: size.width,
            spacing: Self.stripSpacing
        )
        let top = (size.height - Self.stripHeight) / 2
        for index in map.segments.indices {
            guard let span = geometry.span(of: index) else { continue }
            let segment = map.segments[index]
            let rect = CGRect(
                x: span.lowerBound,
                y: top,
                width: span.upperBound - span.lowerBound,
                height: Self.stripHeight
            )
            // **Prošlý se tlumí krytím, ne jinou barvou** — je to tatáž plocha, jen odbytá práce;
            // druhý odstín na každou barvu by ze škály udělal šest hodnot místo tří.
            // `changed` tlumený **není** (#500): je to práce, která se vrátila.
            let fill = fill(of: segment).opacity(segment.readState.isRead ? 0.35 : 1)
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(fill))
            for fraction in segment.threads { drawTick(in: &context, at: fraction, in: rect) }
            if current == segment.path { drawOutline(in: &context, around: rect) }
        }
    }

    /// Čárka vlákna (`.seg .tick`) — akcentem, 2 body široká a o čtyři body vyšší na každou stranu
    /// než pás, jak ji má návrh. Přesah je vidět: uvnitř desetibodového segmentu by se čárka
    /// v plné barvě ztratila.
    ///
    /// **Vystředěná na svém podílu a ořezaná do segmentu**: čárka na `1,0` by jinak visela půlkou
    /// v mezeře vedle a čtla by se jako patřící sousedovi.
    private func drawTick(in context: inout GraphicsContext, at fraction: Double, in rect: CGRect) {
        let width = 2.0
        let center = rect.minX + fraction * rect.width
        let x = min(max(center - width / 2, rect.minX), max(rect.maxX - width, rect.minX))
        let tick = CGRect(
            x: x,
            y: rect.minY - Self.tickOverhang,
            width: width,
            height: rect.height + 2 * Self.tickOverhang
        )
        context.fill(Path(roundedRect: tick, cornerRadius: 1), with: .color(Palette.accent))
    }

    /// Obrys souboru pod výřezem (`outline: 2px solid accent; outline-offset: 2px`).
    ///
    /// Obtah leží **na** cestě, takže se cesta rozšíří o tři body — obrys pak sedí 2 až 4 body od
    /// hrany segmentu, jak to má `outline-offset`. Poloměr je poloměr segmentu plus odstup.
    private func drawOutline(in context: inout GraphicsContext, around rect: CGRect) {
        context.stroke(
            Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 4),
            with: .color(Palette.accent),
            lineWidth: 2
        )
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

/// Kdo je pod výřezem — neviditelné view, které to zapisuje do `DiffFileCursor` (#501).
///
/// **Vlastní view, ne kus těla mapy, a je to výkonová podmínka** — tatáž jako u `DiffPinnedHeader`
/// a `DiffReadShortcut` (#469, #500): čte `DiffViewport.top`, tedy hodnotu, která se mění při
/// **každém** otočení kolečka. Kdyby ji čtelo tělo pásu, překreslila by se při každém snímku celá
/// kresba i s nápovědou a zkratkami.
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
