import AppKit
import SwiftUI

/// Dva sloupce kódu vedle sebe jako **dva texty**, ve kterých jde vybírat přes řádky (#157).
///
/// **Sloupce musí zůstat zarovnané**, jinak přestane platit, že vlevo a vpravo je tentýž řádek
/// souboru — a to je celý smysl pohledu vedle sebe. Se zalamováním by jeden sloupec narostl
/// o vizuální řádek a druhý ne, takže se tady **nezalamuje**: každý řádek je jeden vizuální
/// a dlouhý kód se posouvá vodorovně (vlastní scroller na sloupec, jako na GitHubu).
///
/// V pohledu pod sebou je to obráceně — tam žádný protějšek není, takže se zalamuje jako dosud.
/// Rozhodnutí #157; do té doby se v pohledu vedle sebe zalamovalo taky, ale nebyla v něm selekce.
struct DiffPairBlockView: NSViewRepresentable {
    let block: DiffPairBlock
    var language: Language?
    let colorScheme: ColorScheme
    var leftRangeLines: Set<Int> = []
    var rightRangeLines: Set<Int> = []
    var leftDraggedLines: Set<Int> = []
    var rightDraggedLines: Set<Int> = []
    /// Rámečky řádků po layoutu — jeden na dvojici, protože sloupce jsou zarovnané.
    var noteFrames: ([DiffBlockLineFrame]) -> Void = { _ in }

    final class Coordinator {
        var frames: [DiffBlockLineFrame] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> DiffPairBlockContainer {
        DiffPairBlockContainer()
    }

    func updateNSView(_ container: DiffPairBlockContainer, context: Context) {
        let palette = SyntaxPalette.forScheme(colorScheme)
        let signature = DiffBlockSignature.of(
            blockHash: block.hashValue,
            language: language,
            colorScheme: colorScheme
        )

        container.show(
            block,
            language: language,
            palette: palette,
            signature: signature,
            gutter: DiffLineView.contentInset(for: .split)
        )
        container.apply(
            leftRange: leftRangeLines,
            rightRange: rightRangeLines,
            leftDragged: leftDraggedLines,
            rightDragged: rightDraggedLines
        )

        let frames = container.lineFrames()
        guard frames != context.coordinator.frames else { return }
        context.coordinator.frames = frames
        DispatchQueue.main.async { noteFrames(frames) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DiffPairBlockContainer, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0 else { return nil }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }
}

/// Kontejner, který drží dva textové sloupce a dělicí čáru mezi nimi.
///
/// Existuje proto, aby zarovnání sloupců řešil **AppKit v jednom layoutu**, ne SwiftUI ve dvou
/// nezávislých větvích: řádek vlevo a vpravo musí začínat na tomtéž `y`.
final class DiffPairBlockContainer: NSView, NSTextViewDelegate {
    private let left = DiffTextView.pairColumn()
    private let right = DiffTextView.pairColumn()
    /// Sloupce jsou v clip view, **jinak přetečou do druhé půlky**: textové view s neomezenou
    /// šířkou containeru si roztáhne vlastní rámec podle nejdelšího řádku a `frame`, který mu
    /// nastaví kontejner, ho nezastaví. Nahlášené při zkoušení #157 („levý sloupec je roztáhnutý
    /// do pravého“). Scroll view je tu tedy kvůli **ořezu**; vodorovný posun je vedlejší efekt,
    /// který se hodí, protože se ve split pohledu nezalamuje.
    private let leftScroll = NSScrollView()
    private let rightScroll = NSScrollView()
    private let separator = NSBox()
    private var rowHeight: Double = 0
    private var rows = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        separator.boxType = .separator
        for (scroll, column) in [(leftScroll, left), (rightScroll, right)] {
            scroll.documentView = column
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = true
            // Overlay scroller nezabírá výšku, takže sloupce zůstanou stejně vysoké.
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            addSubview(scroll)
            column.delegate = self
        }
        // Výběr v druhém sloupci se ruší **při stisknutí**, ne až při puštění: dvě modré selekce
        // vedle sebe po celou dobu tažení tvrdí, že je vybrané obojí. `textViewDidChangeSelection`
        // na to nestačí — chodí až s hotovým výběrem.
        left.onMouseDown = { [weak self] in self?.clearSelection(in: self?.right) }
        right.onMouseDown = { [weak self] in self?.clearSelection(in: self?.left) }
        addSubview(separator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("jen z kódu") }

    func show(
        _ block: DiffPairBlock,
        language: Language?,
        palette: SyntaxPalette,
        signature: String,
        gutter: Double
    ) {
        rows = block.count
        left.gutterWidth = gutter
        right.gutterWidth = gutter
        // V buňce dvojice je číslo jedno: vlevo staré, vpravo nové.
        left.numberColumns = 1
        right.numberColumns = 1
        // Word-level rozdíl (#153) se počítá **jednou pro obě strany** a až tehdy, když se text
        // opravdu skládá: `show` níž se z něj vrátí hned, když se obsah nezměnil, a tahle metoda
        // chodí i při pouhém přejezdu myší. Sloupec sám ho spočítat nemůže — protějšek je v tom
        // druhém.
        var computed: (left: WordDiff.Spans, right: WordDiff.Spans)?
        func words() -> (left: WordDiff.Spans, right: WordDiff.Spans) {
            if let computed { return computed }
            let spans = WordDiff.spans(left: block.left, right: block.right)
            computed = spans
            return spans
        }

        // Prázdná strana dvojice se kreslí jako **prázdný řádek**, ne jako mezera: řádky si musí
        // odpovídat i tam, kde jedna strana chybí (přidaný nebo odebraný kód).
        //
        // **Které řádky to jsou, se sloupci musí říct** (#277): v textu je z prázdné strany
        // nerozeznatelný prázdný kontextový řádek, takže „tady řádek není“ ví jedině dvojice.
        // Nastavuje se před složením textu, protože se to složením nemění.
        left.missingLines = Self.missing(in: block.left)
        right.missingLines = Self.missing(in: block.right)
        left.show(
            DiffBlock(lines: block.left.map { $0 ?? .blank }),
            language: language,
            palette: palette,
            signature: "L\(signature)",
            words: { words().left }
        )
        right.show(
            DiffBlock(lines: block.right.map { $0 ?? .blank }),
            language: language,
            palette: palette,
            signature: "R\(signature)",
            words: { words().right }
        )
        rowHeight = left.singleLineHeight
        needsLayout = true
        layoutColumns()
    }

