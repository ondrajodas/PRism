import Foundation
import Testing

@testable import PRism

/// Překlad je **zobrazení, ne tvrzení** — originál musí zůstat a texty se musí umět
/// složit z obojího.
@Suite("Finding — překlad")
struct FindingTranslationTests {
    private func finding(
        summary: String = "Total ignores quantity",
        short: String? = "Bad total",
        scenario: String? = "Two items in the cart",
        translation: FindingTranslation? = nil
    ) -> Finding {
        Finding(
            reported: ReportedFinding(
                file: "Cart.swift",
                line: 13,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: short,
                summary: summary,
                failureScenario: scenario
            ),
            reviewer: "code-review",
            headSha: "aaaa1111",
            translation: translation
        )
    }

    @Test("Bez překladu se ukazuje originál")
    func showsTheOriginalWithoutATranslation() {
        let finding = finding()

        #expect(finding.summary == "Total ignores quantity")
        #expect(finding.shortSummary == "Bad total")
        #expect(finding.failureScenario == "Two items in the cart")
    }

    @Test("S překladem se ukazuje překlad")
    func prefersTheTranslation() {
        let finding = finding(translation: FindingTranslation(
            summary: "Celkovka ignoruje množství",
            shortSummary: "Špatná celkovka",
            failureScenario: "Dvě položky v košíku"
        ))

        #expect(finding.summary == "Celkovka ignoruje množství")
        #expect(finding.shortSummary == "Špatná celkovka")
        #expect(finding.failureScenario == "Dvě položky v košíku")
    }

    /// Kdyby překladateli jedno pole vypadlo, je jeden anglický řádek pořád lepší než
    /// chybějící text — ztracená věta se v UI nedá odlišit od věty, kterou reviewer
    /// nenapsal.
    @Test("Pole, které v překladu chybí, se vezme z originálu")
    func fallsBackFieldByField() {
        let finding = finding(translation: FindingTranslation(summary: "Celkovka ignoruje množství"))

        #expect(finding.summary == "Celkovka ignoruje množství")
        #expect(finding.shortSummary == "Bad total")
        #expect(finding.failureScenario == "Two items in the cart")
    }

    /// Překlad se nesmí propsat do toho, co poslal reviewer — na tom stojí `ReviewStore`.
    @Test("Originál zůstane sáhnutelný")
    func keepsTheOriginalReachable() {
        let finding = finding(translation: FindingTranslation(summary: "Celkovka ignoruje množství"))

        #expect(finding.reported.summary == "Total ignores quantity")
    }

    @Test("Nález s překladem přežije cestu na disk a zpátky")
    func survivesARoundTrip() throws {
        let original = finding(translation: FindingTranslation(
            summary: "Celkovka ignoruje množství",
            shortSummary: "Špatná celkovka",
            failureScenario: nil
        ))

        #expect(try roundTrip(original) == original)
    }

    /// Starší záznamy pole nemají a přijít o ně kvůli novému klíči by znamenalo ztracené
    /// nálezy.
    @Test("Záznam bez překladu se přečte")
    func readsARecordWithoutATranslation() throws {
        let json = """
        {"headSha": "aaaa1111", "reviewer": "code-review",
         "reported": {"summary": "Total ignores quantity"}}
        """

        let finding = try JSONDecoder().decode(Finding.self, from: Data(json.utf8))

        #expect(finding.translation == nil)
        #expect(finding.summary == "Total ignores quantity")
    }
}
