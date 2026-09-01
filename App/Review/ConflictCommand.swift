import Foundation

/// Jak se `claude` volá kvůli konfliktům při srovnání větve (#467). Čisté funkce, žádné I/O.
///
/// Je to **čtvrtá vyjmenovaná session** vedle revieweera, dotažení textu issue (#345) a rozhovoru
/// nad PR (#452) — a **první, která smí měnit soubory**. Tvrdá podmínka č. 2 se tím mění; co z ní
/// zůstává, je vyjmenované v `CLAUDE.md` a drží to tohle jedno místo.
enum ConflictCommand {
    // MARK: - Sada nástrojů

    /// Čtecí půlka sady. **Je to `Read,Grep,Glob` a nic víc — `Bash` v sadě není vůbec.**
    ///
    /// **První session v téhle aplikaci bez `Bash`u, a je to ta nejdůležitější mez z celého
    /// #467.** Zadání říká, že session nesmí commitovat ani pushovat, protože rebase řídí aplikace
    /// (`git add` a `git rebase --continue`) — a dvě věci, které commitují, se rozejdou. Kdyby
    /// v sadě bylo `Bash(git:*)` jako u revieweera, dala by se ta mez držet jedině **výčtem
    /// zákazů** (`Bash(git commit:*)`, `Bash(git rebase:*)`, `Bash(git add:*)`, …), tedy hádáním,
    /// co všechno se ještě dá napsat: `git -C <strom> commit` na vzor `Bash(git commit:*)`
    /// nezačíná. Bez `Bash`u je „session necommituje“ **vlastnost sady**, ne délka seznamu zákazů.
    ///
    /// Co se tím platí: session neuvidí `git show :2:soubor` ani `git log`. Vyrovnává to
    /// **`merge.conflictStyle=zdiff3`** u rebase (`GitRepoCheckout.replay`) — v konfliktní značce
    /// je pak vedle obou stran i **základ**, tedy přesně to, co by si session z `gitu` tahala.
    /// Změřeno na scratch repu: značka nese `<<<<<<< HEAD`, `||||||| parent of …` i
    /// `>>>>>>> <sha> (<titulek>)`.
    static let readingTools = "Read,Grep,Glob"

    /// Nástroje, které **píšou**. Vypsané zvlášť, protože se každý musí omezit na strom.
    static let writingTools = ["Write", "Edit"]

    /// Celá sada — a **`Write` s `Edit` mají vypsaný rozsah, ne holé jméno**.
    ///
    /// **Změřeno, ne přečteno v dokumentaci** (`docs/claude-cli.md`), a měřilo se to obojí, protože
    /// z jednoho pokusu se to rozhodnout nedá:
    ///
    /// - **Holé `Write` píše kamkoli.** Session s `--allowedTools "…,Write,Edit"` a `cwd`
    ///   v jedné složce přepsala soubor v **sousední** složce, o které v povolení nestálo nic.
    ///   Prompt tedy brána není a být nemůže.
    /// - **`Write(//<absolutní cesta>/**)` povoluje právě ten podstrom.** A `cwd` **není** povolený
    ///   implicitně: s rozsahem mířícím do sousední složky se zápis **do `cwd`** odmítl. To je ta
    ///   půlka, kterou bylo potřeba doměřit — bez ní by se první pokus dal vysvětlit i tak, že
    ///   scoped pravidlo nepovoluje nic a zápis do `cwd` prošel sám od sebe.
    /// - **`..` se normalizuje před kontrolou** a **odkaz uvnitř stromu mířící ven se odmítne**.
    ///   Obojí zkoušeno doslovnou cestou v `file_path`.
    ///
    /// Odmítnutí je vidět v `permission_denials` a **běh na něm nekončí chybou** — tedy tatáž
    /// vlastnost jako u odmítnutého `gh` u revieweera.
    ///
    /// **Dvě lomítka na začátku jsou formát pravidla, ne omyl**: `//` uvozuje absolutní cestu,
    /// která sama začíná lomítkem, takže výsledek má tři.
    static func allowedTools(in worktree: URL) -> String {
        let scope = "//\(worktree.path(percentEncoded: false))/**"
        return ([readingTools] + writingTools.map { "\($0)(\(scope))" }).joined(separator: ",")
    }

    /// Kolik má session času, než ji aplikace zabije.
    ///
    /// **Deset minut na kolo**, tedy dvojnásobek rozhovoru (#452) a zlomek limitu review: slití
    /// konfliktu je čtení kódu kolem značky a zápis, ne procházení celého repa. Nekonfiguruje se
    /// ze stejného důvodu jako u rozhovoru — knoflík, který si nikdo nenastaví, je jen řádek
    /// v nastavení.
    static let timeout: Duration = .seconds(600)

