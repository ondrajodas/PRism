import Foundation
import Testing

@testable import PRism

@Suite("Policy.sorted a sections")
struct FindingOrderTests {
    @Test("Blokující kategorie jdou nahoru, zbytek abecedně")
    func blockingCategoriesComeFirst() {
        let sorted = Policy.sorted([
            makeFinding(category: "style", summary: "styl"),
            makeFinding(category: "security", summary: "bezpečnost"),
            makeFinding(category: "architecture", summary: "architektura"),
            makeFinding(category: "correctness", summary: "správnost"),
        ])

        #expect(sorted.map(\.summary) == ["správnost", "bezpečnost", "architektura", "styl"])
    }

    @Test("Nálezy bez kategorie jsou úplně dole")
    func findingsWithoutACategoryGoLast() {
        // Platný stav, ne chyba — jen se nemá o co opřít.
        let sorted = Policy.sorted([
            makeFinding(category: nil, summary: "bez kategorie"),
            makeFinding(category: "style", summary: "styl"),
        ])

        #expect(sorted.map(\.summary) == ["styl", "bez kategorie"])
    }

    @Test("Uvnitř kategorie je CONFIRMED nad PLAUSIBLE")
    func confirmedComesBeforePlausible() {
        let sorted = Policy.sorted([
            makeFinding(verdict: .plausible, summary: "možná"),
            makeFinding(verdict: nil, summary: "neuvedeno"),
            makeFinding(verdict: .confirmed, summary: "jistě"),
        ])

        #expect(sorted.first?.summary == "jistě")
    }

    @Test("Pak se řadí podle souboru a řádku")
    func fileAndLineDecideNext() {
        let sorted = Policy.sorted([
            makeFinding(file: "Order.swift", line: 5, summary: "order 5"),
            makeFinding(file: "Cart.swift", line: 20, summary: "cart 20"),
            makeFinding(file: "Cart.swift", line: 3, summary: "cart 3"),
        ])

        #expect(sorted.map(\.summary) == ["cart 3", "cart 20", "order 5"])
    }

    @Test("Nález bez řádku jde za nálezy z téhož souboru")
    func aFindingWithoutALineGoesAfterTheOthers() {
        let sorted = Policy.sorted([
            makeFinding(file: "Cart.swift", line: nil, summary: "celý soubor"),
            makeFinding(file: "Cart.swift", line: 3, summary: "řádek 3"),
        ])

        #expect(sorted.map(\.summary) == ["řádek 3", "celý soubor"])
    }

    @Test("Nález bez souboru jde úplně dozadu, ne dopředu")
    func aFindingWithoutAFileGoesLast() {
        // Chybějící soubor je `nil` a v klíči z něj vyjde prázdný řetězec, který se řadí
        // **před** všechno — takže bez vlastního kritéria by architektonická poznámka
        // předběhla konkrétní řádky.
        let sorted = Policy.sorted([
            makeFinding(file: nil, line: nil, summary: "chybí testy"),
            makeFinding(file: "Cart.swift", line: 3, summary: "řádek 3"),
        ])

        #expect(sorted.map(\.summary) == ["řádek 3", "chybí testy"])
    }

    @Test("Řazení je úplné, takže pořadí mezi překresleními neposkakuje")
    func theOrderIsTotal() {
        // Bez posledního kritéria by dva nálezy stejného druhu na stejném řádku měnily
        // pořadí podle toho, jak přišly.
        let findings = [
            makeFinding(file: "Cart.swift", line: 13, summary: "bbb"),
            makeFinding(file: "Cart.swift", line: 13, summary: "aaa"),
        ]

        #expect(Policy.sorted(findings).map(\.summary) == ["aaa", "bbb"])
        #expect(Policy.sorted(findings.reversed()).map(\.summary) == ["aaa", "bbb"])
    }

    @Test("Blokující sada mění i pořadí")
    func theBlockingSetChangesTheOrderToo() {
        let findings = [
            makeFinding(category: "correctness", summary: "správnost"),
            makeFinding(category: "style", summary: "styl"),
        ]

        #expect(Policy.sorted(findings, categories: ["style"]).map(\.summary) == ["styl", "správnost"])
    }

    // MARK: - Sekce

    @Test("Sekce jsou podle kategorie a ve stejném pořadí jako řazení")
    func sectionsFollowTheSameOrder() {
        let sections = Policy.sections([
            makeFinding(category: "style"),
            makeFinding(category: "security"),
            makeFinding(category: nil),
        ])

        #expect(sections.map(\.category) == ["security", "style", nil])
    }

    @Test("Kategorie s CONFIRMED i PLAUSIBLE zůstane jedna sekce")
    func aMixedCategoryStaysOneSection() {
        // Kdyby se řadilo podle toho, jestli blokuje **nález** (a ne kategorie), rozpadla by
        // se tahle kategorie na dvě sekce se stejným názvem.
        let sections = Policy.sections([
            makeFinding(category: "correctness", verdict: .confirmed, summary: "jistě"),
            makeFinding(category: "style", verdict: .confirmed, summary: "styl"),
            makeFinding(category: "correctness", verdict: .plausible, summary: "možná"),
        ])

        #expect(sections.count == 2)
        #expect(sections.first?.findings.map(\.summary) == ["jistě", "možná"])
    }

    @Test("Velikost písmen dvě sekce téhož nevyrobí")
    func casingDoesNotSplitASection() {
        let sections = Policy.sections([
            makeFinding(category: "Correctness", summary: "velké"),
            makeFinding(category: "correctness", summary: "malé"),
        ])

        #expect(sections.count == 1)
        #expect(sections.first?.category == "correctness")
    }

    @Test("Prázdný vstup nedá žádnou sekci")
    func nothingInNothingOut() {
        #expect(Policy.sections([]).isEmpty)
        #expect(Policy.sorted([]).isEmpty)
    }
}
