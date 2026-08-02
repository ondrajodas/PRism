import Foundation
import Testing

@testable import PRism

@Suite("ClaudeCommand")
struct ClaudeCommandTests {
    private func request(language: FindingsLanguage = .czech) -> ReviewRequest {
        ReviewRequest(
            key: ReviewRunKey(
                pullRequest: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 7),
                headSha: "aaaa1111",
                skillID: "code-review"
            ),
            worktree: URL(filePath: "/tmp/strom"),
            baseSha: "bbbb2222",
            findingsLanguage: language
        )
    }

    private var request: ReviewRequest { request() }

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

    /// Prompt je **jeden řádek**. Skládá se ze dvou víceřádkových literálů spojených
    /// interpolací a je snadné do něj `\n` propašovat vynechaným `\` na konci řádku.
    /// Víceřádkový literál sám o sobě závěrečný newline nemá — řádek s ukončovacími
    /// uvozovkami do obsahu nepatří — ale spolehnout se na to bez testu znamená čekat,
    /// až to někdo rozbije.
    @Test("Prompt je jeden řádek", arguments: FindingsLanguage.allCases)
    func thePromptIsASingleLine(language: FindingsLanguage) {
        let prompt = ClaudeCommand.prompt(for: request(language: language))

        #expect(!prompt.contains("\n"))
        #expect(!prompt.contains("  "))
    }

    /// Jazyk se **říká reviewerovi**, nepřekládá se po něm — prompt je tedy jediné místo,
    /// kde se volba projeví.
    @Test("Prompt si řekne o jazyk nálezů")
    func thePromptAsksForTheFindingsLanguage() {
        #expect(ClaudeCommand.prompt(for: request(language: .czech)).contains("in Czech"))
        #expect(ClaudeCommand.prompt(for: request(language: .english)).contains("in English"))
    }

    /// Věta se posílá i pro angličtinu. Reviewer čte pracovní strom, a když je repo
    /// dokumentované česky, napsal by česky i nálezy tam, kde se to nechce.
    @Test("Angličtina se taky vysloví, nemlčí se o ní")
    func statesEnglishExplicitly() {
        let prompt = ClaudeCommand.prompt(for: request(language: .english))

        #expect(prompt.contains("Write summary, short_summary and failure_scenario"))
    }

    /// `category` je slug, na který se váže blokující sada. Přeložený by v `Policy`
    /// přestal sedět a nález se ztrátou dat by přestal blokovat.
    @Test("Prompt drží kategorii anglicky i u českých nálezů")
    func keepsTheCategoryInEnglish() {
        let prompt = ClaudeCommand.prompt(for: request(language: .czech))

        #expect(prompt.contains("Keep category in English"))
        #expect(prompt.contains("data-loss"))
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
