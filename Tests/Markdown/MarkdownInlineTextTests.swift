import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Inline sazba (#279). Bloky jsou naše, **inline sází systém** — testuje se proto to, co k němu
/// přidáváme: strhnuté HTML a podložený `kód`.
@Suite("MarkdownInlineText")
struct MarkdownInlineTextTests {
    private func rendered(_ source: String) -> AttributedString {
        MarkdownInlineText.rendered(source, size: 12.5)
    }

    @Test("Tučné a odkaz zůstávají, značky mizí")
    func letsTheSystemDoInline() {
        let text = rendered("**tučně** a [odkaz](https://x)")

        #expect(String(text.characters) == "tučně a odkaz")
        #expect(text.runs.contains { $0.link?.absoluteString == "https://x" })
    }

    /// Inline `kód` dostal podklad, aby se v próze poznal — dřív to byl monospace bez ničeho.
    @Test("Inline kód má monospace písmo a podklad")
    func fillsInlineCode() throws {
        let text = rendered("věta s `Array<T>` uvnitř")

        #expect(String(text.characters).contains("Array<T>"), "generický typ se nesmí strhnout jako tag")
        let code = try #require(
            text.runs.first { $0.inlinePresentationIntent?.contains(.code) == true },
            "systémový parser nedal běhu kódu `inlinePresentationIntent` — bez něj se nemá co podložit"
        )
        #expect(code.backgroundColor == Palette.codeFill)
        #expect(code.font != nil, "kód se sází monospace, takže si písmo říká sám")
    }

    /// Podklad má **jen kód**: kdyby ho dostal celý odstavec, vypadala by próza jako blok kódu.
    @Test("Podklad nedostane nic než kód")
    func fillsNothingButCode() {
        let text = rendered("obyčejná **věta** s [odkazem](https://x)")

        #expect(text.runs.allSatisfy { $0.backgroundColor == nil })
    }

    @Test("Inline HTML se strhne, odkaz zůstane klikatelný")
    func stripsInlineHTML() {
        let text = rendered("<p>text s <a href=\"https://x\">odkazem</a></p>")

        #expect(String(text.characters) == "text s odkazem")
        #expect(text.runs.contains { $0.link?.absoluteString == "https://x" })
    }

    /// Když parsování selže, vrací se **holý text**: nepřečtený komentář je horší než komentář
    /// bez tučného.
    @Test("Rozbitý Markdown se vrátí jako text")
    func survivesBrokenMarkdown() {
        #expect(!String(rendered("[nedokončený odkaz](").characters).isEmpty)
        #expect(String(rendered("").characters).isEmpty)
    }
}
