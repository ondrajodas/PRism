import Foundation
import Testing

@testable import PRism

@Suite("ClaudeCommand")
struct ClaudeCommandTests {
    private let request = ReviewRequest(
        key: ReviewRunKey(
            pullRequest: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 7),
            headSha: "aaaa1111",
            skillID: "code-review"
        ),
        worktree: URL(filePath: "/tmp/strom"),
        baseSha: "bbbb2222"
    )

    @Test("Argumenty odpovídají ověřenému volání")
    func theArgumentsMatchTheVerifiedCommand() {
        // Tvar je kontrakt s CLI, ne detail: `--verbose` je v print režimu podmínka a bez
        // `stream-json` nemá parser co číst.
        let arguments = ClaudeCommand.arguments(prompt: "prompt")

        #expect(arguments == [
            "-p", "prompt",
            "--output-format", "stream-json",
            "--verbose",
            "--allowedTools", ClaudeCommand.allowedTools,
            "--disallowedTools", ClaudeCommand.disallowedTools,
        ])
    }

    @Test("Reviewer nesmí pushnout ani sáhnout na gh")
    func theReviewerCannotPushOrUseGh() {
        // `Bash(git:*)` povoluje **všechny** git příkazy včetně `push` — ověřeno spuštěním.
        // Bez tohohle zákazu by session uměla pushnout do uživatelova repozitáře, protože
        // `origin` v cache míří na skutečné repo a má credential helper.
        let disallowed = ClaudeCommand.disallowedTools.split(separator: ",").map(String.init)

        #expect(disallowed.contains("Bash(git push:*)"))
        #expect(disallowed.contains("Bash(gh:*)"))
    }

    @Test("Reviewer nedostane nic, čím by mohl zapisovat")
    func theReviewerCannotWrite() {
        let tools = ClaudeCommand.allowedTools.split(separator: ",").map(String.init)

        #expect(!tools.contains("Write"))
        #expect(!tools.contains("Edit"))
        #expect(!tools.contains("Bash"))
        // Bez `ReportFindings` by reviewer nálezy napsal textem a sběr by tiše nefungoval.
        #expect(tools.contains("ReportFindings"))
    }

    @Test("Prompt řekne, kdo reviewuje, proti čemu a jak to hlásit")
    func thePromptCarriesTheContract() {
        let prompt = ClaudeCommand.prompt(for: request)

        #expect(prompt.contains("\"code-review\" reviewer"))
        #expect(prompt.contains("bbbb2222...HEAD"))
        #expect(prompt.contains("ReportFindings"))
        // I prázdný seznam je odpověď — bez něj se „nic jsem nenašel" nedá odlišit od
        // „nereportoval jsem".
        #expect(prompt.contains("empty list"))
    }

    /// Prompt je **jeden řádek**. Skládá se z víceřádkového literálu se spojkami `\` na
    /// koncích a je snadné do něj `\n` propašovat tím, že se na jednom řádku vynechá.
    @Test("Prompt je jeden řádek")
    func thePromptIsASingleLine() {
        let prompt = ClaudeCommand.prompt(for: request)

        #expect(!prompt.contains("\n"))
        #expect(!prompt.contains("  "))
    }

    /// Jazyk nálezů se **do promptu nedostane**. Cokoli v něm může ovlivnit to, co reviewer
    /// najde, a ověřit opak je drahé — překládá se proto až po doběhnutí, viz
    /// `FindingTranslating`.
    @Test("Prompt reviewerovi jazyk nediktuje")
    func thePromptSaysNothingAboutLanguage() {
        let prompt = ClaudeCommand.prompt(for: request)

        #expect(!prompt.contains("Czech"))
        #expect(!prompt.contains("in English"))
    }

    @Test("Prompt není slash command")
    func thePromptIsNotASlashCommand() {
        // Ověřeno spuštěním: `-p "/code-review …"` doběhne úspěšně, ale nálezy vrátí jako
        // text a `ReportFindings` nezavolá — sběr by tiše nefungoval.
        #expect(!ClaudeCommand.prompt(for: request).hasPrefix("/"))
    }

    @Test("Prostředí pustí nested git k privátnímu repu bez ptaní")
    func theEnvironmentLetsNestedGitAuthenticate() {
        // `git diff` proti base commitu si na partial klonu dotahuje bloby ze sítě —
        // bez helperu by u privátního repa skončil na přihlášení, s promptem by visel.
        let environment = ClaudeCommand.environment(gh: URL(filePath: "/opt/homebrew/bin/gh"))

        #expect(environment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(environment["GIT_CONFIG_COUNT"] == "1")
        #expect(environment["GIT_CONFIG_KEY_0"] == "credential.helper")
        #expect(
            environment["GIT_CONFIG_VALUE_0"] == "!'/opt/homebrew/bin/gh' auth git-credential"
        )
    }

    @Test("Apostrof v cestě ke gh se odescapuje")
    func anApostropheInThePathIsEscaped() {
        // Helper spouští shell; neodescapovaný apostrof by uzavřel řetězec a zbytek cesty
        // by se stal příkazem.
        let environment = ClaudeCommand.environment(gh: URL(filePath: "/Users/o'brien/gh"))

        #expect(environment["GIT_CONFIG_VALUE_0"] == "!'/Users/o'\\''brien/gh' auth git-credential")
    }
}
