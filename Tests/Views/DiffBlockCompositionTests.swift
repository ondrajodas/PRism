import AppKit
import Testing

@testable import PRism

/// Skládání textu bloku (#275) — že se obarvení trefí na tytéž znaky jako předtím.
///
/// Do #275 vznikal text bloku slepením `NSAttributedString`u za každý run, takže se rozsahy
/// nepočítaly: atribut jel s kusem textu. Od #275 je text **jeden řetězec** a barvy se do něj
/// dopisují na spočítané rozsahy — a spočítaný rozsah se dá spočítat špatně. Přesně to je třída
/// chyby, kterou tenhle soubor hlídá.
///
/// **Znaky mimo ASCII jsou tu jádro věci**, ne ozdoba: `NSAttributedString` měří v UTF-16, takže
/// emoji je **dva** kódy a `count` nad `Character`y by rozsahy posunul. Ověřeno vloženou regresí
/// (`count` místo `utf16.count` v `DiffTextView.lineRanges(of:)`): padnou tři testy — rozsah řádku,
/// obarvený řetězec za emoji a zvýrazněný kus za emoji —, kdežto tytéž případy v ASCII projdou,
/// tedy přesně tak, jak by se ta chyba projevila v okně.
@Suite("Skládání textu bloku")
@MainActor
struct DiffBlockCompositionTests {
    private static let language = Language(path: "Cart.swift")

    private func line(_ text: String, kind: DiffLine.Kind = .context) -> DiffLine {
        DiffLine(kind: kind, oldNumber: 1, newNumber: 1, text: text)
    }

    private func composed(_ lines: [DiffLine], words: WordDiff.Spans = [:]) -> (text: NSAttributedString, ranges: [NSRange]) {
        DiffTextView.compose(lines, words: words, language: Self.language, palette: .intelliJLight)
    }

    /// Rozsah řádku musí vracet **ten** řádek. Kdyby se posunul, obarvení i word-level vrstva by
    /// skončily o pár znaků vedle — a u dlouhého řádku by to nikdo nepoznal.
    @Test("Rozsah řádku ukazuje na jeho text")
    func lineRangesPointAtTheirText() {
        let lines = [
            line("let total = 1"),
            line("let čárka = \"háček\""),
            line("let 🐛 = \"chyba\""),
            line("let 日本 = 2"),
            line(""),
            line("let last = 3"),
        ]
        let (attributed, ranges) = composed(lines)
        let text = attributed.string as NSString

        #expect(ranges.count == lines.count)
        for (index, line) in lines.enumerated() {
            #expect(text.substring(with: ranges[index]) == line.text, "řádek \(index)")
        }
    }

    /// A z druhé strany: složený text je přesně řádky spojené zalomením, nic navíc.
    @Test("Text bloku je řádky spojené zalomením")
    func textIsTheLinesJoined() {
        let lines = [line("let 🐛 = 1"), line("let b = 2")]
        #expect(composed(lines).text.string == "let 🐛 = 1\nlet b = 2")
    }

