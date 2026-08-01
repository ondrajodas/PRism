import Foundation

/// Jak se `claude` volá. Čisté funkce, žádné I/O.
///
/// Tvar argumentů je **kontrakt s CLI**, ne detail implementace — ověřený spuštěním
/// (viz [`docs/claude-cli.md`](../../docs/claude-cli.md)), a proto testovaný bez procesu.
enum ClaudeCommand {
    /// Sada nástrojů reviewera.
    ///
    /// Tvrdá podmínka: **žádný `Write` ani `Edit`** a u `Bash` jen `git`. Ověřeno u #12,
    /// že read-only drží — ale ne tím, čím se čekalo: scope `Bash(git:*)` `Bash` nezúží
    /// (projdou i negitové příkazy) a nepovolené nástroje ze session nezmizí. Co neprojde,
    /// jsou **měnící** operace. Úzká sada tedy nešetří záruku, ale tahy.
    ///
    /// `ReportFindings` v seznamu **být musí**. Bez něj reviewer nálezy napíše jako text
    /// a sběr přes tool cally tiše nefunguje — návrh tuhle chybu obsahoval.
    static let allowedTools = "Read,Grep,Glob,Bash(git:*),ReportFindings"

    /// `--verbose` není volba, je to podmínka: bez něj `claude` v print režimu
    /// `stream-json` odmítne.
    static func arguments(prompt: String) -> [String] {
        [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--allowedTools", allowedTools,
        ]
    }

    /// Prompt je zatím **natvrdo**; konfigurace skillů a modelu přijde v #23.
    ///
    /// Skill se vyvolává lomítkem, protože to je způsob, kterým se skilly spouštějí i
    /// interaktivně. Zbytek je kontext, který session sama zjistit nemůže: strom je
    /// odpojený na head commitu, takže bez base sha nemá reviewer proti čemu diffovat.
    static func prompt(for request: ReviewRequest) -> String {
        """
        /\(request.key.skillID) Review the changes of this pull request. \
        The head commit is checked out here; see them with \
        `git diff \(request.baseSha)...HEAD`. \
        Report every finding with the ReportFindings tool.
        """
    }

    /// Prostředí session.
    ///
    /// Pracovní strom stojí nad **partial klonem**, takže `git diff` proti base commitu si
    /// bloby dotahuje ze sítě — a bez credential helperu by u privátního repa skončil na
    /// přihlášení. Helper se proto předává i sem, jen jinou cestou než u `RepoCheckout`:
    /// `-c` se týká jednoho volání, kdežto tenhle běh spouští `git` sám reviewer.
    /// `GIT_CONFIG_*` je pro to jediná cesta — a helperů se **nedotýká**, přidává další.
    ///
    /// `GIT_TERMINAL_PROMPT=0` ze stejného důvodu jako všude: podproces bez terminálu by
    /// na dotazu na heslo visel do timeoutu.
    static func environment(gh: URL) -> [String: String] {
        // Helper spouští shell, takže cesta patří do apostrofů — a apostrof v ní se musí
        // odescapovat, jinak by je předčasně uzavřela.
        let quoted = gh.path(percentEncoded: false).replacingOccurrences(of: "'", with: "'\\''")
        return [
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "credential.helper",
            "GIT_CONFIG_VALUE_0": "!'\(quoted)' auth git-credential",
        ]
    }
}
