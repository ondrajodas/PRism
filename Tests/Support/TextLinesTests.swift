import Testing

@testable import PRism

/// Dělení na řádky výčtem — je to čistá funkce a je to **jediné** místo, kde se rozhoduje, co je
/// řádek, takže tenhle výčet je zároveň zadání pro `DiffParser`, `FileExpansion`, `MarkdownParser`,
/// rozbor hlaviček `gh -i` i konec logu.
///
/// Proč vyčerpávající výčet a ne dva případy: past, kvůli které to vzniklo (#295), je **tichá**.
/// `split(separator: "\n")` na textu s `CRLF` nerozdělí vůbec, takže z celého vstupu zbyde jeden
/// řádek — a všechno nad tím se pak chová jako by data byla v pořádku, jen jich je málo.
@Suite("TextLines")
struct TextLinesTests {

    // MARK: - Zakončení řádků

    /// Tohle je celé #295 na jednom řádku. `"\r\n"` je ve Swiftu **jeden `Character`**, takže
    /// `split(separator: "\n")` na `CRLF` nerozdělí — vrátí jeden prvek.
    @Test("CRLF dělí řádky, ne slepí do jednoho")
    func splitsCRLF() {
        #expect(TextLines.all("alfa\r\nbeta\r\ngama") == ["alfa", "beta", "gama"])
        // Pro srovnání, ať je v testu vidět to, proti čemu se to píše.
        #expect("alfa\r\nbeta\r\ngama".split(separator: "\n").count == 1)
    }

    @Test("LF, CRLF i samotné CR dávají tentýž výsledek", arguments: ["\n", "\r\n", "\r"])
    func splitsEveryTerminator(_ terminator: String) {
        #expect(TextLines.all("alfa\(terminator)beta") == ["alfa", "beta"])
    }

    @Test("Zakončení řádku v textu nezůstane")
    func dropsTerminatorFromLines() {
        // Kdyby `CR` v textu zůstal, nesla by ho i obarvení a klíče do `SyntaxRunCache` (#153, #224)
        // — a v sazbě by z něj byl prázdný řádek pod každým řádkem kódu.
        #expect(TextLines.all("alfa\r\nbeta").joined() == "alfabeta")
    }

    @Test("Míchaná zakončení v jednom textu se rozdělí všechna")
    func splitsMixedTerminators() {
        #expect(TextLines.all("alfa\nbeta\r\ngama\rdelta") == ["alfa", "beta", "gama", "delta"])
    }

    /// **Vědomé rozhodnutí, ne mezera** (#295): `Character.isNewline` je pravda i pro tyhle znaky,
    /// ale `git` je bere jako **obsah** řádku. Rozdělit se na nich znamená vyrobit řádek, který
    /// v souboru není — a u diffu tím posunout čísla všech řádků pod ním.
    @Test(
        "Unicode oddělovače uvnitř řádku řádek nedělí",
        arguments: ["\u{2028}", "\u{2029}", "\u{85}", "\u{0B}", "\u{0C}"]
    )
    func keepsUnicodeSeparatorsInsideLine(_ separator: String) {
        #expect(Character(separator).isNewline, "předpoklad testu: `isNewline` je na tomhle pravda")
        #expect(!Character(separator).isLineTerminator)
        #expect(TextLines.all("alfa\(separator)beta") == ["alfa\(separator)beta"])
    }

    /// `String.singleLine` naopak `isNewline` **potřebuje** — sráží cizí text do jednoho popisku
    /// a `U+2028` popisek zalomí. Je to tady, aby ten rozdíl někdo omylem nesrovnal.
    @Test("singleLine srazí i unicode oddělovač, na kterém TextLines nedělí")
    func singleLineStillCollapsesUnicodeSeparators() {
        #expect("alfa\u{2028}beta".singleLine == "alfa beta")
        #expect(TextLines.all("alfa\u{2028}beta").count == 1)
    }

    // MARK: - Prázdné řádky

    @Test("all nechá prázdné řádky i ten poslední za koncovým zakončením")
    func allKeepsEmptyLines() {
        #expect(TextLines.all("alfa\n\nbeta\n") == ["alfa", "", "beta", ""])
        #expect(TextLines.all("alfa\r\n\r\nbeta\r\n") == ["alfa", "", "beta", ""])
    }

    @Test("content sundá prázdný poslední řádek, který vyrobí koncové zakončení")
    func contentDropsTrailingEmptyLine() {
        #expect(TextLines.content("alfa\nbeta\n") == ["alfa", "beta"])
        #expect(TextLines.content("alfa\r\nbeta\r\n") == ["alfa", "beta"])
    }

    /// Sundá se **jeden**, ne všechny — prázdný řádek na konci obsahu je obsah.
    @Test("content sundá jen jeden prázdný řádek, ne prázdný konec obsahu")
    func contentDropsOnlyOneEmptyLine() {
        #expect(TextLines.content("alfa\n\n") == ["alfa", ""])
    }

    @Test("content na textu bez koncového zakončení nic neubere")
    func contentKeepsLastLineWithoutTerminator() {
        #expect(TextLines.content("alfa\nbeta") == ["alfa", "beta"])
    }

    @Test("nonEmpty vynechá prázdné řádky kdekoli")
    func nonEmptySkipsEmptyLines() {
        #expect(TextLines.nonEmpty("alfa\r\n\r\nbeta\r\n") == ["alfa", "beta"])
    }

    // MARK: - Okrajové vstupy

    /// `all` na prázdném textu vydá **jeden prázdný řádek** (tak se chová `split`), kdežto `content`
    /// ho jako koncové zakončení sundá a nevydá nic. Je to schválně: prázdný diff nemá mít
    /// nerozpoznaný řádek a prázdný soubor nemá mít řádek.
    @Test("Prázdný text: all vydá jeden prázdný řádek, content žádný")
    func handlesEmptyText() {
        #expect(TextLines.all("") == [""])
        #expect(TextLines.content("").isEmpty)
        #expect(TextLines.nonEmpty("").isEmpty)
    }

    @Test("Text ze samých zakončení nemá žádný neprázdný řádek")
    func handlesTerminatorsOnly() {
        #expect(TextLines.nonEmpty("\r\n\r\n").isEmpty)
        #expect(TextLines.all("\r\n\r\n") == ["", "", ""])
    }

    @Test("Funguje i nad Substring, ne jen nad String")
    func worksOnSubstring() {
        let text = "hlavička\r\nalfa\r\nbeta"
        let rest = text.dropFirst("hlavička\r\n".count)
        #expect(TextLines.all(rest) == ["alfa", "beta"])
    }
}
