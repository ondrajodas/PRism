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
///
/// **Od #422 je vodorovný pruh vidět** (legacy scroller, `DiffPairScrollView`) a blok si na něj
/// rezervuje 17 bodů výšky — jenže jen tehdy, když je co skrývat. Výška bloku tím **začala záležet
/// na šířce**; kde se to rozhoduje a proč na jednom místě, je u `height(forWidth:)`.
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
        /// Co je v kontejneru nakreslené. **Jediná paměť o tom, jestli má `updateNSView` co dělat**
        /// (#393) — viz `DiffBlockDrawing`.
        var drawing: DiffBlockDrawing<DiffPairBlock>?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Paměť koordinátoru se u nového view **zahazuje**. SwiftUI je vyrábí spolu, takže by k tomu
    /// dojít nemělo — ale kdyby ano, prázdný kontejner s klíčem z předchozího by zůstal prázdný,
    /// a to je zrovna ten druh vady, který se pozná až v okně.
    func makeNSView(context: Context) -> DiffPairBlockContainer {
        context.coordinator.drawing = nil
        return DiffPairBlockContainer()
    }

    func updateNSView(_ container: DiffPairBlockContainer, context: Context) {
        container.noteUpdate()
        // **Pruhy rozsahu se aplikují vždycky**, i když se blok nezměnil: mění se přejezdem myší
        // a tažením, tedy bez bloku. Je to porovnání čtyř množin, které jsou obvykle prázdné —
        // sazba za tím stojí o dva řády víc.
        container.apply(
            leftRange: leftRangeLines,
            rightRange: rightRangeLines,
            leftDragged: leftDraggedLines,
            rightDragged: rightDraggedLines
        )

        // Stráž, kvůli které tohle celé existuje (#393): SwiftUI si `updateNSView` volá při každém
        // přepočtu geometrie, takže všechno pod ní se ve ztuhlém okně platilo tisíckrát za sekundu
        // za nic.
        let drawing = DiffBlockDrawing(block: block, style: style, width: container.bounds.width)
        guard drawing != context.coordinator.drawing else { return }
        context.coordinator.drawing = drawing

        container.show(block, style: style, gutter: DiffLineView.contentInset(for: .split))

        let frames = container.lineFrames()
        guard frames != context.coordinator.frames else { return }
        context.coordinator.frames = frames
        DispatchQueue.main.async { noteFrames(frames) }
    }

    private var style: DiffBlockStyle {
        DiffBlockStyle(language: language, colorScheme: colorScheme)
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
    /// do pravého“). Scroll view je tu tedy kvůli **ořezu** a od #422 i kvůli **pruhu**, ze kterého
    /// je vidět, že za okrajem něco je.
    private let leftScroll = DiffPairScrollView()
    private let rightScroll = DiffPairScrollView()
    private let separator = NSBox()
    private var rowHeight: Double = 0
    private var rows = 0

    /// Kolikrát tomuhle bloku přišla aktualizace ze SwiftUI. **Vedle `mounts` schválně** (#393):
    /// samotná nula u nasazení by mohla znamenat i to, že aktualizace nepřišla vůbec, takže stráž
    /// z `DiffBlockDrawing` je ověřená jedině oběma čísly naráz.
    private(set) var updates = 0

    /// Kolikrát se blok nasadil do sloupců, tedy kolikrát průchod prošel stráží. Viz
    /// `DiffTextView.mounts`.
    private(set) var mounts = 0

    /// Kolikrát se v bloku doopravdy sázel text — **za oba sloupce**, takže jedno nasazení nového
    /// obsahu přidá dvě. Podrobnosti u `DiffTextView.typesettings`.
    var typesettings: Int { left.typesettings + right.typesettings }

    /// Přišla aktualizace ze SwiftUI. Volá to `DiffPairBlockView` **před** svou stráží, protože
    /// právě o průchody, které za ni nedojdou, tady jde.
    func noteUpdate() {
        updates += 1
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        separator.boxType = .separator
        for (scroll, column) in [(leftScroll, left), (rightScroll, right)] {
            scroll.documentView = column
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = true
            // **Autohide zůstává zapnutý** (#422): pruh dostane jen blok, který má co skrývat, a co
            // ho nepotřebuje, o těch 17 bodů nepřijde. Skrývání dělá AppKit sám podle toho, jestli
            // je dokument širší než plocha — neprogramuje se, jen se to musí umět **předpovědět**,
            // protože na tom teď visí výška bloku (viz `showsScroller(forWidth:)`).
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

    /// Nasadí blok do sloupců. **Volá se jen tehdy, když se něco změnilo** (`DiffBlockDrawing`),
    /// takže si tady všechno pod tím může dovolit být lineární v délce bloku — do #393 to bylo
    /// obráceně a platilo se to při každém přepočtu geometrie.
    func show(
        _ block: DiffPairBlock,
        style: DiffBlockStyle,
        gutter: Double
    ) {
        mounts += 1
        rows = block.count
        left.gutterWidth = gutter
        right.gutterWidth = gutter
        // V buňce dvojice je číslo jedno: vlevo staré, vpravo nové.
        left.numberColumns = 1
        right.numberColumns = 1
        // Word-level rozdíl (#153) se počítá **jednou pro obě strany** a až tehdy, když se text
        // opravdu skládá: `show` níž se z něj vrátí hned, když se obsah nezměnil — typicky když se
        // sem přišlo jen kvůli jiné šířce. Sloupec sám ho spočítat nemůže — protějšek je v tom
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
        // Klíč sazby je **v každém sloupci jeho vlastní obsah** (#393), ne řetězec s prefixem
        // `L`/`R`: každý sloupec porovná svoje řádky sám, takže se strany nemají jak splést a hash
        // celého bloku k tomu není potřeba.
        left.show(
            DiffBlock(lines: block.left.map { $0 ?? .blank }),
            style: style,
            words: { words().left }
        )
        right.show(
            DiffBlock(lines: block.right.map { $0 ?? .blank }),
            style: style,
            words: { words().right }
        )
        rowHeight = left.singleLineHeight
        needsLayout = true
        layoutColumns()
    }

    /// Sloupcům se musí nastavit **vlastní rámec**, ne jen rámec jejich clip view. Textové view
    /// s neomezenou šířkou containeru si velikost samo nedopočítá, takže po přesunu do `NSScrollView`
    /// zůstalo nulové — a v nulovém view nejde ani vybírat, ani nic vidět (nahlášené při zkoušení
    /// #157: „teď po úpravě nejde už vybírat vůbec“). Od #422 je to navíc rámec, o kterém se
    /// **nevyjednává**: `isHorizontallyResizable` je vypnuté, protože AppKit ho počítal z `usedRect`
    /// bez gutteru a srážel zpátky na šířku plochy — podrobnosti u `DiffTextView.pairColumn()`.
    ///
    /// Šířka je nejdelší řádek **i s gutterem**, nejméně však šířka sloupce: pozadí řádku i pruh
    /// rozsahu se kreslí přes celou šířku view, takže u krátkého kódu by končilo v polovině.
    ///
    /// **Do #422 to byl `sizeToFit()` a ten vracel nulu** (`maxSize` je u view složeného z kódu
    /// `(0, 0)`), takže dokument byl vždycky přesně tak široký jako plocha: nebylo **co rolovat**
    /// a konec dlouhého řádku se z okna nedal dostat vůbec. Šířku proto hlásí sloupec
    /// (`naturalWidth`) — tentýž typ, který kreslí text na `textContainerOrigin.x`, takže se to,
    /// kam text sahá, a to, kam se dá odrolovat, nemá jak rozejít.
    private func layoutColumns() {
        let height = left.height(ofRows: rows)
        for (scroll, column) in [(leftScroll, left), (rightScroll, right)] {
            column.frame = NSRect(
                x: 0,
                y: 0,
                width: max(column.naturalWidth, Double(scroll.contentSize.width)),
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

    /// Výška bloku: řádky × výška řádku plus svislý inset, a k tomu **pás vodorovného pruhu**, když
    /// se na téhle šířce kreslí (#422). Bez zalamování je zbytek přesný, takže se nemusí měřit
    /// layout — počítá to ale **sloupec sám** (`height(ofRows:)`), aby se výška nemohla rozejít
    /// s tím, kde sloupec kreslí text (#236).
    ///
    /// **Na šířce od #422 záleží**, a to je celá past tohohle issue: do té doby nezáleží, protože se
    /// ve split pohledu nezalamuje. Rezervovat pás musí **totéž místo, které rozhoduje, že pruh
    /// je** — proto se obojí ptá `showsScroller(forWidth:)` a proto ta funkce žije tady, ne ve
    /// view. Dvě místa znamenají dvě pravdy o jedné výšce a poslední řádek bloku zmizí pod pruhem
    /// (u #236 to stálo kód přes bublinu nálezu).
    func height(forWidth width: Double) -> Double {
        left.height(ofRows: rows) + (showsScroller(forWidth: width) ? DiffPairScrollView.scrollerHeight : 0)
    }

    /// Kreslí se na téhle šířce bloku vodorovný pruh? **Jedna odpověď pro výšku i pro layout**.
    ///
    /// Rozhoduje se to **na blok, ne na půlku** (#422): rolovací plocha je blok a každá strana má
    /// svůj nejdelší řádek, takže pruh potřebuje občas jen jedna z nich — obě půlky ale musí mít
    /// pořád stejně vysoké řádky, a to je celé, proč se vedle sebe kreslí. Půlka, která pruh
    /// nepotřebuje, má proto v tom pásu prázdno.
    ///
    /// Kritérium je **totéž, podle kterého se rozhoduje AppKit** (autohide): dokument sloupce je
    /// široký `max(naturalWidth, plocha)`, takže se pruh objeví právě tehdy, když je přirozená
    /// šířka větší než plocha. Že to sedí, se netvrdí druhým výpočtem — `DiffPairScrollerTests` to
    /// srovnávají s tím, co po layoutu hlásí `NSScrollView` sám, a **přes pásmo šířek**: rozejde se
    /// to jenom v pásmu, u jedné šířky by test prošel (pravidlo z #236).
    func showsScroller(forWidth width: Double) -> Bool {
        let column = Self.columnWidth(inBlockOfWidth: width)
        return left.naturalWidth > column || right.naturalWidth > column
    }

    /// Šířka jedné poloviny bloku. Bere se z `DiffGutterGeometry` jako v `layout()` — jinak by se
    /// „vejde se to do sloupce“ počítalo z jiné šířky, než jakou sloupec dostane.
    private static func columnWidth(inBlockOfWidth width: Double) -> Double {
        DiffGutterGeometry.rightColumnX(inBlockOfWidth: width) - 1
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
        //
        // Plochy dostanou **celou výšku bloku**, i tu rezervovanou na pruh: pás si `NSScrollView`
        // bere ze své výšky sám a clip view zůstává nad ním (změřeno u #422 — plocha 200 b vysoká
        // hlásí `contentSize` 183 a scroller na `y: 183`). Řádky proto zůstávají tam, kde byly,
        // a `lineFrames()` se pruhem nemění.
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
