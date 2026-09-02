import SwiftUI

/// Blok kódu v diffu i s tím, co na řádcích visí (#157).
///
/// Text kreslí `DiffCodeBlockView` (`NSTextView`), tenhle view k němu přidává to, co se od textu
/// odvozuje polohou: **pilulku na komentář** u řádku pod myší a **tažení rozsahu**. Obojí je
/// v overlay, protože v textovém view by to znamenalo psát vlastní hit-testing.
struct DiffBlockRowView: View {
    let block: DiffBlock
    var language: Language?
    /// Akce rozdělaného review svázané s tímhle souborem.
    var draft = FileDraftActions()
    var performDraftAction: (LineDraftAction, Bool) -> Void = { _, _ in }
    /// Buňky, které leží v rozsahu některého mého komentáře (#110).
    var commentRangeCells: Set<DraftAnchor.Endpoint> = []
    /// Totéž pro rozsah, který se právě táhne.
    var draggedCells: Set<DraftAnchor.Endpoint> = []
    var dragEnd: DraftAnchor.Endpoint?
    var rangeDrag = RangeDragActions()
    /// Identita bloku — z ní se skládají identity řádků pro `DiffRowFrames`.
    var blockID: String = ""
    /// Kopírování z kontextového menu (#157).
    var copy = DiffCopyActions()
    /// Cesta souboru, ve kterém blok leží (#152). Z ní se pozná, jestli tomuhle bloku patří
    /// **aktuální** výskyt hledání — `DiffLine` se totiž mezi dvěma soubory umí shodovat.
    var filePath: String = ""
    /// Řádky, ke kterým se v okraji váže karta (#503) — klíčované **novým** číslem řádku, protože
    /// právě na něj se nález kotví. Prázdné = okraj se nekreslí (bubliny zapnuté, náhledy, testy).
    var marginMarks: [Int: DiffMarginMark] = [:]
    /// Kam se hlásí, kde ty řádky leží. `nil` = nikdo se neptá.
    var marginAnchors: DiffMarginAnchors?

    @Environment(\.colorScheme) private var colorScheme
    /// Hledání v tomhle diffu (#152). **Prostředím, ne parametrem, a je to výkonové rozhodnutí:**
    /// dotaz se mění při každém písmenu, takže kdyby ho `DiffView` předával argumentem, přeložilo by
    /// se při každém znaku celé jeho tělo. Takhle se čte až tady, tedy v bloku — a `DiffView` sám na
    /// dotaz nesahá (viz `DiffSearchState`).
    @Environment(DiffSearchState.self) private var search: DiffSearchState?
    /// Rámečky řádků, které ohlásilo textové view. `@State`, protože se z nich staví overlay.
    @State private var frames: [DiffBlockLineFrame] = []
    /// Řádek pod myší — jen jeho pilulka je vidět, jako dosud u `DiffLineView`.
    @State private var hovered: Int?
    /// Poloha bloku v prostoru obsahu, **mimo observable stav** — viz `DiffBlockPlacement` (#252).
    @State private var placement = DiffBlockPlacement()

    /// **Blok se nasazuje jen v pásu kolem výřezu** (#469) — viz `DiffBlockSlot`. Obaluje se celé
    /// tělo, ne jen text: plocha na tažení, pilulka i hlášení rámečků stojí tolik co on.
    var body: some View {
        DiffBlockSlot { mounted }
    }

