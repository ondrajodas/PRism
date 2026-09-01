import Foundation

/// Co dostane session, která slévá konflikty (#467), a jak se z jejího účtu skládá výpis do okna.
/// Čisté funkce, žádné I/O.
extension Policy {
    // MARK: - Kolik kol

    /// Kolik kol slévání se povolí na jedno srovnání větve.
    ///
    /// **Tři, a je to strop proti účtu, ne proti zacyklení.** Rebase se zastaví u **každého**
    /// commitu, který koliduje, takže kol je tolik, kolik je kolizních commitů — a každé je vlastní
    /// session, tedy vlastní útrata. Tři pokrývají běžný případ (větev o pár commitech, do kterých
    /// zasáhl jeden cizí commit v základu); u čtvrtého už je poctivější říct „na tohle nestačím“
    /// a nabídnout terminál, než platit dál za něco, co se zjevně neslévá.
    ///
    /// **Není to totéž jako počet konfliktů.** Jedno kolo řeší **všechny** soubory, na kterých ten
    /// jeden commit uvázl.
    static let maxConflictRounds = 3

    // MARK: - Prompt

    /// Prompt jednoho kola.
    ///
    /// **Anglicky, jako všechny prompty v tomhle repu** — je to text pro model, ne pro okno.
    ///
    /// **Pět věcí, které v něm být musí** — čtyři pasti a k nim tvar odpovědi:
    ///
    /// - **Kolidující soubory vypsané jmény.** Session nemá `Bash`, takže si `git diff
    ///   --diff-filter=U` spustit nemůže — výčet je jediná cesta, jak se dozví, kde konflikt je.
    /// - **Co znamenají obě strany značky.** Při rebase je `HEAD` **základ** (to, co je na `main`u)
    ///   a spodní strana je **přehrávaný commit**, tedy moje práce. Je to obráceně, než jak to
    ///   člověk čte u merge, a model, který si to splete, zahodí zrovna tu práci, o kterou jde.
    /// - **Že necommituje.** Commit i `git rebase --continue` dělá aplikace; session jen upraví
    ///   soubory. Držet to doopravdy je práce sady bez `Bash`u (viz `ConflictCommand`) — tahle věta
    ///   je pojistka, ne brána, přesně jako u ostatních promptů.
    /// - **Že se má přiznat.** Uhádané slití, které projde testy a rozbije se v provozu, je horší
    ///   výsledek než `unresolved` — a platí to i tam, kde si session jistá je: `caveats` je pole
    ///   na to, čím si jistá není.
    /// - **Tvar účtu.** Vlastní nástroj na hlášení výsledku session nedostala (u té, která už smí
    ///   psát, se výčet nemá rozšiřovat), takže je JSON v posledním sdělení jediná cesta — a čte se
    ///   defenzivně (`ConflictCommand.parse`).
    static func conflictPrompt(files: [String], base: String) -> String {
        let list = files.map { "- \($0)" }.joined(separator: "\n")
        var parts: [String] = []
        parts.append("""
            A `git rebase` onto `\(base)` stopped on a conflict in the repository checked out in \
            the current directory. These files have conflict markers in them:

            \(list)

            Resolve them by editing the files in place. Read enough of the code around each \
            marker to understand both sides before you change anything.
            """)
        parts.append("""
            How to read the markers: this is a rebase, so the part under `<<<<<<< HEAD` is the \
            code that is already on `\(base)` (somebody else's work), the part under \
            `||||||| ` is the common ancestor, and the part above `>>>>>>>` is the commit being \
            replayed (the pull request's own work). Keep both intentions when they are \
            compatible; when they are not, keep the one that the surrounding code needs and say so.
            """)
        parts.append("""
            Rules you must not break: do not commit, do not run `git` at all, do not push, \
            do not touch anything outside the current directory. Staging the result and running \
            `git rebase --continue` is done by the application, not by you. Remove every conflict \
            marker from the files you resolve — a leftover `<<<<<<<` line means the resolution is \
            rejected.
            """)
        parts.append("""
            If a conflict needs a decision you cannot make from the code — a product decision, \
            a generated lockfile that has to be rebuilt, two incompatible refactors — leave that \
            file alone with its markers and report it as "unresolved". A guessed merge that \
            compiles and breaks in production is a worse outcome than admitting you could not do it.
            """)
        parts.append("""
            When you are done, output only a JSON object, no prose and no code fences:
            {"files": [{"path": "<path relative to the current directory>", \
            "action": "both" | "manual" | "unchanged" | "unresolved"}], "caveats": "<one Czech \
            sentence about what you are not sure of, or omit>"}
            Use "both" when both sides survived side by side, "manual" when you merged them by \
            hand, "unchanged" when you kept one side exactly as it was, "unresolved" when you \
            left it alone. Write "caveats" in Czech; everything else in English.
            """)
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Účet session proti tomu, co kolidovalo

    /// Výpis *Co s tím session udělala* — **účet session srovnaný se seznamem z `gitu`**.
    ///
    /// **Pořadí a rozsah drží `git`, popisky session.** Je to celá pointa: kdyby výpis vznikal
    /// z odpovědi modelu, mohl by mlčet o souboru, který kolidoval (a ten by se čtl jako vyřešený),
    /// nebo mluvit o souboru, který nekolidoval vůbec. Proto se prochází `conflicted` a účet se
    /// k němu jen **přiřazuje**:
    ///
    /// - soubor, o kterém session **mlčí**, dostane `unchanged` — nechala ho tak, jak ho `git`
    ///   nechal;
    /// - soubor, který **zůstal se značkami** (`unresolvedPaths`, změřeno `gitem`, ne tvrzeno
    ///   modelem), dostane `unresolved` **bez ohledu na to, co o něm session tvrdí**. Účet, který
    ///   říká „ruční slití“ nad souborem se značkami, je zrovna ten druh tvrzení, které data
    ///   neunesou;
    /// - soubor, o kterém session mluví a v `gitu` po něm není konflikt, dostane, co tvrdí.
    static func resolvedFiles(
        conflicted: [String],
        claimed: [ResolvedConflictFile],
        unresolvedPaths: [String] = []
    ) -> [ResolvedConflictFile] {
        let byPath = Dictionary(claimed.map { ($0.path, $0.action) }, uniquingKeysWith: { first, _ in first })
        let stuck = Set(unresolvedPaths)
        return conflicted.map { path in
            guard !stuck.contains(path) else {
                return ResolvedConflictFile(path: path, action: .unresolved)
            }
            return ResolvedConflictFile(path: path, action: byPath[path] ?? .unchanged)
        }
    }

    // MARK: - Věty do okna

    /// Věta pod akcemi, dokud session běží. **Nese kolo i počet souborů** — patnáctiminutové
    /// ticho nad „Slévám konflikty“ je k nerozeznání od zaseknutého okna.
    static func conflictActivity(round: Int, of limit: Int = maxConflictRounds, files: [String]) -> String {
        let count = Plural.czech(files.count, one: "souboru", few: "souborech", many: "souborech")
        return "Slévám konflikty ve \(count) (kolo \(round) z \(limit))."
    }

    /// Co session zrovna dělá — druhý řádek u hlášky, dokud běží.
    ///
    /// **Vlastní funkce, ne `askActivity`**, a je to o slovník: tahle session **píše**, takže
    /// potřebuje `Write` i `Edit` — a to jsou zrovna ty dva kroky, kvůli kterým se na ten řádek
    /// kouká. Slít je do funkce rozhovoru by znamenalo, že se do tabu `Zeptat se` dostane věta
    /// „píše do…“ o session, která psát nesmí.
    static func conflictToolActivity(of tool: ToolAttempt, inside worktree: URL?) -> String {
        let detail = tool.shortened(inside: worktree).flatMap { $0.isEmpty ? nil : $0 }
        switch tool.name {
        case "Write": return detail.map { "přepisuje \($0)" } ?? "přepisuje soubor…"
        case "Edit": return detail.map { "upravuje \($0)" } ?? "upravuje soubor…"
        case "Read": return detail.map { "čte \($0)" } ?? "čte soubor…"
        case "Grep": return detail.map { "hledá \($0)" } ?? "hledá v kódu…"
        case "Glob": return detail.map { "hledá soubory \($0)" } ?? "hledá soubory…"
        default: return "pracuje…"
        }
    }

    /// Věta o tom, že session psala mimo svůj strom — **a co z toho plyne**.
    ///
    /// Je to stav, který nemá nastat: brána v `--allowedTools` je změřená a takový pokus odmítne
    /// (viz `ConflictCommand`). Kdyby přesto nastal, **výsledek se nepřijme** — a věta to musí
    /// říct, protože „nepovedlo se“ by u téhle jedné vypadalo jako spadlá session.
    static func writesOutsideWorktree(_ paths: [String]) -> String {
        let list = paths.prefix(2).joined(separator: ", ")
        let rest = paths.count - min(paths.count, 2)
        let tail = rest > 0
            ? "\(list) a \(Plural.czech(rest, one: "další", few: "další", many: "dalších"))"
            : list
        return "Session psala mimo kopii repa (\(tail)), takže se její výsledek nepřijal. "
            + "Rebase zůstal rozdělaný — zahoď ho, nebo ho dokonči v terminálu."
    }

    /// Nadpis sheetu po doběhnutí session (návrh, sekce 36: *Srovnáno s `main` — 2 konflikty
    /// vyřešeny*).
    static func conflictSheetTitle(base: String, resolved: Int) -> String {
        // **Prázdný základ se nesází jako mezera.** Do #467 se sem dostane jedině ze snímku, který
        // ho zná (plán bez jména základu se nesestaví), ale nadpis `Srovnáno s  — …` by byl text,
        // který o sobě říká, že mu něco chybí — a je to nadpis potvrzení nevratné akce.
        let with = base.isEmpty ? "se základem" : "s \(base)"
        guard resolved > 0 else { return "Srovnáno \(with)" }
        let word = Plural.czech(resolved, one: "konflikt vyřešen", few: "konflikty vyřešeny", many: "konfliktů vyřešeno")
        return "Srovnáno \(with) — \(word)"
    }

    /// Kolik řádků diffu se v potvrzení vypíše a kolik zbyde.
    ///
    /// **Strop je čtyřicet a zbytek se počítá** (`a další N řádků`), ne ořezává potichu — tatáž
    /// úmluva jako u výpisu commitů (#466) a ze stejného důvodu: pod diffem stojí **výstraha
    /// o lease**, a neomezený diff ji odroluje pod hranu, takže z potvrzení zbude diff. **Vnořený
    /// scroll je zamítnutý** ze stejného důvodu jako tam: dvě rolovací plochy nad sebou u nevratné
    /// akce schovávají zrovna to, co má být přečtené.
    ///
    /// Čtyřicet proto, že jde o slití **jednoho** konfliktu — hunk kolem značky má typicky pár
    /// řádků a čtyřicet pokryje i tři takové. Celý diff je v kopii repa a dá se otevřít
    /// v terminálu, na což sheet nabízí tlačítko.
    static func conflictDiffLines(_ diff: String, limit: Int = conflictDiffLineLimit) -> (shown: [DiffPreviewLine], hidden: Int) {
        // Řádky přes `TextLines` (#295) — je to výstup `gitu`, tedy text, jehož zakončení řádků
        // aplikace nevybírá.
        let lines = TextLines.all(diff).map(String.init)
        // **Prázdný poslední řádek se nepočítá.** `git diff` končí `\n`, takže by výpis měl na konci
        // vždycky prázdný řádek a `a další 1 řádek` u diffu, který se vešel celý.
        let trimmed = lines.last?.isEmpty == true ? Array(lines.dropLast()) : lines
        let rows = trimmed.enumerated().map { DiffPreviewLine(index: $0.offset, text: $0.element) }
        guard rows.count > limit else { return (rows, 0) }
        return (Array(rows.prefix(limit)), rows.count - limit)
    }

    static let conflictDiffLineLimit = 40

    /// Kolik řádků diffu se nevešlo. **Věta, ne číslo** — tatáž úmluva jako `a další N commitů`.
    static func hiddenDiffLines(_ count: Int) -> String {
        "a další \(Plural.czech(count, one: "řádek", few: "řádky", many: "řádků"))"
    }
}

/// Jeden řádek diffu v potvrzení force pushe (#467).
///
/// **Vlastní typ, ne tuple v `ForEach`i** (#361): identita se má brát z uloženého pole. `id` je
/// **index**, ne text — v diffu se řádky legitimně opakují (prázdné řádky, `}`), takže je pořadí
/// jediná správná identita.
struct DiffPreviewLine: Hashable, Sendable, Identifiable {
    let index: Int
    let text: String

    var id: Int { index }

    /// Co ten řádek v diffu je. Rozhoduje **první znak**, jako v každém unified diffu — a hlavička
    /// (`diff --git`, `index`, `---`, `+++`) se od přidaného a smazaného řádku musí odlišit, jinak
    /// by `+++ b/soubor` svítilo zeleně jako přidaný kód.
    var kind: Kind {
        if text.hasPrefix("+++") || text.hasPrefix("---") { return .header }
        if text.hasPrefix("@@") { return .hunk }
        if text.hasPrefix("diff --git") || text.hasPrefix("index ")
            || text.hasPrefix("new file") || text.hasPrefix("deleted file")
            || text.hasPrefix("similarity index") || text.hasPrefix("rename ") {
            return .header
        }
        if text.hasPrefix("+") { return .added }
        if text.hasPrefix("-") { return .removed }
        return .context
    }

    enum Kind: Hashable, Sendable {
        case header
        case hunk
        case added
        case removed
        case context
    }
}
