import AppKit

/// `NSTextView`, který kreslí blok řádků diffu (#157): text je jeden, ale pozadí, čísla řádků
/// a znaky změny se kreslí **po řádcích**.
///
/// **Čísla a znaky nejsou v textu**, jsou nakreslené v `textContainerInset.width` vlevo. Kdyby
/// byly součástí textu, kopírovaly by se s ním — a do schránky má jít kód, ne diff. Je to tentýž
/// požadavek, jaký měl `Policy.code(of:)` u kopírování z menu.
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
    /// Kolik sloupců s čísly se kreslí: dva v pohledu pod sebou, jeden v buňce dvojice.
    var numberColumns = 2
    /// Šířka sloupců, které se kreslí vlevo: sloupec ikonky, čísla a znak změny.
    var gutterWidth: Double = 0 {
        didSet {
            textContainerInset = NSSize(width: gutterWidth, height: 2)

        }
    }

    /// Podpis posledně složeného obsahu — z něj se pozná, že se text skládat nemusí.
    private var signature: String?

    /// Blok, který se má vykreslit. Text se skládá **jednou** a drží se rozsahy řádků, aby se
    /// pozadí a čísla daly kreslit bez druhého průchodu textem.
    ///
    /// **Skládá se jen tehdy, když se obsah opravdu změnil**, a je to podstatné:
    /// `setAttributedString` zruší rozdělaný výběr, a `updateNSView` se volá při každém
    /// překreslení — tedy i když myš přejede na jiný řádek a přesune se pilulka na komentář.
    /// Bez téhle podmínky se výběr rušil při každém hnutí myší (nahlášené při zkoušení #157).
    func show(_ block: DiffBlock, language: Language?, palette: SyntaxPalette, signature: String) {
        guard self.signature != signature else { return }
        self.signature = signature
        lines = block.lines
        lineRanges = []

        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let result = NSMutableAttributedString()
        for (index, line) in block.lines.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: [.font: font])) }
            let start = result.length
            append(line, to: result, font: font, language: language, palette: palette)
            lineRanges.append(NSRange(location: start, length: result.length - start))
        }
        textStorage?.setAttributedString(result)
        needsDisplay = true
    }

    /// Jeden řádek obarvený stejnými pravidly jako v diffu — jedno místo, kde se rozhoduje, co je
    /// klíčové slovo. Poznámka `git`u (`meta`) je ztlumená, jako v `DiffLineView`.
    private func append(
        _ line: DiffLine,
        to result: NSMutableAttributedString,
        font: NSFont,
        language: Language?,
        palette: SyntaxPalette
    ) {
        guard let language, line.kind != .meta else {
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if line.kind == .meta { attributes[.foregroundColor] = NSColor.tertiaryLabelColor }
            result.append(NSAttributedString(string: line.text, attributes: attributes))
            return
        }
        for run in SyntaxHighlighter.runs(of: line.text, in: language) {
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if let color = palette.color(for: run.kind) {
                attributes[.foregroundColor] = NSColor(color)
            }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
    }

    // MARK: - Geometrie řádků

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
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
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
    /// pozadí kreslené před `super.draw` vidět jsou). Text ani gutter se nepřekrývají: text je
    /// odsazený o `textContainerInset.width`, tedy přesně o šířku gutteru.
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

    /// Výška jednoho řádku textu. U nezalamovaného sloupce z ní vyjde celá výška bloku.
    var singleLineHeight: Double {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        return (layoutManager?.defaultLineHeight(for: font) ?? font.boundingRectForFont.height)
            + textContainerInset.height
    }

    /// Sloupec pohledu vedle sebe: **nezalamuje** a posouvá se vodorovně, aby zůstal zarovnaný
    /// s protějškem (viz `DiffPairBlockView`).
    static func pairColumn() -> DiffTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        container.widthTracksTextView = false
        layout.addTextContainer(container)

        let textView = DiffTextView(frame: NSRect.zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isHorizontallyResizable = true
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

    static func sign(of kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .context, .meta: ""
        }
    }
}
