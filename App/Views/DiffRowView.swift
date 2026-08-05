import SwiftUI

/// Vykreslí jeden řádek diffu — hlavičku hunku, řádek souboru, rozbalovací řádek nebo
/// poznámku.
struct DiffRowView: View {
    let row: DiffRow
    /// Jazyk souboru kvůli obarvení kódu. `nil` u souboru, kterému nerozumíme.
    var language: Language?
    /// Pohled na diff. Řádky samy ho poznají z toho, že jsou dvojice; bubliny ne — a přitom
    /// se podle něj kreslí jinak (odsazení, a u komentáře i půlka, ve které visí).
    var layout: DiffLayout = .unified
    /// Načítá se právě obsah souboru, do kterého řádek patří?
    var isLoadingContent = false
    /// Proč se obsah souboru nepodařilo načíst.
    var contentFailure: String?
    var reveal: (ClosedRange<Int>) -> Void = { _ in }
    /// Místo, na které se právě skočilo z tabulky.
    var highlighted: FindingHighlight?
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    /// Odmítnutí a vrácení nálezu (#113). Rozhoduje store, ne tenhle view — ze stejného
    /// důvodu jako u vláken.
    var findingActions: FindingActions?
    /// Přihlášený uživatel — kvůli odlišení mých komentářů ve vláknech.
    var viewer: String = ""
    /// Co se dá dělat s vlákny. Rozhoduje store, ne tenhle view: buňka líného seznamu se při
    /// odscrollování zahodí, takže vlastní `@State` by zapomněl rozbalení i rozepsanou odpověď.
    var threads = ThreadActions()
    /// Akce rozdělaného review svázané s tímhle souborem — cestu si doplní samy.
    var draft = FileDraftActions()
    /// Buňky, které leží uvnitř rozsahu některého mého komentáře (#110) — **řádek a strana**,
    /// protože rozsah v pravém sloupci nemá zvýrazňovat levý. Skládá je volající jednou za
    /// soubor, ne řádek po řádku: hledání konců rozsahu jde přes všechny hunky.
    var commentRangeCells: Set<DraftAnchor.Endpoint> = []
    /// Totéž pro rozsah, který se právě táhne — svítí výrazněji než hotový komentář.
    var draggedCells: Set<DraftAnchor.Endpoint> = []
    /// Konec taženého rozsahu; při tažení je tlačítko vidět jen tam, takže jde s myší.
    var dragEnd: DraftAnchor.Endpoint?
    /// Tažení přes řádky, kterým se vybírá rozsah komentáře (#110).
    var rangeDrag = RangeDragActions()

    var body: some View {
        switch row {
        case .hunk(_, let hunk):
            hunkHeader(hunk)
        case .line(let id, let line):
            DiffLineView(
                line: line,
                language: language,
                draftAction: draft.action(for: line),
                performDraftAction: perform,
                isInCommentRange: covers(commentRangeCells, line),
                isInDraggedRange: covers(draggedCells, line),
                dragEnd: dragEnd,
                rangeDrag: rangeDrag,
                dragID: id
            )
        case .pair(let id, let left, let right):
            DiffPairView(
                left: left,
                right: right,
                language: language,
                draft: draft,
                performDraftAction: perform,
                leftInRange: left.map { covers(commentRangeCells, $0, on: .left) } ?? false,
                rightInRange: right.map { covers(commentRangeCells, $0, on: .right) } ?? false,
                leftInDrag: left.map { covers(draggedCells, $0, on: .left) } ?? false,
                rightInDrag: right.map { covers(draggedCells, $0, on: .right) } ?? false,
                dragEnd: dragEnd,
                rangeDrag: rangeDrag,
                dragID: id
            )
        case .expander(_, let expander):
            DiffExpanderView(
                expander: expander,
                isLoading: isLoadingContent,
                failure: contentFailure,
                reveal: reveal
            )
        case .finding(_, let group, let anchored):
            FindingBubbleView(
                group: group,
                blockingCategories: blockingCategories,
                isAnchored: anchored,
                reveal: reveal,
                isHighlighted: highlighted?.matches(group) ?? false,
                draft: draft,
                actions: findingActions,
                indent: indent
            )
        case .thread(_, let thread):
            ThreadBubbleView(
                thread: thread,
                viewer: viewer,
                isExpanded: threads.isExpanded(thread),
                toggle: { threads.toggle(thread) },
                indent: indent,
                actions: threads
            )
        case .draftComments(_, let left, let right):
            draftComments(left: left, right: right)
        case .note(_, let text):
            note(text)
        }
    }

