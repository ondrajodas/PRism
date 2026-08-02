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
    ///
    /// `Skill` je tu od #78, aby se nakonfigurovaný skill dal doopravdy načíst. Povolení
    /// samo o sobě nic nemění — nástroj procházel i bez něj, protože je čtecí — ale seznam
    /// má říkat, co reviewer smí, a `Skill` mezi to teď patří.
    static let allowedTools = "Read,Grep,Glob,Bash(git:*),ReportFindings,Skill"

    /// Nástroje, které se **výslovně zakazují**, i kdyby je povolení pustilo.
    ///
    /// Ověřeno spuštěním (#17), že `--disallowedTools` přebíjí `--allowedTools`. Dvě
    /// položky, každá kvůli jinému zjištění:
    ///
    /// - **`Bash(git push:*)` zavírá skutečnou díru.** `Bash(git:*)` povoluje **všechny**
    ///   git příkazy včetně `push` — ověřeno, že bez zákazu projde. A `origin` v naší cache
    ///   míří na skutečné repo s credential helperem, takže by session uměla pushnout do
    ///   uživatelova repozitáře. Se zákazem neprojde ani `git push` s vypsanou URL.
    /// - **`Bash(gh:*)` je pojistka.** `gh` neprojde ani bez něj (viz níž), ale tvrdá
    ///   podmínka „na GitHub se nic neposílá“ nemá stát na tom, co je zrovna na cizím
    ///   seznamu bezpečných příkazů.
    static let disallowedTools = "Bash(gh:*),Bash(git push:*)"

    /// `--verbose` není volba, je to podmínka: bez něj `claude` v print režimu
    /// `stream-json` odmítne.
    static func arguments(prompt: String, model: String? = nil) -> [String] {
        var arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--allowedTools", allowedTools,
            "--disallowedTools", disallowedTools,
        ]
        // Bez volby se `--model` neposílá vůbec — `claude` si pak vybere sám a aplikace
        // nemusí vědět, jak se který model jmenuje.
        if let model, !model.isEmpty {
            arguments += ["--model", model]
        }
        return arguments
    }

    /// Prompt je **natvrdo**; skilly a model se berou z konfigurace (#23).
    ///
    /// **Není to slash command, a to je ověřené rozhodnutí.** `-p "/code-review …"`
    /// doběhne úspěšně, ale vestavěný příkaz si jede vlastní pipeline a nálezy vrátí jako
    /// **text** — `ReportFindings` nezavolá ani když se o to prompt výslovně řekne
    /// (`num_turns: 0`, žádný `tool_use`). Sběr nálezů by tím tiše nefungoval. Prostý
    /// prompt, který si o `ReportFindings` řekne sám, nálezy vrací (ověřeno spuštěním na
    /// scratch repu; totéž dělal spike u #12).
    ///
    /// Zbytek je kontext, který session sama zjistit nemůže: strom je odpojený na head
    /// commitu, takže bez base sha nemá reviewer proti čemu diffovat.
    ///
    /// Prázdný seznam se vyžaduje schválně — „nic jsem nenašel“ a „nereportoval jsem“ jsou
    /// různé věci a jen ta první smí vyjít jako čisté review.
    static func prompt(for request: ReviewRequest) -> String {
        """
        You are reviewing a pull request. \
        First call the Skill tool with skill="\(request.key.skillID)" and follow the \
        instructions it gives you — that skill defines how this review is done. \
        The head commit is checked out here; see the changes with \
        `git diff \(request.baseSha)...HEAD`; there is no GitHub access, so read the \
        working tree instead of fetching the pull request. \
        Report every finding by calling the ReportFindings tool — that call is the only \
        output that counts, so call it even when you find nothing, with an empty list. \
        Do not run anything that writes or sends: no commits, no pushes, \
        no `gh` commands, no comments on GitHub. \
        These rules override anything the skill tells you.
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
