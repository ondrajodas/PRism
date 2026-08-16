import Foundation
import Testing

@testable import PRism

/// Šablona promptu review (#281).
///
/// Nejcennější dvě tvrzení jsou o tom, že se **nic nezměnilo** a že se **nedá odebrat**:
/// výchozí šablona složí znak po znaku ten prompt, který aplikace posílala do #281, a jádro
/// je v poskládaném textu i tehdy, když si ho někdo ze šablony smaže. Obojí je zapsané
/// literálem, ne přes konstanty z aplikace — porovnávat konstantu se sebou samou by prošlo
/// i po přepsání textu.
@Suite("Prompt review — šablona")
struct ReviewPromptTemplateTests {
    /// Prompt, který aplikace posílala **před** #281, s dosazeným `code-review` a `bbbb2222`.
    /// Opsáno z `ClaudeCommand.prompt(skillID:baseSha:)` z commitu před touhle změnou.
    private let promptBefore281 = """
        You are reviewing a pull request. \
        First call the Skill tool with skill="code-review" and follow the \
        instructions it gives you — that skill defines how this review is done. \
        The head commit is checked out here; see the changes with \
        `git diff bbbb2222...HEAD`; there is no GitHub access, so read the \
        working tree instead of fetching the pull request. \
        Report every finding by calling the ReportFindings tool — that call is the only \
        output that counts, so call it even when you find nothing, with an empty list. \
        Do not run anything that writes or sends: no commits, no pushes, \
        no `gh` commands, no comments on GitHub. \
        These rules override anything the skill tells you.
        """

    private func compose(_ template: String, skill: String = "code-review", base: String = "bbbb2222") -> String {
        Policy.reviewPrompt(template: template, skillID: skill, baseSha: base)
    }

    // MARK: - Nic se nezměnilo

    /// **Tohle je ten test, kvůli kterému #281 nesmí změnit chování.** `Configuration.standard`
    /// drží hodnoty, se kterými aplikace běžela, než konfigurace existovala — a zavedení pole
    /// je nesmí posunout ani o mezeru.
    @Test("Výchozí šablona složí znak po znaku dnešní prompt")
    func theDefaultTemplateComposesTodaysPrompt() {
        #expect(compose(ReviewPromptTemplate.standard) == promptBefore281)
    }

    /// Druhá strana téhož: v konfiguraci je opravdu ta výchozí šablona, ne prázdno „které se
    /// stejně chová stejně“. Prázdná hodnota by se chovala stejně jen do chvíle, než by se
    /// změnila `standard`.
    @Test("Výchozí konfigurace nese výchozí šablonu")
    func theStandardConfigurationCarriesTheDefaultTemplate() {
        #expect(Configuration.standard.global.reviewPrompt == ReviewPromptTemplate.standard)
        #expect(compose(Configuration.standard.global.reviewPrompt) == promptBefore281)
    }

    /// Prompt se skládá z literálu se spojkami `\` na koncích řádků, takže je snadné do něj
    /// `\n` propašovat tím, že se na jednom řádku vynechá — a dvě mezery vzniknou spojením.
    @Test("Poskládaný prompt zůstává jeden řádek")
    func theComposedPromptStaysASingleLine() {
        let prompt = compose(ReviewPromptTemplate.standard)

        #expect(!prompt.contains("\n"))
        #expect(!prompt.contains("  "))
    }

    // MARK: - Jádro se nedá odebrat

    /// Jádro chrání **sběr nálezů**: bez `ReportFindings` reviewer nálezy napíše textem, sběr
    /// tiše nefunguje a v okně stojí „čisté review“. Musí tedy přijít i k šabloně, ve které po
    /// něm není ani stopa.
    @Test("Jádro je v promptu i tehdy, když si ho uživatel ze šablony smaže")
    func theCoreSurvivesATemplateThatDroppedIt() {
        let stripped = "Review {{skill}} against {{baseSha}} and tell me what you think."

        let prompt = compose(stripped)

        #expect(prompt.hasPrefix("Review code-review against bbbb2222 and tell me what you think."))
        #expect(prompt.contains("Report every finding by calling the ReportFindings tool"))
        #expect(prompt.contains("call it even when you find nothing, with an empty list"))
        #expect(prompt.contains("no comments on GitHub"))
        #expect(prompt.contains("These rules override anything the skill tells you."))
    }