    /// Leží buňka (řádek na dané straně) uvnitř rozsahu? V pohledu pod sebou je sloupec jediný,
    /// takže stačí, když řádek padne do rozsahu na **kterékoli** straně.
    private func covers(_ cells: Set<DraftAnchor.Endpoint>, _ line: DiffLine, on side: DiffSide? = nil) -> Bool {
        guard !cells.isEmpty else { return false }
        let sides: [DiffSide] = side.map { [$0] } ?? [.right, .left]
        return sides.contains { candidate in
            guard let number = Policy.number(of: line, on: candidate) else { return false }
            return cells.contains(DraftAnchor.Endpoint(line: number, side: candidate))
        }
    }

    /// Moje rozdělané komentáře k jednomu řádku diffu.
    ///
    /// Ve split pohledu **vedle sebe ve svých polovinách**: komentář je vázaný na stranu, takže
    /// pruh přes oba sloupce by tvrdil, že patří k obojímu — a u komentáře k odebranému řádku
    /// je to matoucí nejvíc. Rozdělení šířky je **stejné jako v `DiffPairView`** (dvě poloviny
    /// a mezi nimi 1 pt na dělicí čáru), takže komentář končí tam, kde končí buňka jeho řádku.
    ///
    /// V pohledu pod sebou pod sebou přes celou šířku, jako dosud. Nález ani cizí vlákno se na
    /// stranu nevážou (nález stranu nemá vůbec) a nesou delší text, takže zůstávají přes celou
    /// šířku v obou pohledech.
    @ViewBuilder private func draftComments(
        left: [ReviewDraftComment],
        right: [ReviewDraftComment]
    ) -> some View {
        if layout == .split {
            HStack(alignment: .top, spacing: 0) {
                column(left)
                Color.clear.frame(width: 1)
                column(right)
            }
        } else {
            VStack(spacing: 0) { bubbles(left + right) }
        }
    }

    /// Jedna polovina se svými komentáři. Prázdná strana si šířku vzít **musí**, jinak by se
    /// druhá rozlila přes celý řádek a přestala ukazovat, ke které straně patří.
    @ViewBuilder private func column(_ comments: [ReviewDraftComment]) -> some View {
        if comments.isEmpty {
            Color.clear.frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) { bubbles(comments) }
                .frame(maxWidth: .infinity)
        }
    }

    /// Identitu nese `id` komentáře, ne pořadí — na tom stojí, že si editor udrží rozepsaný
    /// text mezi překreslením i po vyjmutí sousedního komentáře.
    private func bubbles(_ comments: [ReviewDraftComment]) -> some View {
        ForEach(comments) { comment in
            DraftCommentBubbleView(
                comment: comment,
                indent: commentIndent,
                update: { draft.updateComment(comment.id, $0) },
                remove: { draft.removeComment(comment.id) }
            )
        }
    }

    /// Odsazení bubliny do sloupce s obsahem.
    ///
    /// Ve split pohledu je v buňce **jedno** číslo řádku místo dvou, takže se odsazení o ten
    /// sloupec zkrátí — jinak by bublina začínala až uvnitř kódu.
    private var indent: Double {
        layout == .split ? Self.bubbleIndent - DiffLineView.numberColumn : Self.bubbleIndent
    }

    /// Odsazení **komentáře**, který ve split pohledu bydlí v polovině řádku. Do sloupce
    /// s obsahem se tam nezarovnává: na půlce šířky je 52 pt odsazení pro parádu drahé
    /// a editor, do kterého se píše, potřebuje místo. Svislý pruh bubliny říká, kam patří,
    /// líp než odsazení.
    private var commentIndent: Double {
        layout == .split ? 16 : Self.bubbleIndent
    }

    /// Odsazení bubliny v pohledu pod sebou — stejná hodnota, jakou mají bubliny ve výchozím
    /// stavu, jen na jednom místě pro všechny tři druhy.
    private static let bubbleIndent = 104.0

    /// `extendsRange` je ⇧ klik (#110). Poznámka do těla review rozsah nezná — je to odkaz na
    /// jeden řádek, který v diffu není.
    private func perform(_ action: LineDraftAction, extendsRange: Bool) {
        switch action {
        case .comment(let anchor): extendsRange ? draft.extend(anchor) : draft.comment(anchor)
        case .note(let line): draft.note(line)
        }
    }

    private func hunkHeader(_ hunk: DiffHunk) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: hunk.header)
            if !hunk.heading.isEmpty {
                Text(verbatim: hunk.heading)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