    private var mounted: some View {
        DiffCodeBlockView(
            block: block,
            language: language,
            colorScheme: colorScheme,
            search: searchHighlight,
            commentRangeLines: rows(in: commentRangeCells),
            draggedLines: rows(in: draggedCells),
            // **Rámečky se posílají dál i argumentem, ne jen přes `@State`** (#503): zápis do
            // `frames` je vidět až v dalším průchodu tělem, takže `noteRows()` hned za ním by
            // čtl ty **staré** (změřeno: nula, i když textové view zrovna ohlásilo devět).
            // Krabice se pak plnily teprve z `onGeometryChange` níž, tedy až se blokem něco
            // pohnulo — a karta v okraji na ten okamžik nemá jak čekat.
            noteFrames: { frames = $0; noteRows(measured: $0) }
        )
        // Plocha na tažení a pilulka leží nad textem, pozicované podle rámečků řádků.
        .overlay(alignment: .topLeading) { gutter }
        // Pruh závažnosti na **pravé** hraně řádku s kartou (#503).
        .overlay(alignment: .topTrailing) { marginStripes }
        // Rámeček **celého bloku** v souřadnicích obsahu diffu — jeden na blok, ne jeden na řádek
        // (#252). Plochy řádků se z něj dopočítají aritmetikou (`DiffGutterGeometry`).
        .onGeometryChange(for: CGRect.self) {
            RenderDiagnostics.inGraph(.blockGeometry)
            return $0.frame(in: .named(DiffView.contentSpace))
        } action: { rect in
            placement.rect = rect
            noteRows()
        }
        // **Rozhoduje jen `y`, ne celý rámeček řádku.** Rámečky jsou rámečky *textu*, takže začínají
        // až za sloupcem s čísly — a `contains(point)` znamenalo, že jak myš zamířila na pilulku,
        // hover zhasl a pilulka zmizela pod rukou. Nedalo se na ni kliknout (nahlášené při zkoušení
        // #157); je to tatáž past jako u #98, kde tlačítko vyčnívalo do dalšího řádku.
        //
        // **Zapisuje se jedině při změně** (#358) — viz `Policy.hoverChange(from:to:)`. Tady je
        // hodnota `Int?`, tedy porovnatelná odjakživa; ve split pohledu na to musel vzniknout
        // `HoveredCell`. Podmínka je v obou stejná a je na jednom místě schválně: druhá kopie by se
        // s tou první rozešla a poznalo by se to až na 99 % CPU.
        .onContinuousHover { phase in
            let next: Int? = switch phase {
            case .active(let point): geometry.line(atY: point.y)?.index
            case .ended: nil
            }
            if case .write(let index) = Policy.hoverChange(from: hovered, to: next) { hovered = index }
        }
        // **Menu se připojuje bezpodmínečně**, ne přes `copyMenu(_:selectText:)`. Ten podle stavu
        // vybírá mezi `self` a `contextMenu`, čímž mění **strukturu** view — a jak myš odjede z bloku
        // a nabídka se vyprázdní, SwiftUI zahodí podstrom a postaví nový `NSTextView`. S ním zmizí
        // výběr. Změřeno: pohyb uvnitř bloku i na druhý blok výběr přežil, pohyb na hlavičku hunku
        // ho zrušil.
        .contextMenu {
            ForEach(copyTargets) { target in
                Button(target.title, systemImage: "doc.on.doc") { Clipboard.copy(target.text) }
            }
            if let selectText {
                Divider()
                Button("Vybrat text z hunku…", systemImage: "text.cursor", action: selectText)
            }
        }
    }

    /// Co se v tomhle bloku zvýrazní jako výsledek hledání (#152).
    ///
    /// Rozhoduje `Policy`, ne tenhle view: **zavřený pruh nezvýrazňuje nic** (`drawnQuery`)
    /// a aktuální výskyt se propouští jedině do svého souboru.
    private var searchHighlight: DiffSearchHighlight {
        guard let search else { return .none }
        return Policy.searchHighlight(query: search.drawnQuery, current: search.currentHit, in: filePath)
    }

