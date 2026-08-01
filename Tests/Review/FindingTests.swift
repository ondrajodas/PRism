import Foundation
import Testing

@testable import PRism

@Suite("Finding")
struct FindingTests {
    private let reported = ReportedFinding(
        file: "Cart.swift",
        line: 13,
        category: "correctness",
        verdict: .confirmed,
        shortSummary: "total() ignoruje quantity",
        summary: "Sčítá jen cenu.",
        failureScenario: "Košík se třemi kusy vrátí cenu jednoho."
    )

    @Test("Reviewer a head commit doplňuje aplikace, ne stream")
    func applicationAddsReviewerAndHeadSha() {
        // Ve streamu nejsou — reviewer je skill, který běžel, a `headSha` je to, na čem
        // nález visí.
        let finding = Finding(reported: reported, reviewer: "code-review", headSha: "7a9a826")

        #expect(finding.reviewer == "code-review")
        #expect(finding.headSha == "7a9a826")
        #expect(finding.file == "Cart.swift")
    }

    @Test("Přežije cestu na disk a zpět")
    func survivesRoundTrip() throws {
        let finding = Finding(reported: reported, reviewer: "code-review", headSha: "7a9a826")

        #expect(try roundTrip(finding) == finding)
    }

    @Test("Nález bez souboru a řádku je platný")
    func findingWithoutLocationIsValid() throws {
        let note = ReportedFinding(
            file: nil,
            line: nil,
            category: "test-coverage",
            verdict: nil,
            shortSummary: nil,
            summary: "Chybí testy.",
            failureScenario: "Nic to nekryje."
        )

        let finding = Finding(reported: note, reviewer: "code-review", headSha: "abc")

        #expect(finding.file == nil)
        #expect(try roundTrip(finding) == finding)
    }
}
