import SwiftUI

/// Mapa PR — pás pod hlavičkou, ve kterém je každý soubor segment (#501, návrh sekce 42).
///
/// Odpovídá na „jak velký a jak zlý je tenhle PR“ **dřív, než se otevře první soubor**:
/// šířka segmentu roste s logaritmem změněných řádků, barva je nejhorší nález v souboru, nový
/// soubor má tón `ok`, prošlý je tlumený, vlákno je svislá čárka a soubor pod výřezem má pod
/// sebou jezdce.
/// **Nahrazuje pilulku `+248 −96` s pěti čtverečky** v pruhu záložek — říká totéž a víc.
///
/// **Pás je jedna kresba, ne řada tlačítek — a je to výkonová podmínka** (#252, #501). První
/// podoba dělala ze segmentu `Button` s nápovědou, dvěma `overlay`y a `contentShape`; u PR
/// o 158 souborech to je 158 tlačítek a přes tisíc views v hlavičce, které se **při každém
/// přerovnání okna znovu umisťují**. Naměřeno na ostrých datech (`cli/cli#14320`, 158 souborů):
/// přerovnání okna stálo **70 ms** proti 14 ms nad týmž oknem s ablovaným pásem a přepnutí tabu
/// **bez diffu** 162 ms proti 57 — tedy cena, která roste **s počtem souborů**, ne s výřezem.
/// Po přepsání je to 19, resp. 63 ms.
/// Od té doby kreslí pás jediný `Canvas` a polohu segmentů počítá `PullRequestMapGeometry`.
///
/// **Kolem kresby stojí tři malá views a každé z nich existuje z téhož důvodu**: co se mění jinak
/// často, nesmí přeložit tělo pásu. `PullRequestMapHoverLayer` drží nápovědu, hover a klik (hranice
/// segmentu je při 158 souborech dva body, takže přejezd myší je 157 změn),
/// `PullRequestMapLegendButton` drží popisek s legendou i její otevřený stav
/// a `PullRequestMapProbe` čte výřez. Čísla jsou v `docs/testovani.md`.
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
    /// Šířka základny jezdce — značky souboru pod výřezem (#501).
    static let markerWidth = 14.0
    /// Výška jezdce, tedy o kolik přečnívá pás **pod** ním.
    static let markerHeight = 7.0
    /// O kolik plocha přečnívá pás na každou stranu. Rozhoduje **ta vyšší z obou značek**, tedy
    /// jezdec; čárka vlákna si dál bere svoje čtyři body. Symetricky schválně — kresba se v řádce
    /// středí, takže asymetrická plocha by pás posunula o rozdíl nahoru.
    static var markerOverhang: Double { markerHeight }
    /// Plocha, na kterou se kreslí. **Vyšší než pás**, protože čárka vlákna i jezdec přečnívají —
    /// `Canvas` si kresbu ořezává do svého rámce, takže by se jinak zarovnaly s hranou pásu.
    /// Řádka zůstává vysoká `stripHeight` a plocha z ní přečnívá, takže se výška hlavičky nemění.
    static var canvasHeight: Double { stripHeight + 2 * markerOverhang }

    /// Šířka celé řádky. Měří se, protože **`availableWidth` sem nedosáhne**: nasazuje se až na
    /// hranici obsahu tabu (`PullRequestDetailView`), a pás stojí nad pruhem záložek. Rozhoduje
    /// o jediné věci — jestli se vejde popisek.
    @State private var rowWidth: Double?

    var body: some View {
        HStack(spacing: Self.summaryGap) {
            strip
            if showsSummary {
                // **Popisek je od #501 tlačítko k legendě** (varianta A) a stav si drží sám, aby
                // otevření legendy nepřeložilo tělo pásu i s kresbou.
                PullRequestMapLegendButton(summary: map.summary)
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
        // **Nápověda, hover a klik leží ve vlastní vrstvě** (#501): dokud je držel pás, přeložil
        // přejezd hranice segmentu tělo mapy a překreslil celou kresbu. Trefení má pořád jediný
        // zdroj — `PullRequestMapGeometry`, jen měřený tam, kde se na něj ptají gesta.
        .overlay {
            PullRequestMapHoverLayer(
                segments: map.segments,
                spacing: Self.stripSpacing,
                summary: map.summary,
                jump: jump
            )
        }
        // **Pás je jeden accessibility element**, ne 158 prvků: per-segment odečítání by ty views
        // muselo postavit, tedy vrátit cenu, kvůli které je pás kresba. Sedí to na kresbě, ne na
        // řádce, aby popisek s legendou zůstal vlastním tlačítkem.
        .accessibilityElement()
        .accessibilityLabel("Mapa souborů")
        .accessibilityValue(map.summary)
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
            let fill = Self.fill(of: Policy.mapFill(of: segment))
                .opacity(segment.readState.isRead ? Policy.mapReadOpacity : 1)
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(fill))
            for fraction in segment.threads { Self.drawTick(in: &context, at: fraction, in: rect) }
            if current == segment.path { Self.drawMarker(in: &context, under: rect, in: size) }
        }
    }

    /// Čárka vlákna (`.seg .tick`) — akcentem, 2 body široká a o čtyři body vyšší na každou stranu
    /// než pás, jak ji má návrh. Přesah je vidět: uvnitř desetibodového segmentu by se čárka
    /// v plné barvě ztratila.
    ///
    /// **Vystředěná na svém podílu a ořezaná do segmentu**: čárka na `1,0` by jinak visela půlkou
    /// v mezeře vedle a čtla by se jako patřící sousedovi.
    static func drawTick(in context: inout GraphicsContext, at fraction: Double, in rect: CGRect) {
        let width = 2.0
        let center = rect.minX + fraction * rect.width
        let x = min(max(center - width / 2, rect.minX), max(rect.maxX - width, rect.minX))
        let tick = CGRect(
            x: x,
            y: rect.minY - Self.tickOverhang,
            width: width,
            height: rect.height + 2 * Self.tickOverhang
        )
        context.fill(Path(roundedRect: tick, cornerRadius: 1), with: .color(fill(of: .thread)))
    }

    /// Jezdec — značka souboru pod výřezem (`.rv-prmap .runner` v návrhu, sekce 42).
    ///
    /// **Pevný trojúhelník 14 × 7 bodů pod pásem, hrotem v ose segmentu.** Nahradil obrys, a je to
    /// změna z **měření, ne z chuti**: obrys byl `outline-offset`, tedy odstup od segmentu, takže
    /// byl vždycky o osm bodů širší než to, co obtahoval — nad hustým pásem pojmenovával okolí víc
    /// než svůj soubor (podíl cílového segmentu spadl z 91–98 % u tří souborů na **21–30 %** u sto
    /// padesáti osmi) a měl přitom **tolik inkoustu a týž tvar co jedna čárka vlákna** (39 proti
    /// 36–44 b²). Čísla jsou v `docs/architektura.md`.
    ///
    /// Tři vlastnosti, na kterých ta náhrada stojí, a všechny tři jsou kontrolovatelné:
    ///
    /// - **velikost nezávisí na šířce segmentu** — jinak se značka rozpadne zrovna tam, kde je pás
    ///   nejužitečnější;
    /// - **hrot je bod**, takže ukazuje přesně i tehdy, když je značka širší než cíl. Obrys naopak
    ///   *obklopoval*, a to při dvou bodech šířky ztrácí smysl;
    /// - **tvar se nedá splést s čárkou vlákna** — čárka má dva body v každém svém řádku, jezdec
    ///   čtrnáct u základny.
    ///
    /// **Hrot zůstává na skutečném středu segmentu, základna se ořezává do plochy.** U prvního
    /// a posledního segmentu tedy vyjde jezdec nesymetrický, a je to vědomá volba: posunutý hrot
    /// by ukazoval na soubor, který to není. Obrys měl na krajích tutéž vadu **nepřiznaně** —
    /// jeho vnější hrana ležela na `x = −4`, tedy mimo plochu, a `Canvas` ji potichu ořezal.
    static func drawMarker(in context: inout GraphicsContext, under rect: CGRect, in size: CGSize) {
        let center = rect.midX
        let half = markerWidth / 2
        let left = max(center - half, 0)
        let right = min(center + half, size.width)
        let base = rect.maxY + markerHeight
        var path = Path()
        path.move(to: CGPoint(x: center, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: base))
        path.addLine(to: CGPoint(x: left, y: base))
        path.closeSubpath()
        context.fill(path, with: .color(fill(of: .current)))
    }

    /// Barva tónu — **jedno místo pro kresbu i pro legendu** (#501). Kdyby si legenda barvy
    /// dosadila sama, rozejití by nebylo vidět: obojí je ta samá barva, jen jinde. Který tón
    /// segment dostane, rozhoduje `Policy.mapFill(of:)`.
    static func fill(of tone: PullRequestMapTone) -> Color {
        switch tone {
        case .blocking: Palette.crit
        case .findings: Palette.find
        case .new: Palette.okWash
        case .clean, .read: Palette.raised
        case .thread, .current: Palette.accent
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

    /// Šířka popisku **tím písmem a s tím textem, jaký se kreslí** (#236) — tedy včetně `▾`,
    /// které z popisku dělá tlačítko k legendě. Bez toho znaku by práh na skrytí popisku počítal
    /// s o třináct bodů užší řádkou, než jaká je na obrazovce (naměřeno: 273 proti 286 bodům nad
    /// popiskem `7 souborů · 3 prošlé · 5 nálezů · 2 vlákna`).
    static func summaryWidth(of summary: String) -> Double {
        TextWidth.of(
            PullRequestMapLegendButton.title(of: summary),
            font: .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        )
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
