import Foundation

/// Jak se `claude` volá kvůli rozhovoru nad pull requestem (#452). Čisté funkce, žádné I/O.
///
/// Je to **třetí vyjmenovaná session** vedle revieweera a dotažení textu issue (#345), a jako
/// u nich platí, že rozšířit ten výčet znamená rozšířit, co aplikace umí spustit bez dohledu.
enum AskCommand {
    /// Sada nástrojů rozhovoru — **užší než reviewerova** (tvrdá podmínka č. 2).
    ///
    /// Proti `ClaudeCommand.allowedTools` chybí dvě položky a každá z jiného důvodu:
    ///
    /// - **`ReportFindings`** — session nemá co hlásit. Nálezy sbírá reviewer a ukládají se
    ///   klíčované `headSha` (tvrdá podmínka č. 5); rozhovor je odpověď na otázku, ne nález,
    ///   takže by ten nástroj byl druhá cesta, kterou se do uložených nálezů dá zapsat.
    /// - **`Skill`** — skill načtený za běhu si umí říct o odeslání na GitHub. U revieweera je
    ///   povolený schválně (#78), protože na skillu celé review stojí; tady na něm nestojí nic,
    ///   takže se nepovoluje. Zavírá to sice i `--disallowedTools`, ale sada má říkat, co session
    ///   smí, a `Skill` mezi to nepatří.
    ///
    /// Co v ní **je**: `Read`, `Grep` a `Glob` na kód v pracovní kopii a na soubor s materiálem
    /// (#120 — do promptu jde cesta, obsah si session přečte sama), a `Bash(git:*)` na
    /// `git diff <base>...HEAD`, tedy na tutéž cestu k diffu, jakou má reviewer. Bez `git`u by
    /// se diff musel do materiálu nasypat celý.
    static let allowedTools = "Read,Grep,Glob,Bash(git:*)"

    /// Kolik má odpověď času, než se session zabije.
    ///
    /// **Vlastní číslo, ne `reviewTimeout` z konfigurace** (#320), a je to rozhodnutí: limit
    /// review se zvedá kvůli pomalému repu, u kterého reviewer čte tisíce řádků. Tady čeká
    /// **člověk u okna** na jednu odpověď — pět minut je strop, po kterém už se nečeká, ale
    /// zkouší znovu. Nekonfiguruje se: knoflík, který si nikdo nenastaví, je jen řádek v okně.
    static let timeout: Duration = .seconds(300)

    /// Argumenty. **`--disallowedTools` je `ClaudeCommand.disallowedTools`**, tedy tatáž konstanta
    /// jako u revieweera i u dotažení textu issue — druhá sada zákazů by znamenala druhé místo,
    /// kde se dá tvrdá podmínka č. 2 porušit.
    ///
    /// `--resume` drží rozhovor pohromadě: druhá otázka navazuje na první, takže se nemusí znovu
    /// platit celý kontext. Prázdné id se **nepředává** — `claude --resume ""` by session hledal
    /// podle prázdného jména.
    ///
    /// **Model se bere z konfigurace**, na rozdíl od překladu nálezů a dotažení textu issue.
    /// U těch dvou je odpověď mechanická (JSON, doslovný text), takže na modelu nezáleží; tady je
    /// odpovědí úvaha nad cizím kódem a `model` v konfiguraci je zavedená odpověď na otázku,
    /// **kterým modelem tahle aplikace mluví**. Druhá odpověď na ni by znamenala, že se cena
    /// a kvalita rozhovoru řídí jinde než cena a kvalita review.
    static func arguments(prompt: String, resuming sessionID: String?, model: String? = nil) -> [String] {
        var arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--allowedTools", allowedTools,
            "--disallowedTools", ClaudeCommand.disallowedTools,
        ]
        if let sessionID, !sessionID.isEmpty {
            arguments += ["--resume", sessionID]
        }
        if let model, !model.isEmpty {
            arguments += ["--model", model]
        }
        return arguments
    }

    /// Soubory, které si session cestou k odpovědi otevřela — „co si přečetl“ nad bublinou.
    ///
    /// Bere se z **pokusů o nástroje**, tedy z toho, co doopravdy udělala, ne z toho, co se jí
    /// nabídlo. Počítají se jen ty, které **prošly**: odmítnutý nebo spadlý `Read` nic nepřečetl
    /// a tvrdit opak by u řádku „přečetl X“ znamenalo doklad o něčem, co se nestalo.
    ///
    /// Cesta se zkracuje o pracovní strom (`ToolAttempt.shortened(inside:)`) — jinak by na řádku
    /// stálo sedmdesát znaků cache před jménem souboru. Duplicity se zahazují, pořadí zůstává:
    /// session si týž soubor otevře i třikrát a v dokladu má být jednou.
    static func readFiles(from tools: [ToolAttempt], worktree: URL?) -> [String] {
        var seen: Set<String> = []
        return tools.compactMap { tool -> String? in
            guard tool.name == "Read", tool.outcome?.kind == .passed else { return nil }
            guard let path = tool.shortened(inside: worktree), !path.isEmpty else { return nil }
            return seen.insert(path).inserted ? path : nil
        }
    }
}
