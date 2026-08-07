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

    @Environment(\.colorScheme) private var colorScheme
    @State private var frames: [DiffBlockLineFrame] = []
    /// Řádek a strana pod myší — pilulka svítí jen tam.
    @State private var hovered: (index: Int, side: DiffSide)?

    var body: some View {
        DiffPairBlockView(
            block: block,
            language: language,
            colorScheme: colorScheme,
            leftRangeLines: rows(in: commentRangeCells, on: .left),
            rightRangeLines: rows(in: commentRangeCells, on: .right),
            leftDraggedLines: rows(in: draggedCells, on: .left),
            rightDraggedLines: rows(in: draggedCells, on: .right),
            noteFrames: { frames = $0 }
        )
        .overlay(alignment: .topLeading) { gutters }
        // Strana se pozná z `x`: která polovina, ta strana. Svisle rozhoduje jen `y`, aby hover
        // držel i nad sloupcem s čísly a nad pilulkou (jinak zmizí pod rukou, viz #157 a #98).
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hovered = frames
                    .first { point.y >= $0.rect.minY && point.y < $0.rect.maxY }
                    .map { (index: $0.index, side: side(at: point.x, in: $0)) }
            case .ended:
                hovered = nil
            }
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

    /// Sloupce s čísly obou stran — plocha na tažení a v ní pilulka.
    private var gutters: some View {
        ForEach(frames) { frame in
            HStack(spacing: 0) {
                gutter(for: frame, on: .left)
                Spacer(minLength: 0)
                gutter(for: frame, on: .right)
                Spacer(minLength: 0)
            }
            .frame(height: frame.rect.height)
            .offset(y: frame.rect.minY)
        }
    }

    private func gutter(for frame: DiffBlockLineFrame, on side: DiffSide) -> some View {
        Color.clear
            .frame(width: DiffLineView.contentInset(for: .split), height: frame.rect.height)
            .contentShape(.rect)
            .overlay(alignment: .leading) { pill(for: frame, on: side) }
            .gesture(rangeGesture(for: frame, on: side))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DiffView.contentSpace)) } action: { rect in
                rangeDrag.frames?.note(rect, id: id(of: frame, on: side), anchor: anchor(of: frame, on: side))
            }
    }

    @ViewBuilder private func pill(for frame: DiffBlockLineFrame, on side: DiffSide) -> some View {
        if let action = action(of: frame, on: side), shows(frame, on: side) {
            Image(systemName: action.isNote ? "text.badge.plus" : "plus.bubble.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 18, height: max(frame.rect.height - 2, 14))
                .background(.tint, in: .rect(cornerRadius: 4))
                .contentShape(.rect)
                .onTapGesture {
                    performDraftAction(action, NSEvent.modifierFlags.contains(.shift))
                }
                .help(action.hint)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(action.hint)
        }
    }

    // MARK: - Odvozené

    /// Která strana leží pod tímhle `x`. Půlka šířky je hranice, stejně jako u kreslení sloupců.
    private func side(at x: Double, in frame: DiffBlockLineFrame) -> DiffSide {
        x < frame.rect.width / 2 ? .left : .right
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

    private func shows(_ frame: DiffBlockLineFrame, on side: DiffSide) -> Bool {
        if let dragEnd {
            anchor(of: frame, on: side)?.end == dragEnd
        } else {
            hovered?.index == frame.index && hovered?.side == side
        }
    }

    private func id(of frame: DiffBlockLineFrame, on side: DiffSide) -> String {
        "\(blockID)l\(frame.index)|\(side.rawValue)"
    }

    private func rangeGesture(for frame: DiffBlockLineFrame, on side: DiffSide) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(DiffView.contentSpace))
            .onChanged { value in
                guard let anchor = anchor(of: frame, on: side) else { return }
                // Hledá se **jen ve svém sloupci**: tažení, které začalo vpravo, nemá skákat vlevo.
                rangeDrag.move(anchor, rangeDrag.frames?.anchor(at: value.location, on: side))
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
