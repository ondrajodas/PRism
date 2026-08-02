import Foundation
import Testing

@testable import PRism

/// Odpověď překladače je **volný text od modelu**, ne formát, na kterém bychom se dohodli.
/// Čte se proto defenzivně a nepřeložený nález musí přežít každou podobu nesmyslu.
@Suite("TranslationCommand")
struct TranslationCommandTests {
    private func finding(_ summary: String, short: String? = nil, scenario: String? = nil) -> ReportedFinding {
        ReportedFinding(
            file: "Cart.swift",
            line: 13,
            category: "correctness",
            verdict: .confirmed,
            shortSummary: short,
            summary: summary,
            failureScenario: scenario
        )
    }

    // MARK: - Argumenty

    /// Překlad je transformace textu — session, která nemůže nic spustit, nemůže ani
    /// omylem sáhnout na repozitář.
    @Test("Překladač nedostane žádný nástroj")
    func theTranslatorGetsNoTools() {
        let arguments = TranslationCommand.arguments(prompt: "cokoli")

        let allowed = arguments.firstIndex(of: "--allowedTools").map { arguments[$0 + 1] }
        #expect(allowed == "")
        #expect(arguments.contains(ClaudeCommand.disallowedTools))
    }

    /// Tvrdá podmínka „na GitHub se nic neposílá“ nesmí stát na tom, že je povolený seznam
    /// prázdný — zákazy jsou tu jako pojistka.
    @Test("Zákazy platí i pro překladač")
    func theTranslatorCannotReachGitHubEither() {
        let arguments = TranslationCommand.arguments(prompt: "cokoli")
        let disallowed = arguments.firstIndex(of: "--disallowedTools").map { arguments[$0 + 1] } ?? ""

        #expect(disallowed.contains("Bash(gh:*)"))
        #expect(disallowed.contains("Bash(git push:*)"))
    }

    // MARK: - Prompt

    @Test("Prompt nese jazyk, id a texty")
    func thePromptCarriesEverythingNeeded() {
        let prompt = TranslationCommand.prompt(
            for: [finding("Total ignores quantity", short: "Bad total", scenario: "Two items")],
            to: .czech
        )

        #expect(prompt.contains("into Czech"))
        #expect(prompt.contains("\"id\":\"0\""))
        #expect(prompt.contains("Total ignores quantity"))
        #expect(prompt.contains("Bad total"))
        #expect(prompt.contains("Two items"))
    }

    /// Kategorie ani cesta se nepřekládají, takže do promptu nepatří — posílat je znamená
    /// nabídnout modelu, aby je změnil.
    @Test("Prompt neposílá kategorii ani cestu")
    func thePromptLeavesOutWhatIsNotProse() {
        let prompt = TranslationCommand.prompt(for: [finding("Total ignores quantity")], to: .czech)

        #expect(!prompt.contains("correctness"))
        #expect(!prompt.contains("Cart.swift"))
    }

    // MARK: - Čtení odpovědi

    @Test("Přeložené texty se přiřadí podle id")
    func matchesTranslationsById() {
        let output = """
        [{"id": "1", "summary": "Druhý"}, {"id": "0", "summary": "První"}]
        """

        let translations = TranslationCommand.parse(output, count: 2)

        #expect(translations[0]?.summary == "První")
        #expect(translations[1]?.summary == "Druhý")
    }

    @Test("Volitelná pole se přenesou")
    func carriesTheOptionalFields() {
        let output = #"[{"id": 0, "summary": "S", "short_summary": "K", "failure_scenario": "P"}]"#

        let translation = TranslationCommand.parse(output, count: 1)[0]

        #expect(translation?.shortSummary == "K")
        #expect(translation?.failureScenario == "P")
    }

    /// Model si vybírá sám, jestli pošle číslo nebo řetězec.
    @Test("id projde jako číslo i jako řetězec")
    func acceptsBothIdShapes() {
        #expect(TranslationCommand.parse(#"[{"id": 0, "summary": "A"}]"#, count: 1)[0] != nil)
        #expect(TranslationCommand.parse(#"[{"id": "0", "summary": "A"}]"#, count: 1)[0] != nil)
    }

    /// Přiřadit překlad podle vymyšleného indexu by ho dalo **cizímu** nálezu — a to je
    /// horší než nepřeložit vůbec.
    @Test("id mimo rozsah se zahodí")
    func dropsAnIdOutsideTheRange() {
        let translations = TranslationCommand.parse(#"[{"id": 7, "summary": "A"}]"#, count: 1)

        #expect(translations == [nil])
    }

    @Test("Chybějící položka nechá nález nepřeložený")
    func leavesAMissingItemUntranslated() {
        let translations = TranslationCommand.parse(#"[{"id": 0, "summary": "A"}]"#, count: 2)

        #expect(translations[0] != nil)
        #expect(translations[1] == nil)
    }

    /// Model rád obalí odpověď do bloku, i když se mu řekne, ať to nedělá.
    @Test("Odpověď v code fence se přečte")
    func readsAResponseWrappedInACodeFence() {
        let output = """
        Tady je překlad:
        ```json
        [{"id": 0, "summary": "A"}]
        ```
        """

        #expect(TranslationCommand.parse(output, count: 1)[0]?.summary == "A")
    }

    @Test("Rozbitá odpověď nechá všechno nepřeložené")
    func survivesGarbage() {
        #expect(TranslationCommand.parse("tohle není json", count: 2) == [nil, nil])
        #expect(TranslationCommand.parse("", count: 1) == [nil])
        #expect(TranslationCommand.parse(#"{"id": 0}"#, count: 1) == [nil])
    }

    /// `summary` je jediné povinné pole nálezu — položka bez něj by dala prázdný text tam,
    /// kde reviewer něco napsal.
    @Test("Položka bez summary se zahodí")
    func dropsAnItemWithoutASummary() {
        #expect(TranslationCommand.parse(#"[{"id": 0, "short_summary": "K"}]"#, count: 1) == [nil])
    }
}
