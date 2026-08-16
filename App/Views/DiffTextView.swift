import AppKit

/// `NSTextView`, který kreslí blok řádků diffu (#157): text je jeden, ale pozadí, čísla řádků
/// a znaky změny se kreslí **po řádcích**.
///
/// **Čísla a znaky nejsou v textu**, jsou nakreslené v gutteru vlevo. Kdyby byly součástí textu,
/// kopírovaly by se s ním — a do schránky má jít kód, ne diff. Je to tentýž požadavek, jaký měl
/// `Policy.code(of:)` u kopírování z menu.
///
/// **TextKit 1, ne 2.** Geometrie řádků se čte z `NSLayoutManager` (`boundingRect(forGlyphRange:)`),
/// protože podle ní se kreslí pozadí i čísla — a TextKit 2 layout manager nemá. Vynutí se tím, že
/// se textové view vyrobí s ručně složeným `NSTextStorage`/`NSLayoutManager`/`NSTextContainer`.
final class DiffTextView: NSTextView {
    /// Řádky bloku ve stejném pořadí, jako jsou v textu.
    private(set) var lines: [DiffLine] = []
    /// Rozsah znaků každého řádku — z něj se počítá jeho rámeček.
    private var lineRanges: [NSRange] = []
    /// Buňky, které leží v rozsahu některého komentáře (pruh přes řádek).
    var commentRangeLines: Set<Int> = []
    /// Totéž pro rozsah, který se právě táhne — svítí výrazněji.
    var draggedLines: Set<Int> = []
    /// Řádky, na kterých v tomhle sloupci **žádný řádek souboru není** (#277) — prázdný protějšek
    /// dvojice v pohledu vedle sebe.
    ///
    /// Vlastní množina, ne druh řádku: prázdná strana se do textu skládá jako prázdný **kontextový**
    /// řádek (`DiffPairBlockContainer.blank`), aby si sloupce odpovídaly, takže z modelu se „tady
    /// nic není“ poznat nedá — a rozšiřovat `DiffLine.Kind` o případ, který existuje jen v jednom
    /// rozvržení, by ten rozdíl protáhlo parserem, `Policy` i kotvami komentářů. Do #277 se tenhle
    /// stav nekreslil vůbec, takže díra byla od nezměněného řádku k nerozeznání.
    var missingLines: Set<Int> = [] {
        didSet {
            guard missingLines != oldValue else { return }
            needsDisplay = true
        }
    }
    /// Kolik sloupců s čísly se kreslí: dva v pohledu pod sebou, jeden v buňce dvojice.
    var numberColumns = 2
    /// Šířka sloupců, které se kreslí vlevo: sloupec ikonky, čísla a znak změny.
    ///
    /// **Posouvá původ textu, nezužuje kontejner z obou stran** (#236). Do #236 se gutter dělal
    /// symetrickým `textContainerInset`em, jenže ten AppKit uplatní na **obě** strany: změřeno, že
    /// při šířce view 600 a gutteru 136 vyjde kontejner 328 pt, tedy o gutter užší i vpravo, kde
    /// žádné sloupce nejsou. Text se tím zalamoval o 17 znaků dřív, než musel, a u pravého okraje
    /// zůstávalo mrtvé místo.
    var gutterWidth: Double = 0 {
        didSet {
            guard gutterWidth != oldValue else { return }
            invalidateTextContainerOrigin()
            fitContainerWidth(bounds.width)
            needsDisplay = true
        }
    }

    /// Zalamuje se text na šířku view? Pod sebou ano, ve sloupci dvojice ne — tam se dlouhý kód
    /// posouvá vodorovně, aby zůstal zarovnaný s protějškem. Rozhoduje to o šířce kontejneru, tedy
    /// i o tom, na jaké šířce se měří výška.
    private var wrapsText = false

    /// Podpis posledně složeného obsahu — z něj se pozná, že se text skládat nemusí.
    private var signature: String?

