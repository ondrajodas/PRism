import Foundation

/// Jak se `claude` volá, když má opravit vlastní PR po cizím review (#510). Čisté funkce, žádné
/// I/O.
///
/// Je to **pátá vyjmenovaná session** vedle revieweera, dotažení textu issue (#345), rozhovoru
/// (#452) a slévání konfliktů (#467) — a **druhá, která smí měnit soubory**. Sada povolení se ale
/// **nemění ani o položku**: bere se tatáž, kterou skládá `ConflictCommand`.
enum AgentFixCommand {
    // MARK: - Sada nástrojů

    /// Sada povolení — **doslova ta, kterou má slévání konfliktů** (#467).
    ///
    /// **Delegace, ne kopie, a je to rozhodnutí.** Otázka „kam smí zapisující session psát“ má mít
    /// **jednu** odpověď: druhé místo, které si `Write(//…)` složí samo, by se s prvním rozešlo
    /// potichu — a je to zrovna ta brána, na které stojí #467 i #510. `SingleWayOutTests` proto dál
    /// tvrdí, že rozsah skládá **jediný** soubor, a `SessionToolSetsTests` tvrdí literálem, že obě
    /// session dostanou tentýž řetězec.
    ///
    /// Co z toho plyne, je vypsané u `ConflictCommand.allowedTools(in:)` a měřené
    /// v `docs/claude-cli.md`: `Write` a `Edit` **s vypsaným rozsahem** (holé `Write` píše kamkoli),
    /// `Bash` v sadě **není vůbec** (commituje aplikace) a `cwd` povolený implicitně **není**.
    static func allowedTools(in worktree: URL) -> String {
        ConflictCommand.allowedTools(in: worktree)
    }

    /// Kolik má session času, než ji aplikace zabije.
    ///
    /// **Patnáct minut**, tedy o polovinu víc než jedno kolo slévání konfliktů, a je to rozdíl
    /// v tom, co ta session dělá: konflikt je čtení kolem značky ve vyjmenovaných souborech,
    /// kdežto tohle je oprava podle cizí zpětné vazby, u které se místo v kódu teprve hledá.
    /// Nekonfiguruje se ze stejného důvodu jako u konfliktů a u rozhovoru — knoflík, který si
    /// nikdo nenastaví, je jen řádek v nastavení.
    static let timeout: Duration = .seconds(900)

    /// Argumenty jednoho běhu.
    ///
    /// **Tytéž jako u konfliktů**, včetně `--disallowedTools` (`ClaudeCommand.disallowedTools`,
    /// tedy jedna konstanta pro všech pět session) a volby modelu z konfigurace. Vlastní seznam by
    /// znamenal druhé místo, kde se dá tvrdá podmínka č. 2 porušit.
    ///
    /// **`--resume` tu není, a je to rozhodnutí.** Každý běh je odpověď na **jinou** zpětnou vazbu
    /// a mezi nimi leží commit, takže by navázání přineslo kontext, který mezitím přestal platit.
    /// Běhy jsou proto samostatné session a společné mají jedině to, co si přečtou ve stromě.
    static func arguments(prompt: String, worktree: URL, model: String? = nil) -> [String] {
        ConflictCommand.arguments(prompt: prompt, worktree: worktree, model: model)
    }

    // MARK: - Co session napsala do souborů mimo strom

    /// Cesty, do kterých se session pokusila psát **mimo svůj pracovní strom** — druhá vrstva
    /// meze, na které #510 stojí.
    ///
    /// **Tatáž funkce jako u konfliktů**, a ze stejného důvodu jako sada povolení: „co je mimo
    /// strom“ má mít jednu odpověď. Když něco vyjde, výsledek se **nepřijme** — `git add`
    /// ani commit neproběhnou a v okně se to řekne.
    static func writesOutside(_ tools: [ToolAttempt], worktree: URL) -> [String] {
        ConflictCommand.writesOutside(tools, worktree: worktree)
    }

    // MARK: - Odpověď

    /// Účet session — **čte se defenzivně, ne přes `Codable`** (tentýž vzor jako u konfliktů
    /// a u překladu nálezů).
    ///
    /// Je to volný text od modelu: může přijít obalený v ```-blocích, s větou navíc, nebo úplně
    /// jinak. Typované dekódování by na tom padalo, a **účet není to, na čem stojí rozhodnutí
    /// commitnout** — o tom rozhoduje `git` (změnilo se ve stromě něco?). Nepřečtený účet tedy
    /// znamená commit bez shrnutí, ne zahozenou práci.
    static func parse(_ text: String?) -> (files: [String], summary: String?, skipped: String?) {
        guard let text, let data = jsonObject(in: text),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return ([], nil, nil) }

        var files: [String] = []
        var seen: Set<String> = []
        for item in object["files"] as? [Any] ?? [] {
            guard let path = (item as? String)?.trimmingCharacters(in: .whitespaces),
                !path.isEmpty, seen.insert(path).inserted
            else { continue }
            files.append(path)
        }
        return (files, sentence(object["summary"]), sentence(object["skipped"]))
    }

    /// Jedna věta od modelu, sražená na řádek. Prázdná se čte jako „neřekla nic“ — prázdný řádek
    /// v panelu vypadá jako díra.
    private static func sentence(_ value: Any?) -> String? {
        let text = (value as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .singleLine
        return (text?.isEmpty ?? true) ? nil : text
    }

    /// Vykrojí z odpovědi objekt. Hledá se první `{` a poslední `}`, takže projde i odpověď
    /// obalená v ```json bloku nebo s větou před ním.
    private static func jsonObject(in output: String) -> Data? {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"),
            start < end
        else { return nil }
        return String(output[start...end]).data(using: .utf8)
    }
}
