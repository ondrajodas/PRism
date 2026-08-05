import Foundation
import Testing

@testable import PRism

/// Klíč nálezu a čtení odmítnutí nad záznamem (#113).
///
/// To hlavní tady není, že se klíč složí, ale **na čem se nesmí rozejít**: kdyby se tentýž
/// nález z druhého běhu nespároval, označení by tiše zmizelo a vypadalo by to jako
/// nekliknuté.
@Suite("Policy.key a odmítnuté nálezy")
struct FindingDismissalTests {
    @Test("Tentýž nález z druhého běhu se spáruje")
    func theSameFindingPairsAcrossRuns() {
        let first = makeFinding(file: "Cart.swift", line: 13, summary: "total() ignoruje množství")
        let second = makeFinding(file: "Cart.swift", line: 13, summary: "total() ignoruje množství")

        #expect(Policy.key(of: first) == Policy.key(of: second))
    }

    /// Ověřeno na skutečném běhu u #17: reviewer, který hlásí průběžně a na konci pošle
    /// kompletní seznam, si `short_summary` umí přeformulovat. Klíč z celé hodnoty by tentýž
    /// nález rozdvojil — a odmítnutí by se přestalo párovat.
    @Test("Přeformulované short_summary párování nerozbije")
    func aReworderShortSummaryStillPairs() {
        let first = makeFinding(
            file: "Cart.swift",
            line: 13,
            summary: "total() ignoruje množství",
            shortSummary: "total() ignores quantity"
        )
        let second = makeFinding(
            file: "Cart.swift",
            line: 13,
            summary: "total() ignoruje množství",
            shortSummary: "quantity ignored in total()"
        )

        #expect(Policy.key(of: first) == Policy.key(of: second))
    }

    /// Překlad se ukládá druhým zápisem po běhu a při dalším běhu ho model napíše jinak.
    /// Klíč se proto skládá z věty revieweera, ne z toho, co je vidět v okně.
    @Test("Překlad na klíč nesahá")
    func aTranslationDoesNotChangeTheKey() {
        let original = makeFinding(file: "Cart.swift", line: 13, summary: "total() ignores quantity")
        let translated = makeFinding(
            file: "Cart.swift",
            line: 13,
            summary: "total() ignores quantity",
            translation: FindingTranslation(
                summary: "total() ignoruje množství",
                shortSummary: nil,
                failureScenario: nil
            )
        )

        #expect(Policy.key(of: original) == Policy.key(of: translated))
    }

    /// Tatáž lekce jako u odznaku „už je v draftu“ (#66): dva reviewery na jednom řádku jsou
    /// běžné a odmítnout jednoho neznamená odmítnout druhého.
    @Test("Nález druhého revieweera na tomtéž řádku je jiný nález")
    func anotherReviewerOnTheSameLineIsADifferentFinding() {
        let mine = makeFinding(file: "Cart.swift", line: 13, reviewer: "code-review")
        let theirs = makeFinding(file: "Cart.swift", line: 13, reviewer: "security-review")

        #expect(Policy.key(of: mine) != Policy.key(of: theirs))
    }

    @Test("Různá místa dají různé klíče")
    func differentPlacesDifferentKeys() {
        let onLine13 = makeFinding(file: "Cart.swift", line: 13)
        let onLine14 = makeFinding(file: "Cart.swift", line: 14)
        let inAnotherFile = makeFinding(file: "Order.swift", line: 13)
        let withoutAPlace = makeFinding()

        #expect(Set([onLine13, onLine14, inAnotherFile, withoutAPlace].map(Policy.key(of:))).count == 4)
    }

    @Test("Různý text na stejném místě dá různé klíče")
    func differentTextDifferentKeys() {
        let first = makeFinding(file: "Cart.swift", line: 13, summary: "první")
        let second = makeFinding(file: "Cart.swift", line: 13, summary: "druhý")

        #expect(Policy.key(of: first) != Policy.key(of: second))
    }

    // MARK: - Čtení nad záznamem

    @Test("Odmítnutý nález se do platných nepočítá, ale ze záznamu nezmizí")
    func aDismissedFindingStaysInTheRecord() {
        let dismissed = makeReported(summary: "falešný")
        var record = makeRecord(runs: [makeStoredRun(findings: [dismissed, makeReported(summary: "platný")])])
        record.setDismissal(
            FindingDismissal(reason: .invalid, dismissedAt: Date(timeIntervalSince1970: 1)),
            of: record.findings[0]
        )

        #expect(record.findings.count == 2)
        #expect(record.activeFindings.map(\.summary) == ["platný"])
        #expect(record.dismissedCount == 1)
    }

    @Test("Vrácení odmítnutí zruší")
    func restoringClearsTheDismissal() {
        var record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])
        let finding = record.findings[0]
        record.setDismissal(
            FindingDismissal(reason: .irrelevant, dismissedAt: Date(timeIntervalSince1970: 1)),
            of: finding
        )

        record.setDismissal(nil, of: finding)

        #expect(record.dismissal(of: finding) == nil)
        #expect(record.activeFindings.count == 1)
        #expect(record.dismissedCount == 0)
    }

    /// Opakované review týmž skillem `StoredReviewRun` **přepíše** — a to je zrovna chvíle,
    /// kdy se stejný falešný nález vrátí. Kdyby označení bydlelo na `Finding`u, zmizelo by.
    @Test("Opakované review týmž skillem odmítnutí nezahodí")
    func repeatingTheSameSkillKeepsTheDismissal() {
        let reported = makeReported(summary: "falešný")
        var record = makeRecord(runs: [makeStoredRun(findings: [reported])])
        record.setDismissal(
            FindingDismissal(reason: .invalid, dismissedAt: Date(timeIntervalSince1970: 1)),
            of: record.findings[0]
        )

        record.replace(makeStoredRun(findings: [reported]))

        #expect(record.runs.count == 1)
        #expect(record.findings.count == 1)
        #expect(record.activeFindings.isEmpty)
    }

    /// Nález, který v tomhle běhu nepřišel, může přijít v dalším — uklidit jeho označení
    /// znamená přijít o něj právě tam, kde je nejdražší.
    @Test("Osiřelé označení se neuklízí")
    func anOrphanedDismissalSurvives() {
        let reported = makeReported(summary: "občas se vrací")
        var record = makeRecord(runs: [makeStoredRun(findings: [reported])])
        let finding = record.findings[0]
        record.setDismissal(
            FindingDismissal(reason: .invalid, dismissedAt: Date(timeIntervalSince1970: 1)),
            of: finding
        )

        // Druhý běh nález nenahlásil…
        record.replace(makeStoredRun(findings: []))
        #expect(record.findings.isEmpty)
        // …a třetí ano.
        record.replace(makeStoredRun(findings: [reported]))

        #expect(record.activeFindings.isEmpty)
    }
}