    /// Sloupec s čísly: plocha na tažení rozsahu a v ní pilulka na komentář.
    ///
    /// Poloha se **počítá z rámečků řádků**, které hlásí layout textového view — jediný zdroj
    /// pravdy o tom, kde řádek je (dlouhý kód se v tomhle pohledu zalomí, takže řádky mají různou
    /// výšku a `index × výška` by lhal).
    ///
    /// **Jeden prvek na blok a jedna pilulka, ne prvek na každý řádek** (#252): plocha na tažení je
    /// souvislá, takže ji nemá smysl skládat z šedesáti dílů, které pak líný seznam při každém
    /// posunu znovu umisťuje.
    @ViewBuilder private var gutter: some View {
        if let span = geometry.span {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: geometry.gutterWidth, height: span.height)
                    .contentShape(.rect)
                    .offset(y: span.top)
                    .gesture(rangeGesture)
                pill
            }
        }
    }

    /// Pilulka na komentář — **nejvýš jedna**: normálně u řádku pod myší, při tažení na konci
    /// rozsahu (jinak by svítila na dvou místech a poskakovala).
    ///
    /// Sedí v prázdné ploše svého řádku a v ní `.leading` — tedy tam, kde ji držel `overlay` uvnitř
    /// gutteru řádku do #252. Odsadit ji přímo by znamenalo dopočítat svislé vystředění ručně, a to
    /// je druhé místo, které se s výškou řádku umí rozejít (viz #98). Řádek se tady navíc zalamuje,
    /// takže výšky nejsou stejné.
    @ViewBuilder private var pill: some View {
        if let spot = pilled {
            Color.clear
                .frame(width: geometry.gutterWidth, height: spot.frame.rect.height)
                .overlay(alignment: .leading) {
                    Image(systemName: symbol(of: spot.action))
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 18, height: max(spot.frame.rect.height - 2, 14))
                        .background(.tint, in: .rect(cornerRadius: 4))
                        .contentShape(.rect)
                        // `onTapGesture`, ne `Button`: `Button` si tažení bere pro sebe, takže by
                        // z pilulky nešlo roztáhnout rozsah (#157).
                        .onTapGesture {
                            performDraftAction(spot.action, NSEvent.modifierFlags.contains(.shift))
                        }
                        .help(spot.action.hint)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(spot.action.hint)
                }
                .offset(y: spot.frame.rect.minY)
        }
    }

    /// Pruh závažnosti na pravé hraně řádku, ke kterému se v okraji váže karta (#503) — 3 body,
    /// jak ho má návrh (`tr.mgn-crit td.code { border-right: 3px solid var(--crit) }`).
    ///
    /// **Jeden prvek na kartu, ne na řádek bloku** (#252): karet je v bloku obvykle nula nebo
    /// jedna, kdežto řádků šedesát — a prvek s prázdným obsahem se pořád umisťuje.
    @ViewBuilder private var marginStripes: some View {
        if !marginMarks.isEmpty {
            ZStack(alignment: .topTrailing) {
                ForEach(stripedFrames) { frame in
                    if let mark = self.mark(of: frame) {
                        Rectangle()
                            .fill(mark.severity.stripe)
                            .frame(width: 3, height: frame.rect.height)
                            .offset(y: frame.rect.minY)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Řádky bloku, na kterých pruh je. Prázdné, dokud okraj nikoho nezajímá.
    private var stripedFrames: [DiffBlockLineFrame] {
        guard !marginMarks.isEmpty else { return [] }
        return frames.filter { mark(of: $0) != nil }
    }

    private func mark(of frame: DiffBlockLineFrame) -> DiffMarginMark? {
        guard let number = Policy.number(of: frame.line, on: .right) else { return nil }
        return marginMarks[number]
    }

    private var geometry: DiffGutterGeometry { .unified(frames: frames) }

    /// Kde svítí pilulka a co udělá.
    private var pilled: (frame: DiffBlockLineFrame, action: LineDraftAction)? {
        if let dragEnd {
            for frame in frames where anchor(of: frame)?.end == dragEnd {
                if let action = draft.action(for: frame.line) { return (frame, action) }
            }
            return nil
        }
        guard let hovered,
              let frame = frames.first(where: { $0.index == hovered }),
              let action = draft.action(for: frame.line)
        else { return nil }
        return (frame, action)
    }

    /// Zapíše plochy řádků do krabice — **naráz za celý blok** (#252).
    ///
    /// **Hlásí se každý řádek, ne jen ten, na který se dá komentovat** (#152): z těchže ploch se
    /// počítá, kam skok posadí cílový řádek, a ten může být i v rozbaleném kontextu. Kotvu dostane
    /// jen řádek, přes který se dá táhnout rozsah.
    /// - Parameter measured: rámečky, které textové view **právě** ohlásilo. `nil` = vzít ty ze
    ///   stavu; hodnota se předává jen z `noteFrames`, kde ještě ve stavu nejsou (viz tam).
    private func noteRows(measured: [DiffBlockLineFrame]? = nil) {
        let frames = measured ?? self.frames
        noteMargin(frames)
        guard let box = rangeDrag.box else { return }
        let gutter = DiffGutterGeometry.unified(frames: frames)
        let origin = placement.rect.origin
        let rows = frames.map { frame in
            DiffRowFrames.Entry(
                id: id(of: frame),
                rect: gutter.rect(of: frame, on: nil).offsetBy(dx: origin.x, dy: origin.y),
                anchor: anchor(of: frame)
            )
        }
        box.frames.note(rows, covering: placement.rect, of: box.subject, block: blockID)
    }

    /// Ohlásí okraji, kde leží řádky s kartou (#503).
    ///
    /// **Hlásí se předfiltr, ne všechny řádky** — na rozdíl od `DiffRowFrames`, ze kterých se
    /// počítá i skok, a tak se hlásí každý. Sem jde jedině to, co okraj doopravdy kreslí, protože
    /// je to krabice, ze které se překresluje.
    ///
    /// **Nezměřený blok nehlásí nic, ani prázdno** — a je to tatáž lekce jako u `DiffRowFrames`
    /// („prázdná plocha se ignoruje“, #252), jen o jednu krabici vedle. Prázdné hlášení znamená
    /// *změřeno a žádná karta tu není*, takže se z krabice sundá stará poloha; kdyby ho poslal
    /// i blok, který se ještě nerozložil, přepsal by tím platnou polohu na nic — a to se děje
    /// pokaždé, když se blok přestaví (změřeno: karty pak stály na sobě u horní hrany okraje).
    private func noteMargin(_ frames: [DiffBlockLineFrame]) {
        // **Nezměřený blok nehlásí nic** — a to platí i na jeho *počátek*, ne jen na rámečky
        // řádků. `noteFrames` se ozývá z textového view, tedy **dřív** než `onGeometryChange`
        // nasadí `placement.rect`; poloha složená v tom okamžiku nese `origin.y == 0`, takže je
        // v souřadnicích **bloku**, ne obsahu — karta by stála o celý soubor výš. Změřeno při
        // slévání s #501, kde se to pořadí projevilo: hlášená poloha byla 98 b místo 137 b,
        // tedy přesně odsazení bloku. Na geometrické cestě se `noteRows()` volá hned za zápisem
        // rectu, takže se tím o žádné hlášení nepřijde — jen se to pozdější vezme.
        guard let marginAnchors, !frames.isEmpty, placement.rect != .zero else { return }
        let origin = placement.rect.origin
        var found: [String: DiffMarginSpot] = [:]
        for frame in frames {
            guard let mark = mark(of: frame) else { continue }
            found[mark.id] = DiffMarginSpot(
                top: origin.y + frame.rect.minY,
                height: frame.rect.height
            )
        }
        marginAnchors.note(found, from: blockID)
    }

    private func anchor(of frame: DiffBlockLineFrame) -> DraftAnchor? {
        guard case .comment(let anchor) = draft.action(for: frame.line) else { return nil }
        return anchor
    }

    private func id(of frame: DiffBlockLineFrame) -> String {
        "\(blockID)l\(frame.index)"
    }

    /// Tažení rozsahu. Gesto je **jedno na blok**, ne na každý řádek (#252), takže se řádek, na
    /// kterém tažení začalo, hledá podle `startLocation` — v souřadnicích obsahu, ze kterých se
    /// poloha bloku odečte.
    private var rangeGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(DiffView.contentSpace))
            .onChanged { value in
                let y = value.startLocation.y - placement.rect.minY
                guard let frame = geometry.line(atY: y), let anchor = anchor(of: frame) else { return }
                rangeDrag.move(anchor, rangeDrag.box?.frames.anchor(at: value.location, on: nil))
            }
            .onEnded { _ in rangeDrag.end() }
    }

    /// Které řádky bloku leží v dané množině buněk. Blok kreslí pruhy podle **pořadí v bloku**,
    /// protože o číslech řádků nic neví — přeložit se to musí tady.
    private func rows(in cells: Set<DraftAnchor.Endpoint>) -> Set<Int> {
        guard !cells.isEmpty else { return [] }
        var result: Set<Int> = []
        for (index, line) in block.lines.enumerated() {
            for side in [DiffSide.right, .left] {
                guard let number = Policy.number(of: line, on: side) else { continue }
                if cells.contains(DraftAnchor.Endpoint(line: number, side: side)) { result.insert(index) }
            }
        }
        return result
    }

    /// Kopírování se vztahuje k řádku **pod myší** — pravé kliknutí platí pro to, na co se kliklo.
    private var copyTargets: [DiffCopyTarget] {
        guard let index = hovered, block.lines.indices.contains(index) else { return [] }
        return copy.targets(block.lines[index])
    }

    private var selectText: (() -> Void)? {
        guard let index = hovered, block.lines.indices.contains(index) else { return nil }
        return copy.selectableText(block.lines[index]).map { text in { copy.showText(text) } }
    }

    private func symbol(of action: LineDraftAction) -> String {
        action.isNote ? "text.badge.plus" : "plus.bubble.fill"
    }
}