    /// Argumenty jednoho kola.
    ///
    /// **`--disallowedTools` je `ClaudeCommand.disallowedTools`**, tedy **tatáž konstanta** jako
    /// u zbylých tří session. Druhá sada zákazů by znamenala druhé místo, kde se dá tvrdá podmínka
    /// č. 2 porušit — a `Bash(gh:*)` s `Bash(git push:*)` jsou tady navíc pojistka **nad**
    /// pojistkou: `Bash` v povoleních není vůbec, takže se k nim session nemá čím dostat. Vypsané
    /// zůstávají proto, že se sada nesmí opřít o to, že je někde jinde krátká.
    ///
    /// **Model se bere z konfigurace**, jako u rozhovoru: slití cizího kódu je úvaha, ne
    /// mechanický převod, takže platí `model` — jedna odpověď na otázku, kterým modelem tahle
    /// aplikace mluví.
    ///
    /// **`--resume` tu není, a je to rozhodnutí.** Každé kolo je jiný commit a jiný konflikt;
    /// navázání by přineslo kontext, který se předchozím kolem stal neplatným (soubory se mezitím
    /// commitly), a zaplatilo by se za jeho přenášení. Kola jsou proto samostatné session
    /// a společné mají jedině prompt, který si pokaždé přečte skutečný stav stromu.
    static func arguments(prompt: String, worktree: URL, model: String? = nil) -> [String] {
        var arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--allowedTools", allowedTools(in: worktree),
            "--disallowedTools", ClaudeCommand.disallowedTools,
        ]
        if let model, !model.isEmpty {
            arguments += ["--model", model]
        }
        return arguments
    }

    // MARK: - Co session napsala do souborů mimo strom

    /// Cesty, do kterých se session pokusila psát **mimo svůj pracovní strom**.
    ///
    /// **Druhá vrstva, ne ta hlavní.** Brána je scoped `--allowedTools` (změřená výš); tohle je
    /// čtení z toho, co session doopravdy zkoušela, a existuje pro případ, že se ta brána někdy
    /// změní. Když se něco najde, výsledek se **nepřijme** — `git add` ani `rebase --continue`
    /// neproběhnou a v okně se to řekne.
    ///
    /// Počítají se **všechny pokusy, i odmítnuté**: otázka není „povedlo se to“, ale „mířila
    /// session mimo strom“. Odmítnutý pokus je odpověď „brána drží“, a to je pořád důvod
    /// nepokračovat bez člověka.
    static func writesOutside(_ tools: [ToolAttempt], worktree: URL) -> [String] {
        let root = worktree.path(percentEncoded: false)
        var seen: Set<String> = []
        return tools.compactMap { tool -> String? in
            guard writingTools.contains(tool.name) else { return nil }
            // Bez cesty se nedá tvrdit ani „mimo“, ani „uvnitř“ — a vymyslet si ji nesmíme.
            // Volání bez `file_path` je vada streamu, ne pokus o zápis ven.
            guard let path = tool.detail, !path.isEmpty else { return nil }
            let resolved = URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
            guard resolved != root, !resolved.hasPrefix(root + "/") else { return nil }
            return seen.insert(resolved).inserted ? resolved : nil
        }
    }

    // MARK: - Odpověď

    /// Účet session — **čte se defenzivně, ne přes `Codable`** (tentýž vzor jako u překladu
    /// nálezů).
    ///
    /// Je to volný text od modelu: může přijít obalený v ```-blocích, s větou navíc, nebo úplně
    /// jinak. Typované dekódování by na tom padalo, a **účet není to, na čem stojí rozhodnutí
    /// pokračovat** — o tom rozhoduje `git` (zůstaly ve souborech značky?). Nepřečtený účet tedy
    /// znamená výpis bez popisků, ne zahozenou práci.
    ///
    /// **Soubory, o kterých session mlčí, doplní volající** (`Policy.resolvedFiles`) jako
    /// `unchanged` — soubor, o kterém výpis mlčí, by se čtl jako vyřešený, a to je tvrzení, které
    /// data neunesou.
    static func parse(_ text: String?) -> (files: [ResolvedConflictFile], caveats: String?) {
        guard let text, let data = jsonObject(in: text),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return ([], nil) }

        let items = object["files"] as? [[String: Any]] ?? []
        var files: [ResolvedConflictFile] = []
        var seen: Set<String> = []
        for item in items {
            guard let path = (item["path"] as? String)?.trimmingCharacters(in: .whitespaces),
                !path.isEmpty, seen.insert(path).inserted
            else { continue }
            files.append(
                ResolvedConflictFile(path: path, action: action(of: item["action"] as? String))
            )
        }
        let caveats = (object["caveats"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .singleLine
        return (files, (caveats?.isEmpty ?? true) ? nil : caveats)
    }

    /// Neznámé slovo je `manual`, ne `unchanged`. Session, která něco udělala a popsala to jinak,
    /// než jsme čekali, ten soubor **sáhla** — a `beze změny` by o něm tvrdilo opak.
    private static func action(of value: String?) -> ResolvedConflictFile.Action {
        switch value?.lowercased() {
        case "both", "tookboth", "took_both": .tookBoth
        case "unchanged", "none", "kept": .unchanged
        case "unresolved", "failed", "giveup", "give_up": .unresolved
        default: .manual
        }
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
