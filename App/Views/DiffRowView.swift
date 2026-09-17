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
    /// Rozbalení bubliny nálezu (#185). Taky ze store: buňka líného seznamu si vlastní stav
    /// při odscrollování zahodí.
    var findingDisclosure = FindingDisclosureActions()
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
    /// Kopírování kódu do schránky (#157) — pravým kliknutím, takže **komentář nezakládá**.
    var copy = DiffCopyActions()
    /// Cesta souboru, do kterého řádek patří (#152). Bloky z ní poznají, jestli jim patří
    /// **aktuální** výskyt hledání; jinak se nikde nekreslí.
    var filePath: String = ""
    /// Řádky s kartou v okraji vpravo (#503), klíčované novým číslem řádku. Skládá je `Policy`
    /// jednou za soubor, ne za řádek.
    var marginMarks: [Int: DiffMarginMark] = [:]
    /// Kam bloky hlásí, kde ty řádky leží. `nil` = okraj se nekreslí.
    var marginAnchors: DiffMarginAnchors?

    var body: some View {
        let _ = RenderDiagnostics.pass(Self.self)
        switch row {
        case .hunk(_, let hunk):
            hunkHeader(hunk)
                .copyMenu(copy.hunkTargets(hunk), selectText: copy.selectableHunkText(hunk).map { text in
                    { copy.showText(text) }
                })
        case .block(let id, let block):
            DiffBlockRowView(
                block: block,
                language: language,
                draft: draft,
                performDraftAction: perform,
                commentRangeCells: commentRangeCells,
                draggedCells: draggedCells,
                dragEnd: dragEnd,
                rangeDrag: rangeDrag,
                blockID: id,
                copy: copy,
                filePath: filePath,
                marginMarks: marginMarks,
                marginAnchors: marginAnchors
            )
        case .pairBlock(let id, let pair):
            pairBlock(id, pair)
        case .line(let id, let line):
            // **Z diffu sem dojde jedině poznámka `git`u ve split pohledu** (#446), tedy
            // `\ No newline at end of file`. `DiffRow.paired(_:)` ji nechává celou (není to obsah
            // souboru, takže nemá stranu, viz `DiffPairing`) a `blockedPairs(_:)` slévá jen
            // dvojice; v pohledu pod sebou ji `blocked(_:)` naopak sebere do bloku jako každý
            // jiný řádek. Živá tahle větev tedy je — na rozdíl od té pod ní —, ale jen na tomhle
            // jednom případu; obojí tvrdí `DiffRenderedRowsTests`.
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
            .copyMenu(copy.targets(line), selectText: selectText(of: line))
        case .pair(let id, let left, let right):
            // **Sem se dvojice z diffu nedostane** (#446): `DiffView` sype do seznamu vždycky
            // výsledek `blockedPairs(_:)`, a ta slije i dvojici osamocenou mezi bublinami.
            // Do #446 tu viselo vlastní `DiffPairView` — sto řádků paralelního kreslení, které se
            // od #157 nespustilo ani jednou. Zbylo po něm hlavně to, že se `DiffRowView` četl jako
            // čtyři větve pro obsah souboru, ze kterých byla jedna kulisa.
            //
            // Prázdno tu ale být nesmí — tichá díra v diffu je horší než řádek navíc —, takže se
            // dvojice nakreslí **týmž blokem** jako každá jiná. Jedna cesta ke kreslení dvojice,
            // ne druhá vedle ní.
            pairBlock(id, DiffPairBlock(left: [left], right: [right], ids: [id]))
        case .annotation(_, let annotation):
            // Věta *proč* pod souřadnicí hunku (#525). **Bez kopírovacího menu**: hunk se kopíruje
            // z hlavičky nad ní a věta o něm jeho obsah není.
            DiffAnnotationRowView(annotation: annotation)
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
                indent: indent,
                disclosure: findingDisclosure.state(group),
                toggle: { findingDisclosure.toggle(group) }
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

    /// Blok dvou sloupců i s tím, co na řádcích visí. **Jediné místo, kde se v tomhle view kreslí
    /// dvojice** — hotový `.pairBlock` i osamocená `.pair`, která se sem nemá jak dostat (#446).
    private func pairBlock(_ id: String, _ block: DiffPairBlock) -> some View {
        DiffPairBlockRowView(
            block: block,
            language: language,
            draft: draft,
            performDraftAction: perform,
            commentRangeCells: commentRangeCells,
            draggedCells: draggedCells,
            dragEnd: dragEnd,
            rangeDrag: rangeDrag,
            blockID: id,
            copy: copy,
            filePath: filePath,
            marginMarks: marginMarks,
            marginAnchors: marginAnchors
        )
    }

    /// Akce, která otevře hunk řádku jako text k vybírání (#157). `nil` = není z čeho ho složit,
    /// položka se v menu nekreslí.
    private func selectText(of line: DiffLine) -> (() -> Void)? {
        copy.selectableText(line).map { text in { copy.showText(text) } }
    }

    /// Leží řádek přes celou šířku uvnitř rozsahu? Stačí, když padne do rozsahu na **kterékoli**
    /// straně — sloupec je jediný, takže se rozsah nemá o co dělit.
    ///
    /// **Strana se sem od #446 nepředává**: jedinou stranu měly buňky dvojice, a ty odsud kreslí
    /// blok (`DiffPairBlockRowView`), který si rozsahy vybírá sám. Volitelný parametr, který
    /// nikdo nevyplní, je kulisa téhož druhu jako `DiffPairView` sám.
    private func covers(_ cells: Set<DraftAnchor.Endpoint>, _ line: DiffLine) -> Bool {
        guard !cells.isEmpty else { return false }
        return [DiffSide.right, .left].contains { side in
            guard let number = Policy.number(of: line, on: side) else { return false }
            return cells.contains(DraftAnchor.Endpoint(line: number, side: side))
        }
    }

    /// Moje rozdělané komentáře k jednomu řádku diffu.
    ///
    /// Ve split pohledu **vedle sebe ve svých polovinách**: komentář je vázaný na stranu, takže
    /// pruh přes oba sloupce by tvrdil, že patří k obojímu — a u komentáře k odebranému řádku
    /// je to matoucí nejvíc. Rozdělení šířky je **stejné jako v bloku dvojic**
    /// (`DiffGutterGeometry.rightColumnX(inBlockOfWidth:)` — dvě poloviny a mezi nimi 1 pt na
    /// dělicí čáru), takže komentář končí tam, kde končí buňka jeho řádku.
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
                // Nabídka návrhu (#528) se počítá **jen tam, kde bublina doopravdy je** — je to
                // průchod hunky, takže řádkům diffu se nedává vůbec.
                suggestion: draft.suggestion?(comment.anchor),
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
        DiffLineView.contentInset(for: layout)
    }

    /// Odsazení **komentáře**, který ve split pohledu bydlí v polovině řádku. Do sloupce
    /// s obsahem se tam nezarovnává: na půlce šířky je 52 pt odsazení pro parádu drahé
    /// a editor, do kterého se píše, potřebuje místo. Svislý pruh bubliny říká, kam patří,
    /// líp než odsazení.
    private var commentIndent: Double {
        layout == .split ? 16 : DiffLineView.contentInset(for: layout)
    }

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
