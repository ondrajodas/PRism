import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Text v `CodeTextSheet`u — skládá ho `SelectableCodeView.attributed` a je to jediné místo
/// v okně, kde se kód sází **jednolitě** a přitom obarvuje po řádcích (#295).
///
/// Testuje se výsledný `NSAttributedString`, ne kresba: je to `static func` nad textem, takže se
/// dá zavolat bez okna.
@Suite("Text v sheetu s kódem")
@MainActor
struct SelectableCodeTextTests {

    /// Do #295 se dělilo `split(separator: "\n")`, takže text s `CRLF` zůstal **jeden** řádek —
    /// obarvoval se jako jeden a celý jeho objem šel do `SyntaxRunCache` jako **jeden klíč**,
    /// přitom cache je klíčovaná textem řádku (#153, #224).
    @Test("Text s CRLF se sází po řádcích, ne jako jeden řádek")
    func splitsCRLFIntoLines() {
        let code = "let a = 1\r\nlet b = 2\r\nlet c = 3"

        let attributed = SelectableCodeView.attributed(code, language: Language(path: "x.swift"), colorScheme: .dark)

        // Sazba vkládá mezi řádky `\n`, takže dva zlomy znamenají tři řádky.
        #expect(TextLines.all(attributed.string).count == 3)
    }

    /// Tentýž kód se `CRLF` a s `LF` musí dát **tentýž** text — to je ta věta „na `LF` vstupech se
    /// nic nezměnilo“, jen z druhé strany.
    @Test("CRLF a LF dají stejný text")
    func typesetsCRLFSameAsLF() {
        let fromCRLF = SelectableCodeView.attributed(
            "let a = 1\r\n\r\nlet b = 2\r\n",
            language: Language(path: "x.swift"),
            colorScheme: .dark
        )
        let fromLF = SelectableCodeView.attributed(
            "let a = 1\n\nlet b = 2\n",
            language: Language(path: "x.swift"),
            colorScheme: .dark
        )

        #expect(fromCRLF.string == fromLF.string)
    }

    /// Prázdné řádky v kódu drží strukturu — bez nich by se vložený text rozešel s originálem.
    @Test("Prázdné řádky zůstávají")
    func keepsEmptyLines() {
        let attributed = SelectableCodeView.attributed(
            "let a = 1\r\n\r\n\r\nlet b = 2",
            language: Language(path: "x.swift"),
            colorScheme: .dark
        )

        #expect(attributed.string == "let a = 1\n\n\nlet b = 2")
    }

    /// **Bez známého jazyka se text neskládá po řádcích vůbec** (#214, kvůli ceně) — takže tam
    /// `CR` projde do textu tak, jak přišel. Je to tady zapsané schválně: sheet s logem chodí
    /// touhle cestou (od #417 s `language: nil`, dřív s jménem checku místo cesty) a `NSTextView`
    /// `CR` jako zlom zobrazí sám.
    @Test("Bez známého jazyka se text nedělí, jde jednolitě")
    func keepsUnknownLanguageTextIntact() {
        let code = "řádek jedna\r\nřádek dva"

        let attributed = SelectableCodeView.attributed(code, language: Language(path: "job.log"), colorScheme: .dark)

        #expect(attributed.string == code)
    }

    /// **Žádný znak bez barvy** (#393) — tatáž vada jako v bloku diffu, protože je to tentýž
    /// mechanismus: chybějící `.foregroundColor` se v atributovaném řetězci kreslí **černě**, ne
    /// „jako okolí“. V tmavém režimu byl proto hunk v sheetu černý na tmavém všude, kde nešlo
    /// o klíčové slovo, řetězec nebo číslo — a **celý** u souboru, kterému `Language` nerozumí
    /// (tedy i u logu, který touhle cestou chodí vždycky).
    @Test("Text v sheetu má barvu i tam, kde se neobarvuje syntaxe")
    func coloursEveryCharacter() {
        for (label, path) in [("se známým jazykem", "x.swift"), ("bez jazyka", "job.log")] {
            let attributed = SelectableCodeView.attributed(
                "let total = Version20260729;\nlet b = 2",
                language: Language(path: path),
                colorScheme: .dark
            )
            var uncoloured: [String] = []
            let whole = NSRange(location: 0, length: attributed.length)
            attributed.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
                guard value == nil else { return }
                uncoloured.append((attributed.string as NSString).substring(with: range))
            }
            #expect(uncoloured.isEmpty, "\(label): bez barvy zůstalo \(uncoloured)")
        }
    }

    /// A ta barva je **z návrhu** (`--ink`, tedy `Palette.ink`), stejně jako v bloku diffu — jeden
    /// token pro obojí, aby se kód v sheetu a v diffu nerozešel.
    @Test("Obyčejný text má barvu textu z palety")
    func paintsPlainTextWithTheInkColour() {
        let attributed = SelectableCodeView.attributed("řádek logu", language: Language(path: "job.log"), colorScheme: .dark)
        let whole = NSRange(location: 0, length: attributed.length)

        var colours: Set<NSColor> = []
        attributed.enumerateAttribute(.foregroundColor, in: whole) { value, _, _ in
            if let colour = value as? NSColor { colours.insert(colour) }
        }
        #expect(colours == [NSColor(Palette.ink)])
    }
}