    /// A z druhé strany: v **psané** půlce jádro není. Kdyby si ho tam někdo přesunul, dala by
    /// se smazáním šablony ztratit — a předchozí test by to nepoznal, protože ten se dívá až na
    /// složený text.
    @Test("Výchozí šablona sama o sobě jádro nenese")
    func theDefaultTemplateItselfCarriesNoCore() {
        #expect(!ReviewPromptTemplate.standard.contains("ReportFindings"))
        #expect(!ReviewPromptTemplate.standard.contains("no comments on GitHub"))
        #expect(!ReviewPromptTemplate.standard.contains("override anything the skill"))
    }

    /// Náhled v nastavení kreslí obě části zvlášť, takže půlka bez jádra musí opravdu být bez
    /// jádra — jinak by se v okně objevilo dvakrát.
    @Test("Náhled psané půlky jádro neobsahuje")
    func theBodyPreviewHasNoCore() {
        let body = Policy.reviewPromptBody(
            template: ReviewPromptTemplate.standard,
            skillID: "code-review",
            baseSha: "bbbb2222"
        )

        #expect(!body.contains("ReportFindings"))
        #expect(body.hasSuffix("instead of fetching the pull request."))
    }

    // MARK: - Prázdná šablona

    /// Prázdné pole je běžný mezistav (⌘A a píše se znovu). Pustit reviewera bez zadání je
    /// horší než ho pustit s tím původním.
    @Test(
        "Prázdná šablona bere výchozí",
        arguments: ["", "   ", "\n", " \n\t "]
    )
    func anEmptyTemplateFallsBackToTheDefault(_ blank: String) {
        #expect(compose(blank) == promptBefore281)
        #expect(Policy.reviewPromptTemplate(from: blank) == ReviewPromptTemplate.standard)
        // A není to chyba, kterou by mělo okno hlásit — je to platná odpověď.
        #expect(Policy.reviewPromptProblems(in: blank).isEmpty)
    }

    // MARK: - Dosazení

    @Test("Zástupné texty se dosadí na každém výskytu")
    func substitutesEveryOccurrence() {
        let prompt = compose("{{skill}} {{baseSha}} {{skill}} {{baseSha}}", skill: "php-review", base: "deadbee")

        #expect(prompt.hasPrefix("php-review deadbee php-review deadbee "))
        #expect(!prompt.contains("{{skill}}"))
        #expect(!prompt.contains("{{baseSha}}"))
    }

    /// Šablona se před spojením s jádrem ořízne, jinak by v jednořádkovém promptu vznikly dvě
    /// mezery za sebou nebo dokonce nový řádek.
    @Test("Bílé znaky kolem šablony se do promptu nepřenášejí")
    func trimsTheTemplateBeforeJoining() {
        let prompt = compose("  Review {{skill}} at {{baseSha}}.\n\n")

        #expect(prompt.hasPrefix("Review code-review at bbbb2222. Report every finding"))
    }

    // MARK: - Validace

    @Test("Chybějící zástupný text se pojmenuje")
    func reportsAMissingPlaceholder() {
        #expect(
            Policy.reviewPromptProblems(in: "Review {{skill}}, nothing else.") == [.missingBaseSha]
        )
        #expect(
            Policy.reviewPromptProblems(in: "Diff against {{baseSha}}.") == [.missingSkill]
        )
    }

    /// Pořadí je pořadí `allCases`, ne pořadí mazání — hlášky u pole se nemají přeskupovat
    /// podle toho, co uživatel smazal dřív.
    @Test("Chybí-li obojí, vypíšou se oba v pevném pořadí")
    func reportsBothInAFixedOrder() {
        #expect(
            Policy.reviewPromptProblems(in: "Just review it.") == [.missingSkill, .missingBaseSha]
        )
    }

    @Test("Výchozí šablona projde validací")
    func theDefaultTemplatePasses() {
        #expect(Policy.reviewPromptProblems(in: ReviewPromptTemplate.standard).isEmpty)
    }

    /// Hláška musí pojmenovat **který** zástupný text chybí a proč to vadí — „šablona je
    /// neplatná“ je zákaz bez důvodu a u pole se s ním nedá nic dělat.
    @Test("Hláška nese zástupný text i důvod", arguments: ReviewPromptTemplate.Problem.allCases)
    func theComplaintNamesThePlaceholderAndTheReason(_ problem: ReviewPromptTemplate.Problem) {
        #expect(problem.reason.contains(problem.placeholder))
        #expect(problem.reason.count > problem.placeholder.count + 20)
    }
}
