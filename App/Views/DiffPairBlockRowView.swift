import SwiftUI

/// Blok dvou sloupců kódu v pohledu vedle sebe i s tím, co na řádcích visí (#157).
///
/// Sestra `DiffBlockRowView` pro split pohled: text kreslí `DiffPairBlockView` (dva `NSTextView`),
/// tenhle view k němu přidává **pilulku na komentář** a **tažení rozsahu** — po jedné na každou
/// stranu, protože komentář je vázaný na stranu diffu.
struct DiffPairBlockRowView: View {
    let block: DiffPairBlock
    var language: Language?
    var draft = FileDraftActions()
    var performDraftAction: (LineDraftAction, Bool) -> Void = { _, _ in }
    var commentRangeCells: Set<DraftAnchor.Endpoint> = []
    var draggedCells: Set<DraftAnchor.Endpoint> = []
    var dragEnd: DraftAnchor.Endpoint?
    var rangeDrag = RangeDragActions()
    var blockID: String = ""
    var copy = DiffCopyActions()
    /// Cesta souboru, ve kterém blok leží (#152) — viz `DiffBlockRowView.filePath`.
    var filePath: String = ""

    @Environment(\.colorScheme) private var colorScheme
    /// Hledání v tomhle diffu (#152) — prostředím, ze stejného důvodu jako u pohledu pod sebou.
    @Environment(DiffSearchState.self) private var search: DiffSearchState?
    @State private var frames: [DiffBlockLineFrame] = []
    /// Řádek a strana pod myší — pilulka svítí jen tam.
    ///
    /// **Je to `HoveredCell`, ne tuple** (#358): tuple se nedá porovnat se stávající hodnotou, takže
    /// se do tohohle stavu zapisovalo při každém hover updatu a okno se zacyklilo.
    @State private var hovered: HoveredCell?
    /// Poloha bloku v prostoru obsahu diffu. Drží se **mimo observable stav** (`@State` na třídě,
    /// jejíž pole nikdo nesleduje), ze stejného důvodu jako `DiffRowFrames`: líný seznam si obsah
    /// přeměřuje průběžně, takže se při scrollování mění — a přestavovat kvůli tomu blok by
    /// znamenalo platit celý jeho layout při každém posunu.
    @State private var placement = DiffBlockPlacement()

    /// **Blok se nasazuje jen v pásu kolem výřezu** (#469) — viz `DiffBlockSlot`. Ve split pohledu
    /// o to víc: jedna dvojice jsou **dva** `NSTextView`.
    var body: some View {
        DiffBlockSlot { mounted }
    }

