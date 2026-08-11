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

    @Environment(\.colorScheme) private var colorScheme
    /// Rámečky řádků, které ohlásilo textové view. `@State`, protože se z nich staví overlay.
    @State private var frames: [DiffBlockLineFrame] = []
    /// Řádek pod myší — jen jeho pilulka je vidět, jako dosud u `DiffLineView`.
    @State private var hovered: Int?
    /// Poloha bloku v prostoru obsahu, **mimo observable stav** — viz `DiffBlockPlacement` (#252).
    @State private var placement = DiffBlockPlacement()

    var body: some View {
        DiffCodeBlockView(
            block: block,
            language: language,
            colorScheme: colorScheme,
            commentRangeLines: rows(in: commentRangeCells),
            draggedLines: rows(in: draggedCells),
            noteFrames: { frames = $0; noteRows() }
        )
        // Plocha na tažení a pilulka leží nad textem, pozicované podle rámečků řádků.
        .overlay(alignment: .topLeading) { gutter }
        // Rámeček **celého bloku** v souřadnicích obsahu diffu — jeden na blok, ne jeden na řádek
        // (#252). Plochy řádků se z něj dopočítají aritmetikou (`DiffGutterGeometry`).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DiffView.contentSpace)) } action: { rect in
            placement.rect = rect
            noteRows()
        }
        // **Rozhoduje jen `y`, ne celý rámeček řádku.** Rámečky jsou rámečky *textu*, takže začínají
        // až za sloupcem s čísly — a `contains(point)` znamenalo, že jak myš zamířila na pilulku,
        // hover zhasl a pilulka zmizela pod rukou. Nedalo se na ni kliknout (nahlášené při zkoušení
        // #157); je to tatáž past jako u #98, kde tlačítko vyčnívalo do dalšího řádku.
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hovered = geometry.line(atY: point.y)?.index
            case .ended: hovered = nil
            }
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

    /// Zapíše plochy řádků do krabice pro tažení — **naráz za celý blok** (#252).
    private func noteRows() {
        guard let box = rangeDrag.frames else { return }
        let gutter = geometry
        let origin = placement.rect.origin
        let rows = frames.compactMap { frame -> DiffRowFrames.Entry? in
            guard let anchor = anchor(of: frame) else { return nil }
            return DiffRowFrames.Entry(
                id: id(of: frame),
                rect: gutter.rect(of: frame, on: nil).offsetBy(dx: origin.x, dy: origin.y),
                anchor: anchor
            )
        }
        box.note(rows, covering: placement.rect)
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
                rangeDrag.move(anchor, rangeDrag.frames?.anchor(at: value.location, on: nil))
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
