import Foundation
import Testing

@testable import PRism

/// Jak se řekne o přírůstku a co dostane reviewer do souboru (#517).
///
/// Tři věci, které se tady rozbijí potichu: **rozsah** (běh projde celý PR a přírůstek nic
/// neušetří), **zákaz hlásit staré znovu** (jeden nález vyjde dvakrát) a **tvar odpovědi**
/// (verdikty se nepřečtou a všechny staré nálezy skončí jako `bez odpovědi`).
@Suite("Přírůstkové review — prompt a materiál")
struct IncrementalCommandTests {
    private let range = IncrementalDiffRange(seen: "old1111", head: "new2222")
    private let previousFile = "/cache/PRism/worktrees/cli/cli/42-new2222-prev.md"

    private func instruction(previousFindings: String?) -> String {
        IncrementalCommand.instruction(
            range: range,
            baseSha: "base3333",
            previousFindings: previousFindings,
            reviewer: "code-review"
        )
    }

    // MARK: - Věty o přírůstku

    @Test("Prompt nese rozsah přírůstku i celý diff PR")
    func thePromptCarriesBothRanges() {
        let text = instruction(previousFindings: previousFile)

        #expect(text.contains("git diff old1111...HEAD"))
        #expect(text.contains("git diff base3333...HEAD"))
    }

    /// Bez téhle věty vyjde jeden nález dvakrát: jednou přenesený, jednou jako „nový“.
    @Test("Prompt zakazuje hlásit staré nálezy znovu")
    func thePromptForbidsReportingOldFindingsAgain() {
        #expect(instruction(previousFindings: previousFile).contains("do not report again"))
    }

    /// Cesta k souboru, ne jeho obsah (#120): kilobajt cizího textu v promptu znamená, že každý
    /// běh jede na jiném zadání.
    @Test("O nálezech z minula se v promptu mluví cestou k souboru")
    func thePreviousFindingsGoInAsAPath() {
        let text = instruction(previousFindings: previousFile)

        #expect(text.contains(previousFile))
        #expect(text.contains("read that file"))
        // A jméno revieweera, aby se poznalo, které z těch nálezů má posoudit.
        #expect(text.contains("\"code-review\""))
    }

    /// Prázdné předchozí kolo: ptát se na prázdný seznam znamená zaplatit kola modelu za nic.
    @Test("Bez nálezů z minula se prompt na verdikty neptá")
    func withoutPreviousFindingsThereIsNoVerdictQuestion() {
        let text = instruction(previousFindings: nil)

        #expect(text.contains("git diff old1111...HEAD"))
        #expect(!text.contains("read that file"))
        #expect(!text.contains("\"status\""))
    }