    private var mounted: some View {
        DiffPairBlockView(
            block: block,
            language: language,
            colorScheme: colorScheme,
            search: searchHighlight,
            leftRangeLines: rows(in: commentRangeCells, on: .left),
            rightRangeLines: rows(in: commentRangeCells, on: .right),
            leftDraggedLines: rows(in: draggedCells, on: .left),
            rightDraggedLines: rows(in: draggedCells, on: .right),
            noteFrames: { frames = $0; noteRows() }
        )
        .overlay(alignment: .topLeading) { gutters }
        // Rámeček **celého bloku** v souřadnicích obsahu diffu — jeden na blok, ne jeden na řádek
        // a stranu (#252). Plochy řádků se z něj dopočítají aritmetikou (`DiffGutterGeometry`).
        //
        // Poloha se **nezapisuje do `@State`**: při scrollování se mění, protože líný seznam
        // přeměřuje obsah, takže by z toho byl layout bloku při každém posunu.
        .onGeometryChange(for: CGRect.self) {
            // Hák diagnostiky (#361): tahle closure běží **uvnitř** hořícího kola, kdežto tělo
            // se v něm nepřeloží ani jednou. Viz `GraphSite`.
            RenderDiagnostics.inGraph(.pairBlockGeometry)
            return $0.frame(in: .named(DiffView.contentSpace))
        } action: { rect in
            placement.rect = rect
            noteRows()
        }
        // Strana se pozná z `x`: která polovina, ta strana. Svisle rozhoduje jen `y`, aby hover
        // držel i nad sloupcem s čísly a nad pilulkou (jinak zmizí pod rukou, viz #157 a #98).
        //
        // **Zapisuje se jedině při změně** (#358). `onContinuousHover` dostane polohu i tehdy, když
        // se myš nehnula, takže bezpodmínečný zápis do `@State` zavíral kolo přes runloop observer
        // a okno spálilo 99 % CPU. Rozhodnutí drží `Policy.hoverChange(from:to:)` — tam je i důvod,
        // proč se hodnota vrací a neposílá se `inout`.
        .onContinuousHover { phase in
            let next: HoveredCell? = switch phase {
            case .active(let point): geometry.hoveredCell(at: point)
            case .ended: nil
            }
            if case .write(let cell) = Policy.hoverChange(from: hovered, to: next) { hovered = cell }
        }
        // Menu bezpodmínečně, ať se nemění struktura view a nezruší se výběr — viz `DiffBlockRowView`.
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

    /// Co se v tomhle bloku zvýrazní jako výsledek hledání (#152) — viz `DiffBlockRowView`.
    /// **Obě strany dostanou tentýž styl**: řádek se porovnává sám se sebou, takže odebraný výskyt
    /// svítí vlevo a přidaný vpravo, aniž by o stranách musel styl vědět.
    private var searchHighlight: DiffSearchHighlight {
        guard let search else { return .none }
        return Policy.searchHighlight(query: search.drawnQuery, current: search.currentHit, in: filePath)
    }

    /// Sloupce s čísly obou stran — plochy na tažení a nad nimi pilulka.
    ///
    /// **Dva prvky na blok a jedna pilulka, ne dva na každý řádek** (#252). Do té doby tu byl
    /// `ForEach` přes řádky a v něm `HStack` se dvěma `Spacer`y, takže šedesátiřádkový blok stál
    /// přes čtyři stovky prvků k umístění — a líný seznam je při scrollování umisťuje pořád dokola.
    /// Plocha na tažení je souvislá (`span`), pilulka je vidět nejvýš jedna, takže se počet prvků
    /// dá spočítat místo vyjednávat: je to tatáž úvaha jako u šířky v #220.
    @ViewBuilder private var gutters: some View {
        if let span = geometry.span {
            ZStack(alignment: .topLeading) {
                dragArea(on: .left, span: span)
                dragArea(on: .right, span: span)
                pill
            }
        }
    }

    /// Plocha na tažení rozsahu — celý sloupec s čísly jedné strany.
    private func dragArea(on side: DiffSide, span: (top: Double, height: Double)) -> some View {
        Color.clear
            .frame(width: geometry.gutterWidth, height: span.height)
            .contentShape(.rect)
            .offset(x: geometry.x(of: side), y: span.top)
            .gesture(rangeGesture(on: side))
    }

    /// Pilulka na komentář — **nejvýš jedna**: normálně u řádku pod myší, při tažení na konci
    /// rozsahu (jinak by svítila na dvou místech a poskakovala).
    ///
    /// Sedí v prázdné ploše svého řádku a v ní `.leading` — tedy tam, kde ji držel `overlay` uvnitř
    /// gutteru řádku do #252. Odsadit ji přímo by znamenalo dopočítat svislé vystředění ručně,
    /// a to je druhé místo, které se s výškou řádku umí rozejít (viz #98).
    @ViewBuilder private var pill: some View {
        if let spot = pilled {
            Color.clear
                .frame(width: geometry.gutterWidth, height: spot.frame.rect.height)
                .overlay(alignment: .leading) {
                    Image(systemName: spot.action.isNote ? "text.badge.plus" : "plus.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 18, height: max(spot.frame.rect.height - 2, 14))
                        .background(.tint, in: .rect(cornerRadius: 4))
                        .contentShape(.rect)
                        .onTapGesture {
                            performDraftAction(spot.action, NSEvent.modifierFlags.contains(.shift))
                        }
                        .help(spot.action.hint)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(spot.action.hint)
                }
                .offset(x: geometry.x(of: spot.side), y: spot.frame.rect.minY)
        }
    }

    // MARK: - Odvozené

    private var geometry: DiffGutterGeometry { .split(frames: frames) }

    /// Kde svítí pilulka a co udělá. Při tažení se hledá konec rozsahu, jinak řádek pod myší.
    private var pilled: (frame: DiffBlockLineFrame, side: DiffSide, action: LineDraftAction)? {
        if let dragEnd {
            for side in [DiffSide.left, .right] {
                for frame in frames where anchor(of: frame, on: side)?.end == dragEnd {
                    if let action = action(of: frame, on: side) { return (frame, side, action) }
                }
            }
            return nil
        }
        guard let hovered,
              let frame = frames.first(where: { $0.index == hovered.index }),
              let action = action(of: frame, on: hovered.side)
        else { return nil }
        return (frame, hovered.side, action)
    }

    /// Zapíše plochy řádků do krabice pro tažení — **naráz za celý blok** (#252). Volá se odkud
    /// přijde nová informace: z rámečků řádků i z polohy bloku, protože obojí je potřeba.
    private func noteRows() {
        guard let box = rangeDrag.box else { return }
        let gutter = geometry
        let origin = placement.rect.origin
        var rows: [DiffRowFrames.Entry] = []
        for side in [DiffSide.left, .right] {
            for frame in frames {
                guard let anchor = anchor(of: frame, on: side) else { continue }
                rows.append(DiffRowFrames.Entry(
                    id: id(of: frame, on: side),
                    rect: gutter.rect(of: frame, on: side).offsetBy(dx: origin.x, dy: origin.y),
                    anchor: anchor
                ))
            }
        }
        box.frames.note(rows, covering: placement.rect, of: box.subject)
    }

    private func line(of frame: DiffBlockLineFrame, on side: DiffSide) -> DiffLine? {
        let column = side == .left ? block.left : block.right
        return column.indices.contains(frame.index) ? column[frame.index] : nil
    }

    private func action(of frame: DiffBlockLineFrame, on side: DiffSide) -> LineDraftAction? {
        line(of: frame, on: side).flatMap { draft.action(for: $0, on: side) }
    }

    private func anchor(of frame: DiffBlockLineFrame, on side: DiffSide) -> DraftAnchor? {
        guard case .comment(let anchor) = action(of: frame, on: side) else { return nil }
        return anchor
    }

    private func id(of frame: DiffBlockLineFrame, on side: DiffSide) -> String {
        "\(blockID)l\(frame.index)|\(side.rawValue)"
    }

    /// Tažení rozsahu. Gesto je **jedno na sloupec**, ne na každý řádek (#252), takže se řádek,
    /// na kterém tažení začalo, hledá podle `startLocation` — v souřadnicích obsahu, ze kterých
    /// se poloha bloku odečte.
    private func rangeGesture(on side: DiffSide) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(DiffView.contentSpace))
            .onChanged { value in
                let y = value.startLocation.y - placement.rect.minY
                guard let frame = geometry.line(atY: y),
                      let anchor = anchor(of: frame, on: side)
                else { return }
                // Hledá se **jen ve svém sloupci**: tažení, které začalo vpravo, nemá skákat vlevo.
                rangeDrag.move(anchor, rangeDrag.box?.frames.anchor(at: value.location, on: side))
            }
            .onEnded { _ in rangeDrag.end() }
    }