    /// **Vodorovný inset je nula a zůstane nula** (#236): odsazení na gutter dělá
    /// `textContainerOrigin`, protože `textContainerInset` platí na obě strany. Svisle symetrický
    /// zůstává schválně — 2 pt nad prvním řádkem a pod posledním.
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        textContainerInset = NSSize(width: 0, height: 2)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("jen z kódu") }

    /// Blok, který se má vykreslit. Text se skládá **jednou** a drží se rozsahy řádků, aby se
    /// pozadí a čísla daly kreslit bez druhého průchodu textem.
    ///
    /// **Skládá se jen tehdy, když se obsah opravdu změnil**, a je to podstatné:
    /// `setAttributedString` zruší rozdělaný výběr, a `updateNSView` se volá při každém
    /// překreslení — tedy i když myš přejede na jiný řádek a přesune se pilulka na komentář.
    /// Bez téhle podmínky se výběr rušil při každém hnutí myší (nahlášené při zkoušení #157).
    ///
    /// **Text vzniká jako jeden řetězec a barvy se do něj dopisují** (#275), ne jako řetězec
    /// slepený z run. Do #275 se za každý run vyrobil `NSAttributedString` a připojil — u velkého
    /// diffu 16 000 objektů na jedno projetí, tedy **22,2 ms z 79** na 27 blocích. Jeden řetězec
    /// a `addAttribute` na rozsah dělá totéž za **4,1 ms**; text i atributy z toho vyjdou znak po
    /// znaku stejné, což drží `DiffWordHighlightTests` a `DiffBlockCompositionTests`.
    ///
    /// - Parameter words: co se uvnitř přepsaných řádků změnilo (#153). Je to **closure, ne
    ///   hodnota**, schválně: word-level rozdíl je jediná drahá věc v tomhle skládání (LCS na
    ///   dvojici) a takhle se spočítá až za tou stráží výš, tedy jednou na obsah bloku — ne při
    ///   každém přejezdu myší, kdy `updateNSView` doběhne až sem a vrátí se.
    ///
    ///   **Výchozí hodnotu nemá schválně:** kdo blok kreslí, ať se rozhodne, čím ho porovnat.
    ///   S `{ [:] }` by nový volající zvýraznění tiše vypnul a nikdo by to nepoznal.
    func show(
        _ block: DiffBlock,
        language: Language?,
        palette: SyntaxPalette,
        signature: String,
        words: () -> WordDiff.Spans
    ) {
        guard self.signature != signature else { return }
        self.signature = signature
        lines = block.lines

        let composed = Self.compose(block.lines, words: words(), language: language, palette: palette)
        lineRanges = composed.ranges
        textStorage?.setAttributedString(composed.text)
        needsDisplay = true
    }

    /// Text bloku i s obarvením, a k němu rozsahy řádků v něm — **čistá funkce nad řádky**, žádný
    /// stav view.
    ///
    /// Zvlášť od `show(…)` schválně (#275): je to ta polovina, kterou jde změřit bez sazby, takže
    /// se dá poznat, kolik z ceny projíždění je skládání textu a kolik už `NSLayoutManager`.
    /// Měřidlo je `DiffPerformanceMeasurement.blockTypesettingBreakdown`.
    ///
    /// **Rozsahy se vracejí, ne přijímají**, a je to celá pojistka: počítají se z týchž řádků, ze
    /// kterých se skládá text, takže se s ním nemají jak rozejít. Jako parametr by to byla povinnost
    /// volajícího, a ta se dá nesplnit potichu — obarvení by pak sedělo o kus vedle.
    static func compose(
        _ lines: [DiffLine],
        words: WordDiff.Spans,
        language: Language?,
        palette: SyntaxPalette
    ) -> (text: NSAttributedString, ranges: [NSRange]) {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // Pět převodů na blok místo jednoho na run (#275) — viz `SyntaxColors`.
        let colors = SyntaxColors(palette)
        let ranges = lineRanges(of: lines)
        let result = NSMutableAttributedString(
            string: lines.map(\.text).joined(separator: "\n"),
            attributes: [.font: font]
        )
        for (index, line) in lines.enumerated() {
            colorize(line, in: result, over: ranges[index], language: language, colors: colors)
            highlight(words[index] ?? [], of: line, in: result, from: ranges[index].location)
        }
        return (result, ranges)
    }

    /// Rozsahy řádků ve složeném textu, **bez** zalomení mezi nimi.
    ///
    /// Počítá se v UTF-16, protože v nich měří `NSAttributedString`. Je to ta nová třída chyby,
    /// kterou #275 přineslo: emoji je jeden `Character`, ale **dva** kódy, takže s `count` by
    /// obarvení i word-level vrstva skončily o kus doprava.
    private static func lineRanges(of lines: [DiffLine]) -> [NSRange] {
        var result: [NSRange] = []
        result.reserveCapacity(lines.count)
        var location = 0
        for line in lines {
            let length = line.text.utf16.count
            result.append(NSRange(location: location, length: length))
            // Zalomení patří mezi řádky, do rozsahu ani jednoho z nich.
            location += length + 1
        }
        return result
    }

    /// Jeden řádek obarvený stejnými pravidly jako v diffu — jedno místo, kde se rozhoduje, co je
    /// klíčové slovo. Poznámka `git`u (`meta`) je ztlumená, jako v `DiffLineView`.
    private static func colorize(
        _ line: DiffLine,
        in result: NSMutableAttributedString,
        over range: NSRange,
        language: Language?,
        colors: SyntaxColors
    ) {
        if line.kind == .meta {
            result.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            return
        }
        // Soubor bez rozpoznaného jazyka zůstane v barvě okolí — font už na řádku je.
        guard let language else { return }
        var location = range.location
        for run in SyntaxHighlighter.runs(of: line.text, in: language) {
            let length = run.text.utf16.count
            // Runy se z definice skládají zpátky na řádek (`SyntaxRun`), takže se za jeho konec
            // dostat nemají. Kdyby přece, je barva to jediné, o co se přijde — pád uprostřed diffu
            // je horší než neobarvené slovo, tatáž úvaha jako u `highlight(_:of:in:from:)`.
            guard location + length <= NSMaxRange(range) else { return }
            if let color = colors.color(for: run.kind) {
                result.addAttribute(.foregroundColor, value: color, range: NSRange(location: location, length: length))
            }
            location += length
        }
    }

    /// Word-level zvýraznění jako **druhá vrstva nad** hotovým textem (#153).
    ///
    /// Sytější pozadí, ne jiná barva písma: písmo patří obarvení syntaxe a dvě sady barev na
    /// tomtéž textu se čtou jako kaše. Pozadí navíc leží nad tím řádkovým (12 %), takže se
    /// změněný kus liší od zbytku řádku, ne od okolí.
    ///
    /// **Do `SyntaxRunCache` to nesmí** a je to celé jádro věci: zvýraznění závisí na protějšku
    /// dvojice, kdežto cache je klíčovaná `(text řádku, jazyk)` — tentýž řádek proti jinému
    /// protějšku by z ní vytáhl cizí zvýraznění, a to potichu. Proto se přidává **až tady**,
    /// atributem přes hotové runy.
    private static func highlight(
        _ spans: [Range<String.Index>],
        of line: DiffLine,
        in result: NSMutableAttributedString,
        from start: Int
    ) {
        guard !spans.isEmpty, let color = DiffTextView.wordBackground(of: line.kind) else { return }
        for span in spans {
            let range = NSRange(span, in: line.text)
            let target = NSRange(location: start + range.location, length: range.length)
            // Rozsah patří textu, ze kterého se počítal, takže mimo složený řetězec sáhnout nemá
            // jak — a kdyby přece, je zvýraznění to jediné, o co se přijde. Pád uprostřed diffu
            // je horší než neobarvené slovo.
            guard NSMaxRange(target) <= result.length else { continue }
            result.addAttribute(.backgroundColor, value: color, range: target)
        }
    }

    // MARK: - Geometrie řádků

    /// **Text začíná za gutterem** — o ten posun se stará původ kontejneru, ne inset (#236).
    ///
    /// Změřeno, že to platí pro kreslení i pro klikání: nakreslený text začíná na `gutterWidth`
    /// (+ `lineFragmentPadding`) a `characterIndexForInsertion` sedí na znak. Ve sloupci dvojice
    /// z toho vyjde přesně to, co dřív dělal inset — původ tam AppKit klade na `inset.width` taky,
    /// takže se pohled vedle sebe nikam neposunul.
    override var textContainerOrigin: NSPoint {
        NSPoint(x: gutterWidth, y: textContainerInset.height)
    }

    /// Rámeček řádku v souřadnicích view — z něj se kreslí pozadí i čísla, a **ven** z něj se hlásí
    /// pozice pro tlačítko na komentář a pro tažení rozsahu.
    ///
    /// Bere skutečný rámeček z layout manageru, ne výšku řádku × index: dlouhý řádek se zalomí na
    /// dva vizuální a číslo by se pak rozešlo s kódem.
    func frame(ofLine index: Int) -> NSRect? {
        guard lineRanges.indices.contains(index),
              let layoutManager, let textContainer
        else { return nil }

        let glyphs = layoutManager.glyphRange(forCharacterRange: lineRanges[index], actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        // Tímtéž původem, jakým se text kreslí — jinak by rámeček řekl něco jiného, než co je vidět.
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        // Prázdný řádek nemá glyfy, takže by vyšel nulově vysoký — vezme se výška písma.
        if rect.height == 0 { rect.size.height = layoutManager.defaultLineHeight(for: font ?? .systemFont(ofSize: 12)) }
        return rect
    }

    /// Rámečky všech řádků. Volá se po layoutu, takže se dá poslat do SwiftUI.
    func lineFrames() -> [(line: DiffLine, index: Int, rect: NSRect)] {
        lines.enumerated().compactMap { index, line in
            frame(ofLine: index).map { (line: line, index: index, rect: $0) }
        }
    }

    /// **Barva výběru se nemění podle fokusu.** AppKit sáhne u neaktivního textu po
    /// `unemphasizedSelectedTextBackgroundColor` (šedá) bez ohledu na `selectedTextAttributes` —
    /// tady se to přebíjí, protože v diffu je vybraný kód pořád vybraný, i když člověk zamíří myší
    /// jinam. Nahlášené při zkoušení #157 („když je myš pryč, tak šedě, normálně to chci modře“).
    override var selectedTextAttributes: [NSAttributedString.Key: Any] {
        get { [.backgroundColor: NSColor.selectedTextBackgroundColor] }
        set { super.selectedTextAttributes = newValue }
    }

    /// Stisk myši v tomhle sloupci. Kontejner z toho ruší výběr v tom druhém — **při stisknutí**,
    /// ne až při puštění (vyžádané při zkoušení #157).
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }

    /// Kurzor po sloupcích: **ruka nad pilulkou, šipka nad čísly, I-beam nad kódem**.
    ///
    /// Jde to přes **tracking area a `cursorUpdate`**, ne přes `addCursorRect` ani SwiftUI
    /// `onHover`. Obojí se u #157 zkoušelo a nefungovalo: `NSCursor.set()` ze SwiftUI si textové
    /// view hned přepíše (ruka blikla jen v rohu, kde se to potkalo) a `cursorRect` si přebije
    /// vlastními, kterými si drží I-beam nad celou plochou. `cursorUpdate` je poslední slovo.
    ///
    /// Pás pilulky je široký `iconColumn` a platí v **celé výšce bloku**, i když je pilulka vidět
    /// jen u řádku pod myší: kamkoli v tom pásu myš přijde, tam se pilulka zapne, takže ruka nikdy
    /// neslibuje tlačítko, které tam není.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate, .mouseMoved],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.x < DiffLineView.iconColumn {
            NSCursor.pointingHand.set()
        } else if point.x < gutterWidth {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    /// `cursorUpdate` chodí jen při vstupu do tracking areay, takže **při pohybu vevnitř** by
    /// kurzor zůstal ten, se kterým myš přijela. Sloupce jsou úzké a přejezd mezi nimi je pohyb
    /// uvnitř téže areay — proto se rozhoduje i tady.
    ///
    /// **Při stisknutém tlačítku ne**: to se táhne (výběr textu, rozsah komentáře) a kurzor má
    /// zůstat, jaký byl. Bez téhle podmínky se přepínal podle toho, přes který sloupec tažení
    /// právě jelo, a **problikával** (nahlášené při zkoušení #157).
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard NSEvent.pressedMouseButtons == 0 else { return }
        cursorUpdate(with: event)
    }

    // MARK: - Kreslení

    /// **Všechno vlastní kreslení musí být před `super.draw`.** Co se nakreslí po něm, není vidět —
    /// změřeno u #157 tím, že se do gutteru nakreslil plný obdélník a taky nebyl (kdežto pruhy
    /// pozadí kreslené před `super.draw` vidět jsou). Text ani gutter se nepřekrývají: text začíná
    /// na `textContainerOrigin.x`, tedy přesně na šířce gutteru.
    ///
    /// **Do #236 to tvrzení neplatilo**: gutter se dělal symetrickým `textContainerInset`em, takže
    /// text byl odsazený o jeho dvojnásobek — jen se to vpravo nepoznalo, protože tam nic nekreslíme.
    override func draw(_ dirtyRect: NSRect) {
        drawRows(in: dirtyRect)
        drawGutter(in: dirtyRect)
        super.draw(dirtyRect)
    }

    /// Pozadí podle druhu řádku a pruh rozsahu — **pod** textem, takže se kreslí před `super.draw`.
    ///
    /// Přes **celou šířku** view, ne jen za textem: pozadí, které končí s posledním znakem, čte se
    /// jako podtržení, ne jako řádek diffu.
    private func drawRows(in dirtyRect: NSRect) {
        for (index, line) in lines.enumerated() {
            guard let rect = frame(ofLine: index) else { continue }
            let strip = NSRect(x: 0, y: rect.minY, width: bounds.width, height: rect.height)
            guard strip.intersects(dirtyRect) else { continue }

            if let background = DiffTextView.background(of: line.kind) {
                background.setFill()
                strip.fill()
            }
            if let tint = tint(of: index) {
                tint.setFill()
                strip.fill()
            }
        }
        // **Šrafa až nad plochami**, jako v návrhu, kde je to gradient nad `transparent`. Kreslená
        // před nimi by zmizela pod pozadím řádku — vyzkoušeno, byla to první verze #277.
        for run in missingRuns() where run.intersects(dirtyRect) {
            drawMissing(in: run)
        }
    }

    /// Souvislé úseky prázdných protějšků jako jeden rámeček na úsek.
    ///
    /// **Po úsecích, ne po řádcích**, a je to obojí najednou: šrafa je tím **spojitá** (pruh přes
    /// hranici řádku pokračuje, nezačíná znovu) a je jí řádově méně — u přidaného bloku o šedesáti
    /// řádcích jeden rámeček místo šedesáti, tedy stovky úseček místo tisíců, a to při **každém**
    /// překreslení. Je to tatáž úvaha jako u overlay gutteru (#252): co se dá spočítat naráz, se
    /// nemá dělat na každý řádek.
    private func missingRuns() -> [NSRect] {
        var result: [NSRect] = []
        for index in lines.indices {
            guard missingLines.contains(index), let rect = frame(ofLine: index) else { continue }
            let strip = NSRect(x: 0, y: rect.minY, width: bounds.width, height: rect.height)
            // Navazuje na předchozí úsek? Porovnává se **poloha**, ne index — mezi dvěma prázdnými
            // řádky může být řádek bez rámečku, a ten úsek přerušuje.
            if let last = result.last, abs(last.maxY - strip.minY) < 0.5 {
                result[result.count - 1] = last.union(strip)
            } else {
                result.append(strip)
            }
        }
        return result
    }

    /// Prázdný protějšek dvojice (#277): šrafa přes celý úsek.
    ///
    /// **Plocha se nekreslí**, jen pruhy — v návrhu je pod gradientem `transparent`, takže tam, kde
    /// řádek není, prosvítá plocha obsahu. Šrafa se ořezává na úsek, protože pruhy jsou o jeho výšku
    /// posunuté doleva (sklon 45°) a bez ořezu by přetekly nad něj a pod něj.
    private func drawMissing(in run: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: run).setClip()
        NSColor(Palette.diffMissingStripe).setStroke()
        let path = NSBezierPath()
        path.lineWidth = DiffMissingHatch.lineWidth
        for segment in DiffMissingHatch.segments(in: run) {
            path.move(to: segment.from)
            path.line(to: segment.to)
        }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Čísla řádků a znak změny — v insetu vlevo, kam text nezasahuje.
    private func drawGutter(in dirtyRect: NSRect) {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        for (index, line) in lines.enumerated() {
            guard let rect = frame(ofLine: index), rect.intersects(dirtyRect) else { continue }
            // Čísla u **prvního** vizuálního řádku zalomeného kódu, ne na jeho středu.
            let top = NSRect(x: 0, y: rect.minY, width: gutterWidth, height: font.boundingRectForFont.height + 2)

            if numberColumns > 1 {
                draw(number: line.oldNumber, in: top, column: 0, font: font)
                draw(number: line.newNumber, in: top, column: 1, font: font)
            } else {
                // V buňce dvojice je číslo jedno — to, které na téhle straně existuje.
                draw(number: line.newNumber ?? line.oldNumber, in: top, column: 0, font: font)
            }
            draw(sign: line.kind, in: top, font: font)
        }
    }

    /// **Kreslí se `draw(in:)`, ne `draw(at:)`.** Textové view je flipped, takže `draw(at:)` položí
    /// text **nad** daný bod — tedy mimo řádek a mimo view. Čísla se pak nekreslila vůbec, ačkoli
    /// se kód volal se správnými hodnotami (nahlášené při zkoušení #157: „čísla zmizely úplně“).
    /// `draw(in:)` bere rámeček a zarovnání z odstavce, takže flipnutí řeší AppKit sám.
    private func draw(number: Int?, in rect: NSRect, column: Int, font: NSFont) {
        guard let number else { return }
        // **Za sloupcem ikonky**, ne od levé hrany: ikonka má vlastní sloupec a čísla začínají
        // až za ním. Bez toho offsetu vycházela čísla uříznutá.
        let box = NSRect(
            x: DiffLineView.iconColumn + Double(column) * DiffTextView.numberColumn,
            y: rect.minY,
            width: DiffTextView.numberColumn - 8,
            height: rect.height
        )
        NSAttributedString(
            string: String(number),
            attributes: [
                .font: font,
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: DiffTextView.aligned(.right),
            ]
        )
        .draw(in: box)
    }

    private func draw(sign kind: DiffLine.Kind, in rect: NSRect, font: NSFont) {
        let symbol = DiffTextView.sign(of: kind)
        guard !symbol.isEmpty else { return }
        // Znak stojí ve **svém** sloupci na konci gutteru, ne v tom s čísly.
        let box = NSRect(
            x: gutterWidth - DiffLineView.signColumn,
            y: rect.minY,
            width: DiffLineView.signColumn,
            height: rect.height
        )
        NSAttributedString(
            string: symbol,
            attributes: [
                .font: font,
                .foregroundColor: NSColor(DiffLineView.signColor(of: kind)),
                .paragraphStyle: DiffTextView.aligned(.center),
            ]
        )
        .draw(in: box)
    }

    private static func aligned(_ alignment: NSTextAlignment) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        return style
    }

    private func tint(of index: Int) -> NSColor? {
        if draggedLines.contains(index) { return NSColor(DiffLineView.dragTint) }
        if commentRangeLines.contains(index) { return NSColor(DiffLineView.rangeTint) }
        return nil
    }

    /// Řádek na daném indexu, nebo `nil` mimo blok.
    func line(at index: Int) -> DiffLine? {
        lines.indices.contains(index) ? lines[index] : nil
    }

    // MARK: - Výška

    /// Výška, kterou blok na dané šířce view **nakreslí**.
    ///
    /// Měří se na téže šířce kontejneru, jakou si view nastaví při kreslení (`fitContainerWidth`),
    /// a je to celé jádro #236: dokud se měřilo na o gutter širším kontejneru, zalomil se řádek,
    /// který se do změřené šířky ještě vešel. Blok pak nakreslil víc vizuálních řádků, než na kolik
    /// si řekl, a přeteklý text šel přes bublinu nálezu pod sebou — `NSTextView` je nad SwiftUI
    /// obsahem, takže byl vidět kód přes bublinu.
    func height(forWidth width: Double) -> Double? {
        guard let layoutManager, let textContainer else { return nil }
        isMeasuring = true
        defer { isMeasuring = false }
        textContainer.size = containerSize(forWidth: width)
        layoutManager.ensureLayout(for: textContainer)
        return layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2
    }

    /// Výška bloku o daném počtu **nezalomených** řádků. Sloupec dvojice se nezalamuje, takže se
    /// nemusí měřit layout.
    ///
    /// Svislý inset se připočítá **celý a jen jednou** (nahoře a dole), ne po řádcích: dokud ho
    /// nesl `singleLineHeight`, utíkal každý další řádek o 2 pt (#236) — na osmi řádcích 12 pt,
    /// na šedesátiřádkovém bloku 116 pt, tedy pilulka komentáře sedm řádků pod svým kódem.
    func height(ofRows rows: Int) -> Double {
        Double(max(rows, 1)) * singleLineHeight + textContainerInset.height * 2
    }

    /// Výška jednoho řádku textu — **bez insetu**, ten platí na blok, ne na řádek.
    var singleLineHeight: Double {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        guard let layoutManager else { return font.boundingRectForFont.height }
        return layoutManager.defaultLineHeight(for: font)
    }

    /// Rozměr kontejneru pro danou šířku view: co zbude za gutterem. Ve sloupci dvojice neomezený —
    /// tam se nezalamuje a dlouhý kód se posouvá vodorovně.
    private func containerSize(forWidth width: Double) -> NSSize {
        NSSize(
            width: wrapsText ? max(width - gutterWidth, 0) : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    /// Kontejner drží šířku view **bez gutteru**. Nechat to na `widthTracksTextView` nejde: ten
    /// odečítá `textContainerInset.width` na obě strany (#236).
    ///
    /// Nastavuje se **jen při změně**, aby se to nezacyklilo: změnu geometrie kontejneru si AppKit
    /// vyloží jako důvod zavolat `setFrameSize`, odkud se sem chodí.
    private func fitContainerWidth(_ width: Double) {
        guard wrapsText, let textContainer else { return }
        let size = containerSize(forWidth: width)
        guard textContainer.size != size else { return }
        textContainer.size = size
    }

    /// Měří se právě teď výška? Nastavení `textContainer.size` si AppKit vyloží jako změnu geometrie
    /// a **sám zavolá `setFrameSize`** — a ten by změřenou šířku hned přepsal tou, jakou má view
    /// zrovna teď. Měření je přitom dotaz na **budoucí** šířku („jak vysoký bys byl na 400?“), takže
    /// odpověď musí vydržet až do chvíle, kdy SwiftUI ten rámec nastaví.
    ///
    /// Změřeno u #236: bez téhle stráže se měřilo o jednu šířku pozadu — tedy zase na jiné šířce,
    /// než na jaké se kreslí, jen jinak. Blok o dvou dlouhých řádcích si při šířce 300 řekl o 36 pt
    /// a nakreslil 162.
    private var isMeasuring = false

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard !isMeasuring else { return }
        fitContainerWidth(newSize.width)
    }

    // MARK: - Skládání view

    /// Blok pohledu **pod sebou**: zalamuje na šířku view zbylou za gutterem.
    static func wrappingBlock() -> DiffTextView {
        let textView = textKit1()
        textView.wrapsText = true
        // Zalamování místo vodorovného scrollu. Zalomení není znak, takže se do vybraného textu
        // nedostane.
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        return textView
    }

    /// Sloupec pohledu vedle sebe: **nezalamuje** a posouvá se vodorovně, aby zůstal zarovnaný
    /// s protějškem (viz `DiffPairBlockView`).
    static func pairColumn() -> DiffTextView {
        let textView = textKit1()
        textView.textContainer?.size = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = true
        return textView
    }

    /// **Ručně složený TextKit 1.** `NSTextView(frame:)` dostane na dnešním macOS TextKit 2, kde je
    /// `layoutManager` nil — a bez něj se nedá zjistit, kde který řádek leží, tedy ani nakreslit
    /// čísla a pozadí.
    ///
    /// **`widthTracksTextView` je vypnuté v obou pohledech** (#236): šířku kontejneru si view drží
    /// samo (`fitContainerWidth`), protože gutter ubírá místo jen vlevo.
    private static func textKit1() -> DiffTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layout.addTextContainer(container)

        let textView = DiffTextView(frame: NSRect.zero, textContainer: container)
        textView.isEditable = false
        // Read-only, ale **vybíratelné** — o tohle celé #157 je.
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        // **Výběr má být modrý i tehdy, když je fokus jinde.** AppKit u neaktivního textu kreslí
        // šedou (`unemphasizedSelectedTextBackgroundColor`), což u diffu znamená, že vybraný kód
        // zešedne, jak myš odjede — a vypadá to, že výběr zmizel. Vyžádané při zkoušení #157.
        textView.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        return textView
    }

    /// Šířka jednoho sloupce s číslem — tatáž hodnota jako v `DiffLineView`, aby se bubliny
    /// s kódem nerozešly.
    static let numberColumn = DiffLineView.numberColumn

    static func background(of kind: DiffLine.Kind) -> NSColor? {
        switch kind {
        case .added, .removed: NSColor(DiffLineView.background(of: kind))
        case .context, .meta: nil
        }
    }

    /// Pozadí změněného kusu přepsaného řádku (#153). Barvu drží `DiffLineView`, ať se obě
    /// vrstvy nekreslí každá z jiné palety.
    ///
    /// **Převádí se jednou** (#275): `NSColor(Color)` je most ze SwiftUI a tohle se ptá na každý
    /// přepsaný řádek bloku. Na paletě obarvení to nezávisí, takže se to dá držet staticky —
    /// a dynamická barva zůstane dynamická, režim se v ní nezmrazí.
    static func wordBackground(of kind: DiffLine.Kind) -> NSColor? {
        switch kind {
        case .added: addedWordBackground
        case .removed: removedWordBackground
        case .context, .meta: nil
        }
    }

    private static let addedWordBackground = DiffLineView.wordBackground(of: .added).map(NSColor.init)
    private static let removedWordBackground = DiffLineView.wordBackground(of: .removed).map(NSColor.init)

    static func sign(of kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .context, .meta: ""
        }
    }
}