    /// Sloupcům se musí nastavit **vlastní rámec**, ne jen rámec jejich clip view. Textové view
    /// s neomezenou šířkou containeru si velikost samo nedopočítá, takže po přesunu do `NSScrollView`
    /// zůstalo nulové — a v nulovém view nejde ani vybírat, ani nic vidět (nahlášené při zkoušení
    /// #157: „teď po úpravě nejde už vybírat vůbec“).
    ///
    /// Šířka je nejdelší řádek, **nejméně však šířka sloupce**: pozadí řádku i pruh rozsahu se
    /// kreslí přes celou šířku view, takže u krátkého kódu by končilo v polovině.
    private func layoutColumns() {
        let height = left.height(ofRows: rows)
        for (scroll, column) in [(leftScroll, left), (rightScroll, right)] {
            column.sizeToFit()
            column.frame = NSRect(
                x: 0,
                y: 0,
                width: max(column.frame.width, scroll.contentSize.width),
                height: height
            )
        }
    }

    func apply(leftRange: Set<Int>, rightRange: Set<Int>, leftDragged: Set<Int>, rightDragged: Set<Int>) {
        guard left.commentRangeLines != leftRange || right.commentRangeLines != rightRange
            || left.draggedLines != leftDragged || right.draggedLines != rightDragged
        else { return }
        left.commentRangeLines = leftRange
        right.commentRangeLines = rightRange
        left.draggedLines = leftDragged
        right.draggedLines = rightDragged
        left.needsDisplay = true
        right.needsDisplay = true
    }

    /// Výška bloku: řádky × výška řádku plus svislý inset. Bez zalamování je to přesné, takže se
    /// nemusí měřit layout — počítá to ale **sloupec sám** (`height(ofRows:)`), aby se výška nemohla
    /// rozejít s tím, kde sloupec kreslí text (#236). Šířka na ni nemá vliv; ve split pohledu se
    /// nezalamuje.
    func height(forWidth width: Double) -> Double {
        left.height(ofRows: rows)
    }

    /// Rámečky řádků — **jeden na dvojici**, protože sloupce jsou zarovnané. Overlay z nich staví
    /// pilulky po obou stranách.
    ///
    /// Počítají se aritmetikou, ne z layout manageru: sloupec se nezalamuje, takže je řádek vždycky
    /// jeden vizuální. **Musí ale začínat tam, kde začíná text** — tedy na svislém insetu, a krok je
    /// výška řádku bez něj (#236). Že to sedí na to, co hlásí layout manager, drží test.
    func lineFrames() -> [DiffBlockLineFrame] {
        let top = left.textContainerOrigin.y
        return (0..<rows).map { index in
            DiffBlockLineFrame(
                index: index,
                line: left.line(at: index) ?? .blank,
                rect: CGRect(x: 0, y: top + Double(index) * rowHeight, width: bounds.width, height: rowHeight)
            )
        }
    }

    override func layout() {
        super.layout()
        // Hranice polovin se bere z `DiffGutterGeometry` (#252): podle ní se umisťují i plochy na
        // tažení a pilulka, takže dva výpočty by znamenaly, že pilulka svítí v jedné polovině
        // a táhne se ve druhé.
        let right = DiffGutterGeometry.rightColumnX(inBlockOfWidth: bounds.width)
        let half = right - 1
        leftScroll.frame = NSRect(x: 0, y: 0, width: half, height: bounds.height)
        separator.frame = NSRect(x: half, y: 0, width: 1, height: bounds.height)
        rightScroll.frame = NSRect(x: right, y: 0, width: half, height: bounds.height)
        // Znovu po každé změně šířky: minimální šířka sloupce se odsud odvozuje.
        layoutColumns()
    }

    private func clearSelection(in column: DiffTextView?) {
        guard let column, column.selectedRange().length > 0 else { return }
        column.setSelectedRange(NSRange(location: 0, length: 0))
    }

    /// Indexy řádků, na kterých na téhle straně dvojice nic není (#277). Statická, protože je to
    /// čistý přepis pole na množinu — a `DiffTextView` si to spočítat nemůže, viz `missingLines`.
    static func missing(in side: [DiffLine?]) -> Set<Int> {
        Set(side.indices.filter { side[$0] == nil })
    }

    /// Záloha pro výběr klávesnicí (⇧+šipky, ⌘A) — tam žádný stisk myši není. `mouseDown` výš to
    /// řeší dřív, tohle jen dorovnává zbytek.
    func textViewDidChangeSelection(_ notification: Notification) {
        guard let changed = notification.object as? DiffTextView, changed.selectedRange().length > 0
        else { return }
        clearSelection(in: changed === left ? right : left)
    }
}

extension DiffLine {
    /// Prázdná protistrana dvojice. Není to řádek souboru, takže nemá čísla ani druh změny —
    /// jen drží zarovnání sloupců.
    static let blank = DiffLine(kind: .context, oldNumber: nil, newNumber: nil, text: "")
}