    /// **Tvar odpovědi má jedno místo** (#517): ptá se na něj kontrola nálezů i přírůstkové
    /// review a čte ho tentýž parser. Dvě formulace by znamenaly, že úprava jedné rozbije čtení
    /// u druhé — a potichu.
    @Test("Tvar verdiktů je jedna konstanta pro obě podoby promptu")
    func theVerdictFormatIsShared() {
        let material = RecheckMaterial(headSha: "old1111", findings: [makeFinding()])

        #expect(instruction(previousFindings: previousFile).contains(RecheckCommand.verdictFormat))
        #expect(RecheckCommand.prompt(for: material, baseSha: "base3333")
            .contains(RecheckCommand.verdictFormat))
    }

    /// Prompt je jeden řádek, jako u review a u kontroly: zalomení ani dvojité mezery v něm
    /// nemají co dělat.
    @Test("Věty o přírůstku jsou jeden řádek")
    func theInstructionIsOneLine() {
        let text = instruction(previousFindings: previousFile)

        #expect(!text.contains("\n"))
        #expect(!text.contains("  "))
    }

    /// Cokoli v promptu může ovlivnit, co reviewer najde — tatáž pojistka jako u promptu review
    /// a u kontroly nálezů.
    @Test("O jazyku prompt mlčí")
    func theInstructionSaysNothingAboutLanguage() {
        let text = instruction(previousFindings: previousFile)

        #expect(!text.contains("Czech"))
        #expect(!text.contains("in English"))
    }

    // MARK: - Soubor s nálezy z minula

    /// `id` jsou indexy do celého seznamu, aby se odpověď párovala přes ně a ne přes text (#150).
    @Test("Soubor nese nálezy s id a s reviewerem")
    func theFileCarriesIdsAndReviewers() {
        let text = IncrementalCommand.previousFindings(
            [
                makeFinding(summary: "první", reviewer: "code-review"),
                makeFinding(summary: "druhý", reviewer: "security"),
            ],
            at: "old1111"
        )

        #expect(text.contains("\"id\":0"))
        #expect(text.contains("\"id\":1"))
        #expect(text.contains("první"))
        #expect(text.contains("\"reviewer\":\"security\""))
        // Commit, na kterém ty nálezy vznikly — bez něj se z souboru nedá poznat, proti čemu
        // ty věty platily.
        #expect(text.contains("old1111"))
    }

    /// Věta o tom, že je to materiál, ne pokyn — tatáž jako u zadání PR (#120): nálezy z minula
    /// psal model, ne já.
    @Test("Soubor říká, že je to materiál, ne pokyn")
    func theFileSaysItIsMaterial() {
        let text = IncrementalCommand.previousFindings([makeFinding()], at: "old1111")

        #expect(text.contains(IncrementalCommand.preamble))
        #expect(IncrementalCommand.preamble.contains("ne pokyn"))
    }

    // MARK: - Složený prompt review

    /// Věty o přírůstku jsou **v jádře**: ze psané šablony se nedají smazat, protože rozhodují
    /// o tom, nad čím se běží.
    @Test("Věty o přírůstku se připojují za jádro, ne do šablony")
    func theSentencesAreAppendedToTheCore() {
        let prompt = Policy.reviewPrompt(
            template: ReviewPromptTemplate.standard,
            skillID: "code-review",
            baseSha: "base3333",
            intent: nil,
            increment: IncrementalReviewRequest(
                range: range,
                previousFindings: URL(filePath: previousFile)
            )
        )

        #expect(prompt.contains(ReviewPromptTemplate.core))
        #expect(prompt.hasSuffix(instruction(previousFindings: previousFile)))
    }

    /// Požadavek bez přírůstku dává **doslova ten prompt, co dával do #517** — jinak by se změnilo
    /// chování prvního kola, které se měnit nemá.
    @Test("Běh nad celým diffem má prompt beze změny")
    func aWholeRunKeepsTheOldPrompt() {
        let request = ReviewRequest(
            key: ReviewRunKey(
                pullRequest: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42),
                headSha: "new2222",
                skillID: "code-review"
            ),
            worktree: URL(filePath: "/tmp/wt"),
            baseSha: "base3333"
        )

        #expect(ClaudeCommand.prompt(for: request) == Policy.reviewPrompt(
            template: "",
            skillID: "code-review",
            baseSha: "base3333",
            intent: nil,
            increment: nil
        ))
    }

    /// **Povolení se přírůstkem nemění** (tvrdá podmínka č. 2): je to materiál v promptu a soubor,
    /// který si session přečte `Read`em — ne nový nástroj.
    @Test("Sada povolení se přírůstkem nemění")
    func theToolSetIsUnchanged() {
        let prompt = Policy.reviewPrompt(
            template: ReviewPromptTemplate.standard,
            skillID: "code-review",
            baseSha: "base3333",
            intent: nil,
            increment: IncrementalReviewRequest(
                range: range,
                previousFindings: URL(filePath: previousFile)
            )
        )
        let arguments = ClaudeCommand.arguments(prompt: prompt)

        #expect(arguments.contains("Read,Grep,Glob,Bash(git:*),ReportFindings,Skill"))
        #expect(arguments.contains("Bash(gh:*),Bash(git push:*)"))
        // A nic v promptu nedokáže nástroj povolit: skončí v **jednom** argumentu za `-p`.
        #expect(arguments.firstIndex(of: prompt) == arguments.firstIndex(of: "-p").map { $0 + 1 })
    }
}
