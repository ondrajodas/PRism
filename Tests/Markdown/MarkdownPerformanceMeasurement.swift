import Foundation
import Testing

@testable import PRism

/// Měření, ne test (#279). Nic netvrdí — říká, kolik stojí rozložení cizího textu na bloky.
///
/// Existuje proto, že #279 přidalo do citací **rekurzi**, a pravidlo #224 chce vědět, jestli se to
/// smí počítat v `body`, nebo se to musí pamatovat. Odpověď je číslo, ne dojem.
///
/// Časy se **netvrdí** `#expect`em: na jiném stroji vyjdou jinak a byl by z toho test, který padá
/// bez chyby v kódu. **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@Suite(
    "Měření sazby Markdownu (#279)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct MarkdownPerformanceMeasurement {
    private func measure(_ label: String, iterations: Int = 200, _ body: () -> Void) {
        let clock = ContinuousClock()
        body()    // zahřátí — první průchod platí za líné inicializace
        let elapsed = clock.measure {
            for _ in 0..<iterations { body() }
        }
        let each = elapsed / iterations
        print("MĚŘENÍ \(label): \(Double(each.components.attoseconds) / 1e12) µs na volání")
    }

    /// Skutečný komentář od bota (12 kB, `[!WARNING]` s nadpisem a dvěma rozbalovátky uvnitř)
    /// a proti němu tentýž text z cache. Rozdíl mezi těmi dvěma čísly je celé odůvodnění
    /// `MarkdownRenderCache`.
    @Test("Rozložení cizího komentáře na bloky")
    func parsingCost() throws {
        let body = try Fixture.text("gh/comment-coderabbit.md")
        let cache = MarkdownRenderCache()

        measure("parser nad komentářem od bota (\(body.utf8.count) B)") {
            _ = MarkdownParser.parse(body)
        }
        measure("tentýž komentář z cache") {
            _ = cache.blocks(of: body)
        }

        // Konverzace má desítky zpráv a překreslí se celá, takže zajímavé číslo je součet, ne
        // jedna zpráva.
        let conversation = Array(repeating: body, count: 40)
        measure("konverzace o 40 zprávách — parser", iterations: 10) {
            for text in conversation { _ = MarkdownParser.parse(text) }
        }
        measure("konverzace o 40 zprávách — z cache", iterations: 10) {
            for text in conversation { _ = cache.blocks(of: text) }
        }

        // A pro srovnání to druhé, co se v `body` počítá: inline sazba každého bloku. Podle tohohle
        // čísla se pozná, jestli stačí jedna cache, nebo jsou potřeba dvě.
        let texts = inlineTexts(of: MarkdownParser.parse(body))
        measure("inline sazba všech bloků komentáře (\(texts.count) bloků)", iterations: 50) {
            for text in texts { _ = MarkdownInlineText.rendered(text, size: 12.5) }
        }
    }

    /// Texty, které jdou do inline sazby — i ze zanořených bloků.
    private func inlineTexts(of blocks: [MarkdownBlock]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .heading(_, let text), .paragraph(let text), .listItem(_, _, let text): [text]
            case .quote(let inner), .alert(_, let inner): inlineTexts(of: inner)
            case .details(let summary, let inner): [summary] + inlineTexts(of: inner)
            case .code, .rule, .table, .htmlComment: []
            }
        }
    }
}
