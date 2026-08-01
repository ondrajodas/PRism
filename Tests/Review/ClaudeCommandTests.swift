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
        ])
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

    @Test("Prompt vyvolá skill a řekne, proti čemu diffovat")
    func thePromptInvokesTheSkill() {
        let prompt = ClaudeCommand.prompt(for: request)

        #expect(prompt.hasPrefix("/code-review "))
        #expect(prompt.contains("bbbb2222...HEAD"))
        #expect(prompt.contains("ReportFindings"))
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
