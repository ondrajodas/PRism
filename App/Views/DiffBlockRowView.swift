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

    var body: some View {
        DiffCodeBlockView(
            block: block,
            language: language,
            colorScheme: colorScheme,
            commentRangeLines: rows(in: commentRangeCells),
            draggedLines: rows(in: draggedCells),
            noteFrames: { frames = $0 }
        )
        // Pilulky a plochy na tažení leží nad textem, každá u svého řádku.
        .overlay(alignment: .topLeading) { gutter }
        // **Rozhoduje jen `y`, ne celý rámeček řádku.** Rámečky jsou rámečky *textu*, takže začínají
        // až za sloupcem s čísly — a `contains(point)` znamenalo, že jak myš zamířila na pilulku,
        // hover zhasl a pilulka zmizela pod rukou. Nedalo se na ni kliknout (nahlášené při zkoušení
        // #157); je to tatáž past jako u #98, kde tlačítko vyčnívalo do dalšího řádku.
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hovered = frames.first { row(at: point.y, in: $0) }?.index
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
    /// Kreslí se **absolutně podle rámečků řádků**, ne ve `VStack`u: řádky mají různou výšku
    /// (dlouhý kód se zalomí) a jediný zdroj pravdy o jejich poloze je layout textového view.
    private var gutter: some View {
        ForEach(frames) { frame in
            Color.clear
                .frame(width: DiffLineView.contentInset(for: .unified), height: frame.rect.height)
                .contentShape(.rect)
                .overlay(alignment: .leading) { pill(for: frame) }
                .offset(y: frame.rect.minY)
                .gesture(rangeGesture(for: frame))
                // Rámeček řádku pro tažení — v souřadnicích **obsahu** diffu, jako u `DiffLineView`.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DiffView.contentSpace)) } action: { rect in
                    rangeDrag.frames?.note(rect, id: id(of: frame), anchor: anchor(of: frame))
                }
        }
    }

    @ViewBuilder private func pill(for frame: DiffBlockLineFrame) -> some View {
        if let action = draft.action(for: frame.line), shows(frame) {
            Image(systemName: symbol(of: action))
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 18, height: max(frame.rect.height - 2, 14))
                .background(.tint, in: .rect(cornerRadius: 4))
                .contentShape(.rect)
                // `onTapGesture`, ne `Button`: `Button` si tažení bere pro sebe, takže by z pilulky
                // nešlo roztáhnout rozsah (#157).
                .onTapGesture {
                    performDraftAction(action, NSEvent.modifierFlags.contains(.shift))
                }
                .help(action.hint)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(action.hint)
        }
    }

    /// Leží myš ve svislém rozsahu tohohle řádku? Vodorovně se neptáme schválně — pilulka i čísla
    /// stojí vlevo od textu a musí na myš reagovat taky.
    private func row(at y: Double, in frame: DiffBlockLineFrame) -> Bool {
        y >= frame.rect.minY && y < frame.rect.maxY
    }

    /// Kdy je pilulka vidět: normálně nad řádkem pod myší, **při tažení jen na konci rozsahu** —
    /// jinak by svítila na dvou místech a poskakovala.
    private func shows(_ frame: DiffBlockLineFrame) -> Bool {
        if let dragEnd { anchor(of: frame)?.end == dragEnd } else { hovered == frame.index }
    }

    private func anchor(of frame: DiffBlockLineFrame) -> DraftAnchor? {
        guard case .comment(let anchor) = draft.action(for: frame.line) else { return nil }
        return anchor
    }

    private func id(of frame: DiffBlockLineFrame) -> String {
        "\(blockID)l\(frame.index)"
    }

    private func rangeGesture(for frame: DiffBlockLineFrame) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(DiffView.contentSpace))
            .onChanged { value in
                guard let anchor = anchor(of: frame) else { return }
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