    /// Které řádky sloupce leží v dané množině buněk.
    private func rows(in cells: Set<DraftAnchor.Endpoint>, on side: DiffSide) -> Set<Int> {
        guard !cells.isEmpty else { return [] }
        let column = side == .left ? block.left : block.right
        var result: Set<Int> = []
        for (index, line) in column.enumerated() {
            guard let line, let number = Policy.number(of: line, on: side) else { continue }
            if cells.contains(DraftAnchor.Endpoint(line: number, side: side)) { result.insert(index) }
        }
        return result
    }

    private var hoveredLine: DiffLine? {
        guard let hovered,
              let frame = frames.first(where: { $0.index == hovered.index })
        else { return nil }
        return line(of: frame, on: hovered.side)
    }

    private var copyTargets: [DiffCopyTarget] {
        hoveredLine.map { copy.targets($0) } ?? []
    }

    private var selectText: (() -> Void)? {
        guard let line = hoveredLine, let text = copy.selectableText(line) else { return nil }
        return { copy.showText(text) }
    }
}

extension LineDraftAction {
    var isNote: Bool {
        if case .note = self { true } else { false }
    }

    /// Nápověda u pilulky. Jedno místo pro oba pohledy — dvě formulace téhož se rozejdou.
    var hint: String {
        switch self {
        case .comment: "Přidat komentář k tomuhle řádku. ⇧ klik roztáhne rozsah od naposledy přidaného komentáře."
        case .note: "Řádek není v diffu, takže GitHub komentář k němu nepřijme. Přidá se do těla review jako odkaz na kód."
        }
    }
}
