import AppKit
import Testing

@testable import PRism

/// Kolik řádků se v sheetu nevejde na šířku (#417) — **proti skutečnému layout manageru**, ne proti
/// vlastní aritmetice.
///
/// Patička sheetu s hunkem tvrdí `1 řádek z 21 se nevešel na šířku`, a je to tvrzení o **kresbě**:
/// spočítá se z šířky a šířky znaku (`Policy.codeSheetOverflow`), kdežto lámat řádky bude TextKit.
/// Dvě pravdy o jedné šířce jsou přesně to, co #236 stálo přetékající blok kódu, takže se to musí
/// potkat — a **přes pásmo šířek**, protože u jedné jediné šířky projde i výpočet, který je
/// o odsazení vedle.
///
/// Co se dá pokazit potichu: zapomenutý `lineFragmentPadding` (2×5 bodů) nebo odsazení kontejneru
/// (2×8) — u širokého sheetu se to na počtu neprojeví vůbec a u úzkého o jeden dva řádky, tedy
/// zrovna v tom čísle, které patička vypisuje.
@Suite("Zalomené řádky v sheetu s kódem")
@MainActor
struct CodeSheetWrappingTests {
    /// Řádky s **známými délkami** okolo kapacity, ne fixture: testuje se hranice, takže je potřeba
    /// mít vedle sebe řádek o kapacitě a řádek o kapacitě + 1. Text hunku samotný se testuje jinde.
    private func code(lengths: [Int]) -> String {
        lengths.map { String(repeating: "x", count: $0) }.joined(separator: "\n")
    }

    /// Kolik řádků TextKit doopravdy zalomil: fragmentů sazby je víc než jeden právě u těch řádků,
    /// které se nevešly.
    ///
    /// Rozsahy se počítají **z délek, ne hledáním podřetězce**: `"xxxxxxxxxx"` je podřetězcem
    /// dlouhého řádku, takže by `range(of:)` u krátkého řádku vrátil kus toho dlouhého a počet by
    /// vyšel náhodou.
    ///
    /// **Overlay scroller schválně**: v legacy stylu si svislý scroller ukusuje ze šířky textu
    /// **17 bodů** (změřeno: `contentView.bounds.width` 1 163 proti 1 180), tedy necelé dva znaky.
    /// Tady se měří ta aritmetika, kterou má i tabulka v návrhu — na čem je ten rozdíl vidět
    /// a proč se s ním nepočítá, je u `Policy.codeSheetOverflow`.
    private func wrappedByLayoutManager(lengths: [Int], width: CGFloat) throws -> Int {
        let text = code(lengths: lengths)
        let scroll = SelectableCodeView.makeScrollView()
        scroll.scrollerStyle = .overlay
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: 2_000)
        let textView = try #require(scroll.documentView as? NSTextView)
        textView.frame = scroll.frame
        textView.textStorage?.setAttributedString(
            SelectableCodeView.attributed(text, language: nil, colorScheme: .dark)
        )
        let layout = try #require(textView.layoutManager)
        let container = try #require(textView.textContainer)
        layout.ensureLayout(for: container)

        var wrapped = 0
        var start = 0
        for length in lengths {
            var fragments = 0
            let glyphs = layout.glyphRange(
                forCharacterRange: NSRange(location: start, length: length),
                actualCharacterRange: nil
            )
            layout.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in fragments += 1 }
            if fragments > 1 { wrapped += 1 }
            // +1 za zlom řádku; text je ASCII, takže znaky a UTF-16 jednotky si odpovídají.
            start += length + 1
        }
        return wrapped
    }

    /// **Pásmo šířek**, ne jedna: rozejde se to jen v pásmu — u jedné šířky projde i výpočet,
    /// kterému chybí odsazení.
    @Test(
        "Spočítaná zalomení sedí s tím, co zalomí TextKit",
        arguments: [560.0, 700.0, 820.0, 1_000.0, 1_180.0, 1_360.0] as [CGFloat]
    )
    func matchesTheLayoutManager(width: CGFloat) throws {
        let capacity = Policy.codeSheetCharacters(
            width: width,
            characterWidth: SelectableCodeView.characterWidth
        )
        // Okolo kapacity, ať se pozná i chyba o jeden znak: přesně kapacita se vejde, o znak víc ne.
        let lengths = [10, capacity, capacity + 1, capacity * 2, 1]

        let computed = Policy.codeSheetOverflow(
            code: code(lengths: lengths),
            width: width,
            characterWidth: SelectableCodeView.characterWidth
        )

        let real = try wrappedByLayoutManager(lengths: lengths, width: width)
        #expect(
            computed?.wrapped == real,
            "Při \(width) bodech spočítáno \(computed?.wrapped ?? 0), zalomeno \(real)."
        )
        #expect(computed?.total == lengths.count)
    }

    /// A obráceně: text, který se celý vejde, nesmí mít v patičce věty. `nil`, ne nula.
    @Test("Text, který se vejde, TextKit nezalomí a patička mlčí")
    func agreesOnTextThatFits() throws {
        let lengths = [10, 20, 30]

        #expect(Policy.codeSheetOverflow(
            code: code(lengths: lengths),
            width: 1_180,
            characterWidth: SelectableCodeView.characterWidth
        ) == nil)
        #expect(try wrappedByLayoutManager(lengths: lengths, width: 1_180) == 0)
    }
}
