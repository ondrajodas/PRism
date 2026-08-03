import Foundation
import Testing

@testable import PRism

/// Inline HTML z komentářů na GitHubu. Čisté funkce, nic se nemockuje.
///
/// Vzory pocházejí ze **skutečných** komentářů botů (`linear-code` posílá `<details>`,
/// `<summary>` a `<a href>` do každého linkbacku) — proto se testuje zrovna tohle a ne
/// obecné HTML.
@Suite("MarkdownHTML")
struct MarkdownHTMLTests {
    /// Odkaz musí zůstat **klikatelný**, takže se převádí na Markdown, ne zahazuje.
    @Test("Odkaz se převede na Markdown")
    func convertsAnchors() {
        #expect(
            MarkdownHTML.stripped(#"<a href="https://linear.app/x">AJDA-2222</a>"#)
                == "[AJDA-2222](https://linear.app/x)"
        )
    }

    /// Bot si formát uvozovek vybírá sám a na klikatelnosti odkazu to nemá záležet.
    @Test("Uvozovky u href mohou být jakékoli", arguments: [
        #"<a href="https://x">t</a>"#,
        "<a href='https://x'>t</a>",
        "<a href=https://x>t</a>",
    ])
    func acceptsEveryQuotingStyle(html: String) {
        #expect(MarkdownHTML.stripped(html) == "[t](https://x)")
    }

    @Test("Odkaz s dalšími atributy se převede taky")
    func convertsAnchorsWithOtherAttributes() {
        #expect(
            MarkdownHTML.stripped(#"<a class="x" href="https://x" rel="nofollow">t</a>"#)
                == "[t](https://x)"
        )
    }

    /// Odkaz bez textu by v Markdownu zmizel úplně.
    @Test("Odkaz bez textu zůstane jako URL")
    func keepsATextlessLink() {
        #expect(MarkdownHTML.stripped(#"<a href="https://x"><img src="y"></a>"#) == "https://x")
    }

    @Test("Ostatní tagy jdou pryč, text zůstává")
    func dropsOtherTags() {
        #expect(MarkdownHTML.stripped("<p>text</p>") == "text")
        #expect(MarkdownHTML.stripped("<summary>popisek</summary>") == "popisek")
        #expect(MarkdownHTML.stripped("<b>tučně</b> a <i>kurzíva</i>") == "tučně a kurzíva")
    }

    @Test("Řádek jen z tagů vyjde prázdný")
    func emptiesATagOnlyLine() {
        #expect(MarkdownHTML.stripped("<details>").isEmpty)
        #expect(MarkdownHTML.stripped("</p>").isEmpty)
    }

    @Test("`<br>` je zalomení")
    func convertsLineBreaks() {
        #expect(MarkdownHTML.stripped("první<br>druhý") == "první\ndruhý")
        #expect(MarkdownHTML.stripped("první<br />druhý") == "první\ndruhý")
    }

    @Test("Entity se dekódují")
    func decodesEntities() {
        #expect(MarkdownHTML.stripped("&lt;T&gt;") == "<T>")
        #expect(MarkdownHTML.stripped("a &amp; b") == "a & b")
        #expect(MarkdownHTML.stripped("&quot;citát&quot;") == "\"citát\"")
    }

    /// `&amp;` se dekóduje naposled — jinak by z `&amp;lt;` vyšlo `<` místo `&lt;`.
    @Test("Dvojitě zakódovaná entita se nedekóduje dvakrát")
    func decodesAmpersandLast() {
        #expect(MarkdownHTML.stripped("&amp;lt;") == "&lt;")
    }

    // MARK: - Inline kód

    /// Generický typ v inline kódu **není tag**. Bez téhle výjimky z komentáře zmizí zrovna to,
    /// o čem kolega píše nejčastěji.
    @Test("Generický typ v inline kódu zůstane")
    func keepsGenericsInsideCode() {
        #expect(MarkdownHTML.stripped("použij `Array<T>` místo pole") == "použij `Array<T>` místo pole")
        #expect(MarkdownHTML.stripped("`Result<OK, Err>`") == "`Result<OK, Err>`")
    }

    /// Kód uvnitř, HTML venku — obojí naráz na jednom řádku.
    @Test("HTML mimo kód se strhne, kód zůstane")
    func stripsOnlyOutsideCode() {
        #expect(
            MarkdownHTML.stripped("<b>pozor</b> na `Array<T>` tady")
                == "pozor na `Array<T>` tady"
        )
    }

    /// Pravidlo je Markdownové: zavírá běh **stejné délky**, takže dvojitý apostrof unese
    /// apostrof uvnitř.
    @Test("Dvojitý apostrof unese apostrof uvnitř")
    func handlesDoubleBacktickSpans() {
        #expect(MarkdownHTML.stripped("``kód s ` a <T>``") == "``kód s ` a <T>``")
    }

    /// Apostrof v běžné větě se stane — a spolknout kvůli němu půl komentáře by bylo horší než
    /// neošetřený tag.
    @Test("Neuzavřený apostrof kódem není")
    func doesNotTreatAnUnclosedBacktickAsCode() {
        #expect(MarkdownHTML.stripped("nedopsaný ` a <b>tučně</b>") == "nedopsaný ` a tučně")
    }

    @Test("Dva úseky kódu na řádku")
    func handlesTwoCodeSpans() {
        #expect(
            MarkdownHTML.stripped("`<A>` a <i>něco</i> a `<B>`")
                == "`<A>` a něco a `<B>`"
        )
    }

    /// Text bez HTML se nemá čím pokazit — a nemá se ani zdržovat.
    @Test("Text bez HTML zůstane nedotčený")
    func leavesPlainTextAlone() {
        let text = "obyčejný **Markdown** s `kódem`"

        #expect(!MarkdownHTML.containsMarkup(text))
        #expect(MarkdownHTML.stripped(text) == text)
    }
}