    /// Obarvení syntaxe **za** znakem mimo ASCII. Řetězec je na řádku poslední, takže posunutý
    /// rozsah se pozná hned: obarví se uvozovka a kus jména místo obsahu řetězce.
    @Test("Řetězec je obarvený i na řádku s emoji")
    func coloursTheStringAfterANonASCIICharacter() throws {
        let lines = [line("let name = \"chyba\""), line("let 🐛 = \"chyba\"")]
        let text = composed(lines).text
        let color = NSColor(SyntaxPalette.intelliJLight.string)

        var painted: [String] = []
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value as? NSColor == color else { return }
            painted.append((text.string as NSString).substring(with: range))
        }
        #expect(painted == ["\"chyba\"", "\"chyba\""])
    }

    /// Totéž pro word-level vrstvu (#153): zvýrazněný kus se počítá z rozsahů v `DiffLine.text`,
    /// takže se do složeného textu překládá přes tentýž offset.
    @Test("Zvýrazněný kus sedí i na řádku s emoji")
    func highlightsTheRewrittenPartAfterAnEmoji() {
        let removed = DiffLine(kind: .removed, oldNumber: 1, newNumber: nil, text: "let 🐛 = amount")
        let added = DiffLine(kind: .added, oldNumber: nil, newNumber: 1, text: "let 🐛 = count")
        let lines = [removed, added]
        let text = composed(lines, words: WordDiff.spans(in: lines)).text

        var painted: [String] = []
        text.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value != nil else { return }
            painted.append((text.string as NSString).substring(with: range))
        }
        #expect(painted == ["amount", "count"])
    }

    /// Poznámka `git`u je ztlumená přes **celý** řádek, ne přes runy — a nesmí přetéct do dalšího.
    @Test("Meta řádek je ztlumený celý a jen on")
    func dimsTheWholeMetaLineOnly() {
        let lines = [line("\\ No newline at end of file", kind: .meta), line("let total = 1")]
        let text = composed(lines).text

        var dimmed: [String] = []
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value as? NSColor == NSColor.tertiaryLabelColor else { return }
            dimmed.append((text.string as NSString).substring(with: range))
        }
        #expect(dimmed == ["\\ No newline at end of file"])
    }

    /// **Žádný znak nesmí zůstat bez barvy** (#393) — a je to ten nejcennější případ v tomhle
    /// souboru, protože chybějící `.foregroundColor` se v atributovaném řetězci nekreslí „jako
    /// okolí“, ale **černě**. V tmavém režimu z toho byly identifikátory černé na tmavém pozadí
    /// (kontrast 1,39), kdežto klíčová slova a řetězce svoji barvu měly — takže to vypadalo jako
    /// vlastnost tématu, ne jako vada.
    ///
    /// Blok je namíchaný schválně: syntaxe, poznámka `git`u, prázdný řádek i znak mimo ASCII.
    @Test("Žádný znak nezůstane bez barvy")
    func coloursEveryCharacter() {
        let lines = [
            line("let total = Version20260729;"),
            line("\\ No newline at end of file", kind: .meta),
            line(""),
            line("let 🐛 = \"chyba\""),
        ]
        let text = composed(lines).text
        var uncoloured: [String] = []
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value == nil else { return }
            uncoloured.append((text.string as NSString).substring(with: range))
        }
        #expect(uncoloured.isEmpty)
    }

    /// Obyčejný text (identifikátory, interpunkce) má barvu **z návrhu** — token `--ink`, tedy
    /// `Palette.ink`. Kontrast téhle barvy nad všemi druhy řádku hlídá `DiffPaletteTests`; tady se
    /// tvrdí to, co tomu měření dosud chybělo: že se ta barva doopravdy nasadí do textu.
    @Test("Obyčejný text má barvu textu z palety")
    func paintsPlainTextWithTheInkColour() {
        let text = composed([line("let total = Version20260729;")]).text
        let ink = NSColor(Palette.ink)

        var painted: [String] = []
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value as? NSColor == ink else { return }
            painted.append((text.string as NSString).substring(with: range))
        }
        // `let` je klíčové slovo, zbytek řádku je obyčejný text.
        #expect(painted == [" total = Version20260729;"])
    }

    /// Soubor bez rozpoznaného jazyka: písmo ano, obarvení syntaxe ne — ale **barvu textu ano**.
    ///
    /// **Změna tvrzení proti #275** (do #393 tu stálo „bez jazyka se nic neobarví“ a měřilo se, že
    /// `.foregroundColor` není nikde). Bylo správné o obarvení a špatné o kresbě: text bez té barvy
    /// vyjde černý, takže soubor, kterému `Language` nerozumí, byl v tmavém režimu celý černý na
    /// tmavém. Zůstává z něj to podstatné — obarvení syntaxe se nedosazuje —, jen se to tvrdí na
    /// barvách runů, ne na jejich nepřítomnosti.
    @Test("Bez jazyka se neobarvuje syntaxe, ale text barvu má")
    func leavesAnUnknownLanguageUnhighlighted() {
        let lines = [line("let total = 1")]
        let text = DiffTextView.compose(lines, words: [:], language: nil, palette: .intelliJLight).text
        var colours: Set<NSColor> = []
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let colour = value as? NSColor { colours.insert(colour) }
        }
        #expect(colours == [NSColor(Palette.ink)])
    }
}
