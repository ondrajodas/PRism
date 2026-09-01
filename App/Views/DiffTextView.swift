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

    /// Čím byl obarvený posledně složený text. Spolu s `lines` je to celý podpis obsahu, ze kterého
    /// se pozná, že se skládat nemusí — do #393 to byl řetězec s **hashem** všech řádků, a ten se
    /// počítal při každém průchodu `updateNSView` (viz `DiffBlockDrawing`).
    private var style: DiffBlockStyle?

    /// Kolikrát tomuhle bloku přišla aktualizace ze SwiftUI — počítá to `DiffCodeBlockView`
    /// (pohled pod sebou); ve sloupci dvojice zůstává nula, protože tam aktualizace dostává
    /// kontejner. **Vedle `typesettings` schválně**: samotná nula u sazby by mohla znamenat i to,
    /// že aktualizace nepřišla vůbec (#393).
    private(set) var updates = 0

    /// Kolikrát se do view **nasadil blok** — tedy kolikrát průchod `updateNSView` prošel stráží
    /// z `DiffBlockDrawing` a zaplatil práci lineární v délce bloku (rámečky řádků, u dvojice ještě
    /// pole a množiny navíc). **Tohle je to číslo, o které u #393 šlo**: sazba se neopakovala ani
    /// předtím (držel ji podpis obsahu), kdežto nasazení se dělo při každém přepočtu geometrie.
    private(set) var mounts = 0

    /// Kolikrát view **doopravdy** složilo text.
    ///
    /// **Počitadlo, ne dojem** (#393): že se nezměněný blok nesází znovu, se v okně jinak poznat
    /// nedá — výsledek přesázení vypadá stejně jako to, co tam bylo, jen zahodí rozdělaný výběr
    /// a stojí desítky milisekund. Čtou to `DiffBlockUpdateTests` (nezměněný blok) a sonda
    /// projíždění (`IdleDiffSpinProbe`).
    private(set) var typesettings = 0

    /// Přišla aktualizace ze SwiftUI. Volá to `DiffCodeBlockView` **před** svou stráží, protože
    /// právě o průchody, které za ni nedojdou, tady jde.
    func noteUpdate() {
        updates += 1
    }

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
    /// **Porovnává se to na řádcích, ne na jejich hashi** (#393). Volající drží tentýž blok, jaký
    /// posledně nasadil, takže `Array.==` vrátí na identitě úložiště hned — a hash celého bloku,
    /// který tu byl do #393, přečetl znaky všech řádků pokaždé znovu. Šířka v tom klíči **není**
    /// schválně: zalomení textu se s ní mění, ale sazba je pořád tatáž, a přesázení by sebralo výběr
    /// při každém tažení za hranu okna (viz `DiffBlockDrawing`).
    ///
    /// **Text vzniká jako jeden řetězec a barvy se do něj dopisují** (#275), ne jako řetězec
    /// slepený z run. Do #275 se za každý run vyrobil `NSAttributedString` a připojil — u velkého
    /// diffu 16 000 objektů na jedno projetí, tedy **22,2 ms z 86** na 27 blocích. Jeden řetězec
    /// a `addAttribute` na rozsah dělá totéž za **4,5 ms**; text i atributy z toho vyjdou znak po
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
        style: DiffBlockStyle,
        words: () -> WordDiff.Spans
    ) {
        mounts += 1
        guard self.style != style || lines != block.lines else { return }
        self.style = style
        lines = block.lines
        typesettings += 1

        let composed = Self.compose(
            block.lines,
            words: words(),
            language: style.language,
            palette: style.palette,
            // Dotaz je součástí klíče (`DiffBlockStyle.search`), takže se sem dojde i tehdy, když se
            // změnilo **jen** hledané slovo — a přesázet se v tu chvíli musí, jinak by v okně
            // zůstalo zvýraznění toho předchozího.
            search: style.search
        )
        lineRanges = composed.ranges
        textStorage?.setAttributedString(composed.text)
        // Nový text = nová šířka nejdelšího řádku, takže zapamatovaná neplatí.
        rememberedTextWidth = nil
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
        palette: SyntaxPalette,
        search: DiffSearchHighlight = .none
    ) -> (text: NSAttributedString, ranges: [NSRange]) {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // Šest převodů na blok místo jednoho na run (#275, od #393 i barva textu) — viz `SyntaxColors`.
        let colors = SyntaxColors(palette)
        let ranges = lineRanges(of: lines)
        // **Barva obyčejného textu se nasazuje na celý text** (#393), obarvení syntaxe ji pak přes
        // svoje rozsahy přepíše. Bez ní kreslí TextKit chybějící `.foregroundColor` **černě** —
        // v tmavém režimu tedy identifikátory černé na tmavém pozadí; podrobnosti u `SyntaxColors.plain`.
        let result = NSMutableAttributedString(
            string: lines.map(\.text).joined(separator: "\n"),
            attributes: [.font: font, .foregroundColor: colors.plain]
        )
        for (index, line) in lines.enumerated() {
            colorize(line, in: result, over: ranges[index], language: language, colors: colors)
            highlight(words[index] ?? [], of: line, in: result, from: ranges[index].location)
            // **Hledání jde naposled, tedy nad word-level vrstvou** (#152), a to pořadí je
            // rozhodnutí: je to jediná z těch vrstev, kterou si člověk zapnul sám a která zhasne,
            // jak zavře pruh. Barva písma zůstává ze syntaxe, mění se jedině podklad.
            highlightSearch(search, of: line, in: result, from: ranges[index].location)
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

    /// Výsledek hledání jako **třetí vrstva nad** hotovým textem (#152).
    ///
    /// Tentýž tvar jako word-level vrstva nad tímhle řádkem, a ze stejného důvodu **nesmí do
    /// `SyntaxRunCache`** (#153): zvýraznění závisí na dotazu, kdežto cache je klíčovaná
    /// `(text řádku, jazyk)` — tentýž řádek by z ní při jiném dotazu vytáhl cizí zvýraznění.
    ///
    /// Kde dotaz na řádku sedí, rozhoduje **`DiffSearch.ranges`, tedy tatáž funkce, ze které se
    /// počítá počet výskytů v pruhu**. Dvě kopie porovnávání by znamenaly, že pruh umí tvrdit `17`
    /// a v textu svítí šestnáct podkladů.
    private static func highlightSearch(
        _ search: DiffSearchHighlight,
        of line: DiffLine,
        in result: NSMutableAttributedString,
        from start: Int
    ) {
        guard let query = search.query, query.isActive else { return }
        let spans = DiffSearch.ranges(in: line.text, query: query)
        guard !spans.isEmpty else { return }
        for (occurrence, span) in spans.enumerated() {
            let range = NSRange(span, in: line.text)
            let target = NSRange(location: start + range.location, length: range.length)
            // Tatáž pojistka jako u word-level vrstvy: rozsah patří textu, ze kterého se počítal,
            // takže mimo složený řetězec sáhnout nemá jak — a kdyby přece, je zvýraznění to jediné,
            // o co se přijde.
            guard NSMaxRange(target) <= result.length else { continue }
            let color = search.isCurrent(line, occurrence: occurrence)
                ? Self.currentSearchBackground
                : Self.searchBackground
            result.addAttribute(.backgroundColor, value: color, range: target)
        }
    }

    /// Podklad výskytu a toho aktuálního. **`NSColor` z palety, jeden převod na proces** — tentýž
    /// vzorec jako u word-level pozadí o pár řádků výš (#275: šest převodů na blok, ne jeden na run).
    private static let searchBackground = NSColor(Palette.searchHit)
    private static let currentSearchBackground = NSColor(Palette.searchHitCurrent)

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
        if rect.height == 0 { rect.size.height = FontMetric.shared.lineHeight(of: font ?? .systemFont(ofSize: 12)) }
        return rect
    }

    /// Rámečky všech řádků. Volá se po layoutu, takže se dá poslat do SwiftUI.
    ///
    /// **Jedním průchodem přes fragmenty, ne dotazem na každý řádek** (#476). Do #476 se pro každý
    /// řádek volalo `boundingRect(forGlyphRange:in:)`, a to je u `NSLayoutManager` drahá cesta:
    /// ve vzorku z přepínání tabů drželo `lineFrames()` **697 vzorků z 1 519**, které stál celý
    /// `updateNSView` bloku — a uvnitř z toho `_rectArrayForRange` →
    /// `_insertionPointHelperForCharacterAtIndex` **653**. Fragmenty přitom layout manager umí
    /// vydat **naráz**, a protože se řádky dělí zalomením, patří každý fragment právě jednomu
    /// řádku; zalomený řádek si své fragmenty sjednotí.
    ///
    /// **Řádek, na který se v průchodu nedostane, se dopočítá po starém.** Počet vrácených rámečků
    /// musí sedět na počet řádků — je z nich geometrie gutteru (#252) i kotvy pro ⇧ klik
    /// (`DiffRowFrames`), takže chybějící řádek by byl tichá díra v obojím.
    func lineFrames() -> [(line: DiffLine, index: Int, rect: NSRect)] {
        guard let layoutManager, let textContainer, !lines.isEmpty else { return [] }
        let origin = textContainerOrigin
        // **Odsazení kontejneru se musí odečíst.** `usedRect` fragmentu ho na obou koncích
        // **obsahuje**, kdežto `boundingRect(forGlyphRange:)` vrací rámeček samotných glyfů —
        // rozdíl je přesně `lineFragmentPadding` a projevil by se posunutou pilulkou na komentář
        // a kotvou pro ⇧ klik o pět bodů vedle. Chytil to `DiffLineFramesTests`.
        let padding = textContainer.lineFragmentPadding
        var rects = [NSRect?](repeating: nil, count: lines.count)
        // **Zalomený řádek je vodorovně široký jako kontejner**, ne jako jeho nejdelší fragment —
        // tak to vrací `boundingRect(forGlyphRange:)`, a rámečky se nesmí lišit ani tímhle. Proto
        // se u řádku s víc fragmenty bere sjednocení **fragmentů**, u nezalomeného **použité části**.
        var fragments = [NSRect?](repeating: nil, count: lines.count)
        var counts = [Int](repeating: 0, count: lines.count)
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { fragment, used, _, glyphRange, _ in
            let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard let index = self.lineIndex(atCharacter: characters.location) else { return }
            rects[index] = rects[index].map { $0.union(used) } ?? used
            fragments[index] = fragments[index].map { $0.union(fragment) } ?? fragment
            counts[index] += 1
        }
        return lines.indices.compactMap { index in
            guard var rect = rects[index] else {
                // Nedopočítaný řádek po staru — radši dotaz navíc než chybějící rámeček.
                return frame(ofLine: index).map { (line: lines[index], index: index, rect: $0) }
            }
            if counts[index] > 1, let wide = fragments[index] {
                rect.origin.x = wide.minX
                rect.size.width = wide.width
            }
            rect.origin.x += origin.x + padding
            rect.size.width = max(rect.width - padding * 2, 0)
            rect.origin.y += origin.y
            // Prázdný řádek nemá glyfy, takže by vyšel nulově vysoký — vezme se výška písma.
            if rect.height == 0 {
                rect.size.height = FontMetric.shared.lineHeight(of: font ?? .systemFont(ofSize: 12))
            }
            return (line: lines[index], index: index, rect: rect)
        }
    }

    /// Do kterého řádku patří znak na téhle pozici.
    ///
    /// Rozsahy jdou po sobě a mezi nimi je právě jedno zalomení, takže úsek
    /// `[začátek_i, začátek_i+1)` pokrývá řádek i **včetně** jeho zalomení — a hledá se tedy
    /// poslední řádek, který začíná nejvýš na téhle pozici. Půlením, ne procházením: fragmentů je
    /// u dlouhého bloku tolik co řádků a lineární hledání by z toho udělalo kvadrát.
    private func lineIndex(atCharacter location: Int) -> Int? {
        guard !lineRanges.isEmpty, location >= 0 else { return nil }
        var low = 0
        var high = lineRanges.count - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if lineRanges[middle].location <= location {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
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
            let top = NSRect(x: 0, y: rect.minY, width: gutterWidth, height: FontMetric.shared.boundingHeight(of: font) + 2)

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
        // **Jen při skutečné změně**, jako ve `fitContainerWidth` (nález z review na #422): jiná
        // šířka kontejneru je jiné zalomení, tedy jiná šířka textu — ale měření na tutéž šířku
        // (a ve sloupci dvojice na neomezenou) zapamatovanou hodnotu zneplatnit nemá.
        let size = containerSize(forWidth: width)
        if textContainer.size != size {
            textContainer.size = size
            rememberedTextWidth = nil
        }
        layoutManager.ensureLayout(for: textContainer)
        return layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2
    }

    /// Šířka, na které je z bloku vidět **všechno** — gutter plus nejdelší vysázený řádek.
    ///
    /// **Je to šířka pro kreslení, ne pro sazbu**, a v tom je ten rozdíl: text se kreslí od
    /// `textContainerOrigin.x`, tedy až za gutterem, takže dokument široký jen jako `usedRect`
    /// ořeže konec nejdelšího řádku právě o gutter (ve split pohledu 84 pt).
    ///
    /// **`sizeToFit()` na to nestačí a je to změřené, ne odhad** (#422): view složené z kódu má
    /// `maxSize` `(0, 0)` a nikdo ji nenastavuje, takže `sizeToFit()` vrátí rámec **nulové** šířky.
    /// Dokument sloupce z něj proto vycházel vždycky přesně tak široký jako plocha — nebylo co
    /// rolovat a autohide vodorovný pruh schoval i tam, kde kód za okraj přetékal.
    ///
    /// Ptá se na ni **sloupec dvojice**; v zalamovacím bloku vyjde přibližně šířka view (text se
    /// zalomí do kontejneru), takže o přetečení tam neříká nic — a není co, nezalomený řádek tam
    /// není.
    ///
    /// **Je to nejdelší řádek téhle půlky, ne bloku**, a se sousedkou se nesdílí: každá strana má
    /// svou rolovací plochu, takže sdílená šířka by u půlky s krátkými (nebo šrafovanými) řádky
    /// znamenala pruh, který jede do prázdna. Zarovnání řádků na tom nevisí — to drží **výška**
    /// (`height(ofRows:)`) a prázdný řádek na chybějící straně, ne šířka dokumentu.
    var naturalWidth: Double {
        gutterWidth + laidOutWidth()
    }

    /// Šířka vysázeného textu podle layout manageru. **Pamatuje se** (#224): ptá se na ni každý
    /// dotaz na výšku bloku dvojice, tedy `sizeThatFits` při **každém** přepočtu geometrie (#393),
    /// a je to funkce vysázeného textu a šířky kontejneru — obojí ji zahazuje. Změřeno: spočítat ji
    /// stojí totéž co dřívější `sizeToFit()` (39,6 proti 40,1 ms na 54 stranách, jedno sezení),
    /// z paměti 0,003 ms.
    ///
    /// **Zahazuje ji `show(…)`, tedy jediné místo, kde se v aplikaci text mění.** Kdo sáhne na
    /// `textStorage` mimo něj, dostane hodnotu z minula — dělá to jedno měřidlo v testech a je to
    /// tam napsané.
    ///
    /// Hodnota je pravdivá jen nad **vysázeným celým blokem**; `ensureLayout(for:)` to zajišťuje
    /// a `allowsNonContiguousLayout` je u těchhle sloupců `false` (změřeno). Že se nejdelší řádek
    /// najde i na konci šedesátiřádkového bloku, drží `DiffPairScrollerTests`.
    ///
    /// **Ptá se po řádcích, ne `usedRect(for:)` na celý kontejner** — a je to oprava vady, se kterou
    /// #422 vyšlo (nahlášená jako „moc velký posuvník, který jede do prázdna“). `usedRect` totiž
    /// **umí zahrnout extra line fragment**: to je řádek za posledním `\n`, který AppKit vysází
    /// tehdy, když text končí zalomením — tedy vždycky, když je **poslední řádek půlky prázdný**,
    /// a prázdná je každá šrafovaná (chybějící) strana dvojice. Jeho rámec je celá šířka kontejneru,
    /// a ta je tu neomezená, takže se zaokrouhlí na **10 000 000**; z půlky s třemi šrafovanými
    /// řádky pak vyšla `naturalWidth` 10 000 084 místo 94 — proti okýnku 449,5 b je to
    /// `knobProportion` **4,49 × 10⁻⁵**, tedy vlas u levého okraje a rolování do prázdna.
    ///
    /// **Jestli se ten fragment do `usedRect` započítá, se řídit nedá** (změřeno u #422): nad
    /// samotným sloupcem vyšla 34,1, nad tímtéž sloupcem v `DiffPairBlockContainer` 10 000 000,
    /// a minimálně to jde vyrobit tak, že se po jeho vysázení zneplatní layout. Odsud to „někdy“
    /// v hlášení. `enumerateLineFragments(forGlyphRange:)` extra fragment **nevydá vůbec**, takže
    /// se nemá jak vloudit — a `usedRect` každého fragmentu je to, co se v něm doopravdy vysázelo.
    ///
    /// Nad blokem, kterému poslední řádek prázdný není, vychází **týž počet jako dřív** (změřeno
    /// znak po znaku: 82,3 / 98,4 / 238,4 / 347,5), takže geometrie odsouhlasená u #422 se nemění.
    /// Výška zůstává na `usedRect(for:)` schválně: extra fragment je tam **skutečný řádek** bloku
    /// (prázdný řádek souboru se kreslí i s číslem), takže se do výšky započítat má.
    ///
    /// Cena je 0,005 ms na šedesátiřádkovém bloku proti 0,0001 ms za `usedRect` — pamatuje se to,
    /// takže se platí jednou na obsah, a proti sazbě, kterou si `ensureLayout` vynutí, je to nic.
    private func laidOutWidth() -> Double {
        if let rememberedTextWidth { return rememberedTextWidth }
        guard let layoutManager, let textContainer else { return 0 }
        layoutManager.ensureLayout(for: textContainer)
        var width = 0.0
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: textContainer)) {
            _, used, _, _, _ in
            // **Převod je explicitní** (nález z review na #422): geometrie fragmentu je `CGFloat`,
            // cache drží `Double`. Implicitní převod tady sice je (SE-0307), ale právě on se ztrácí
            // v rozkladu `#expect` — a pak se dvě identická čísla nerovnají, viz `docs/testovani.md`.
            width = max(width, Double(used.maxX))
        }
        rememberedTextWidth = width
        return width
    }

    /// Zapamatovaná šířka vysázeného textu, nebo `nil`, když se od poslední sazby (či změny
    /// kontejneru) neplatí.
    private var rememberedTextWidth: Double?

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
    ///
    /// Metrika je z `FontMetric` (#407). Do té doby to byla dvojice: `defaultLineHeight` z layout
    /// manageru view, a když ho view ještě nemělo, výška obalového rámce — tedy **dvě různá čísla
    /// pro jednu výšku řádku**, mezi kterými rozhodovalo to, jak daleko je view v sestavování.
    /// Jedno měřidlo tu volbu ruší; hodnota je ta z layout manageru, protože podle ní se sází.
    var singleLineHeight: Double {
        FontMetric.shared.lineHeight(of: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular))
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
        rememberedTextWidth = nil
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
    ///
    /// **`isHorizontallyResizable` je vypnuté, a to je celá oprava rolování z #422.** Zapnuté
    /// znamená „šířku si spočítám sám“ — a AppKit ji počítá z `usedRect`, který o gutteru neví,
    /// takže rámec, který mu nastaví kontejner (`layoutColumns()`), **přepíše zpátky na šířku
    /// plochy** vždycky, když se do ní vejde samotný text. Změřeno: sloupec s dvanácti znaky
    /// v poloviční šířce 129,5 b má text nakreslený do 190,4 b, a dokument z toho vyšel 129,5 —
    /// tedy nebylo co rolovat a autohide vodorovný pruh schoval. `sizeToFit()` je tatáž slepota
    /// (vrací nulu, dokud `maxSize` nikdo nenastaví).
    ///
    /// Šířku proto drží **kontejner** a jediný, kdo ji umí spočítat, je tenhle typ (`naturalWidth`)
    /// — je to tatáž úvaha jako u výšky v #236: kdo kreslí, ten měří.
    static func pairColumn() -> DiffTextView {
        let textView = textKit1()
        textView.textContainer?.size = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
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
