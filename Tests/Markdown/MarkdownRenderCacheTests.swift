import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Zapamatovaná sazba Markdownu (#279). Testuje se to, co u cache může selhat potichu: že vrací
/// výsledek **toho svého** vstupu a že se přes vyjmenované meze nedostane.
@Suite("MarkdownRenderCache")
struct MarkdownRenderCacheTests {
    // MARK: - Bloky

    @Test("Zapamatovaný rozklad je tentýž, jaký by dal parser")
    func returnsWhatTheParserWould() {
        let cache = MarkdownRenderCache()
        let text = "## Nadpis\n\n> [!NOTE]\n> obsah"

        let first = cache.blocks(of: text)
        let second = cache.blocks(of: text)

        #expect(first == MarkdownParser.parse(text))
        #expect(second == first)
        #expect(cache.count == 1, "podruhé se to nemá počítat znovu")
    }

    /// Klíčem je celý text, ne jeho délka ani hash: dva různé komentáře se nesmí potkat v jednom
    /// záznamu, protože z toho je **vysázený cizí komentář**, a to potichu.
    @Test("Dva různé texty dostanou každý své bloky")
    func keepsTextsApart() {
        let cache = MarkdownRenderCache()

        #expect(cache.blocks(of: "## a") == [.heading(level: 2, text: "a")])
        #expect(cache.blocks(of: "## b") == [.heading(level: 2, text: "b")])
        #expect(cache.count == 2)
    }

    // MARK: - Inline

    @Test("Zapamatovaná inline sazba je tatáž, jakou by dal `MarkdownInlineText`")
    func returnsWhatInlineWould() {
        let cache = MarkdownRenderCache()
        let source = "věta s `kódem` a **tučným**"

        let first = cache.inline(source, size: 12.5)

        #expect(first == MarkdownInlineText.rendered(source, size: 12.5))
        #expect(cache.inline(source, size: 12.5) == first)
        #expect(cache.count == 1)
    }

    /// **Velikost je součástí klíče.** Bez ní by tentýž text vysázený v okně s novinkami (13)
    /// dostal písmo inline kódu z komentáře (12,5) — a taky potichu, protože rozdíl je půl bodu.
    @Test("Tentýž text v jiné velikosti je jiný záznam")
    func keepsSizesApart() {
        let cache = MarkdownRenderCache()
        let source = "věta s `kódem`"

        let small = cache.inline(source, size: 12.5)
        let large = cache.inline(source, size: 16)

        #expect(cache.count == 2, "velikost musí být v klíči")
        #expect(font(in: small) != font(in: large), "písmo kódu se má lišit, ne přijít z minula")
    }

    private func font(in text: AttributedString) -> Font? {
        text.runs.compactMap(\.font).first
    }

    // MARK: - Meze

    @Test("Přes strop na počet záznamů se cache nedostane")
    func staysWithinCapacity() {
        let cache = MarkdownRenderCache(capacity: 3, budget: 1024)

        for index in 0..<10 {
            _ = cache.blocks(of: "odstavec \(index)")
            _ = cache.inline("odstavec \(index)", size: 12.5)
            #expect(cache.count <= 3, "po \(index + 1) kolech je v cache \(cache.count)")
        }
    }

    @Test("Přes rozpočet na objem se cache nedostane")
    func staysWithinBudget() {
        let cache = MarkdownRenderCache(capacity: 1000, budget: 100)

        for index in 0..<10 {
            _ = cache.blocks(of: String(repeating: "a", count: 30) + "\(index)")
            #expect(cache.count <= 4, "po \(index + 1) textech je v cache \(cache.count)")
        }
    }

    /// Vstup delší, než je celý rozpočet, se **nepamatuje vůbec** — jinak by cache po jeho vložení
    /// hned přetekla a při dalším zápisu zahodila všechno; byla by z ní přihrádka na jeden komentář.
    @Test("Text nad rozpočet se nezapamatuje, ale vysází")
    func refusesAnOversizedText() {
        let cache = MarkdownRenderCache(capacity: 100, budget: 10)
        let text = "## " + String(repeating: "dlouhý ", count: 20)

        #expect(cache.blocks(of: text) == MarkdownParser.parse(text))
        #expect(cache.inline(text, size: 12.5) == MarkdownInlineText.rendered(text, size: 12.5))
        #expect(cache.count == 0)
    }
}
