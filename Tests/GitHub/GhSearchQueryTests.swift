import Foundation
import Testing

@testable import PRism

/// Dělení dotazu je kontrakt s `gh`, ne detail: `gh search prs` bere každý argument jako
/// jeden výraz a hodnotu s mezerou si sám uzávorkuje. Špatné dělení tedy nespadne — jen
/// tiše hledá něco jiného, což je horší.
@Suite("GhSearchQuery")
struct GhSearchQueryTests {
    @Test("Qualifiery oddělené mezerou jsou samostatné argumenty")
    func splitsQualifiersOnWhitespace() {
        #expect(GhSearchQuery.arguments(from: "review-requested:@me is:open")
            == ["review-requested:@me", "is:open"])
    }

    @Test("Hodnota v uvozovkách zůstane jedním argumentem")
    func keepsQuotedValueTogether() {
        // Rozdělené na `label:help` a `wanted` je to jiný dotaz: druhý token se stane
        // fulltextovým výrazem a výsledky nemají s labelem nic společného.
        #expect(GhSearchQuery.arguments(from: "label:\"help wanted\"") == ["label:help wanted"])
    }

    @Test("Uvozovky se do argumentu nepropíšou")
    func dropsQuoteCharacters() {
        // gh si hodnotu s mezerou uzávorkuje sám; naše uvozovky by v dotazu skončily dvakrát.
        #expect(GhSearchQuery.arguments(from: "\"some phrase\"") == ["some phrase"])
    }

    @Test("Uvozovkovaná fráze se snese vedle běžných qualifierů")
    func mixesQuotedAndPlainTerms() {
        #expect(GhSearchQuery.arguments(from: "is:open label:\"help wanted\" review-requested:@me")
            == ["is:open", "label:help wanted", "review-requested:@me"])
    }

    @Test("Přebytečné mezery nevyrobí prázdné argumenty")
    func ignoresExtraWhitespace() {
        #expect(GhSearchQuery.arguments(from: "  is:open\t\nis:pr  ") == ["is:open", "is:pr"])
    }

    @Test("Neuzavřená uvozovka se dobere do konce místo pádu")
    func toleratesUnterminatedQuote() {
        #expect(GhSearchQuery.arguments(from: "label:\"help wanted") == ["label:help wanted"])
    }

    @Test("Prázdný dotaz nedá žádný argument")
    func emptyQueryHasNoArguments() {
        #expect(GhSearchQuery.arguments(from: "   ").isEmpty)
    }
}
