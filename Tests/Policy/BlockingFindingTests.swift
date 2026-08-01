import Foundation
import Testing

@testable import PRism

@Suite("Policy.isBlocking")
struct BlockingFindingTests {
    @Test("Potvrzený nález v blokující kategorii blokuje")
    func aConfirmedFindingInABlockingCategoryBlocks() {
        #expect(Policy.isBlocking(makeFinding(category: "correctness", verdict: .confirmed)))
        #expect(Policy.isBlocking(makeFinding(category: "security", verdict: .confirmed)))
        #expect(Policy.isBlocking(makeFinding(category: "data-loss", verdict: .confirmed)))
    }

    @Test("PLAUSIBLE neblokuje ani v blokující kategorii")
    func aPlausibleFindingNeverBlocks() {
        // Nález „možná" nesmí zastavit PR — jinak se blokující příznak přestane brát vážně.
        #expect(!Policy.isBlocking(makeFinding(category: "correctness", verdict: .plausible)))
    }

    @Test("Kategorie mimo sadu neblokuje ani jako CONFIRMED")
    func aCategoryOutsideTheSetDoesNotBlock() {
        #expect(!Policy.isBlocking(makeFinding(category: "style", verdict: .confirmed)))
        #expect(!Policy.isBlocking(makeFinding(category: "test-coverage", verdict: .confirmed)))
    }

    @Test("Chybějící údaj neblokuje")
    func missingDataNeverBlocks() {
        // Nehádá se: bez kategorie nebo bez verdiktu není z čeho blokující příznak odvodit.
        #expect(!Policy.isBlocking(makeFinding(category: nil, verdict: .confirmed)))
        #expect(!Policy.isBlocking(makeFinding(category: "correctness", verdict: nil)))
    }

    @Test("Velikost písmen kategorii nezmění")
    func categoriesAreComparedCaseInsensitively() {
        // Kategorie je volný slug od reviewera. Kdyby `Data-Loss` neblokovalo, PR
        // s hlášenou ztrátou dat by tiše prošel.
        #expect(Policy.isBlocking(makeFinding(category: "Data-Loss", verdict: .confirmed)))
        #expect(Policy.isBlocking(
            makeFinding(category: "style", verdict: .confirmed),
            categories: ["STYLE"]
        ))
    }

    @Test("Blokující sada je jediný knoflík")
    func theBlockingSetIsTheOnlyKnob() {
        // Kvůli tomu se nemusí přepisovat skilly: co je vážné, se řekne tady.
        let finding = makeFinding(category: "correctness", verdict: .confirmed)

        #expect(!Policy.isBlocking(finding, categories: ["security"]))
        #expect(!Policy.isBlocking(finding, categories: []))
    }
}
