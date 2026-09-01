import Foundation

/// Co pruh hledání o výsledku říká (#152).
///
/// Tři stavy, ne dva. **`idle` a `empty` se nesmí slít**: prázdné pole je „ještě jsem nezačal“,
/// kdežto prázdný výsledek je tvrzení o datech — a to je zrovna to tvrzení, které se musí říct
/// opatrně, protože mimo hunky se nehledá.
enum DiffSearchReport: Equatable, Sendable {
    /// Pole je prázdné, nehledá se.
    case idle
    /// Výskyty jsou. `position` je pořadí od jedničky, `nil` = zatím se nikam neskočilo.
    case hits(position: Int?, total: Int)
    /// Dotaz je, výskyt v načteném diffu žádný.
    case empty
}

extension Policy {
    /// Kam skočí šipka. `nil` = není kam (žádný výskyt).
    ///
    /// **Cyklí se dokola**, jako v prohlížeči i v Xcode: hledání je průchod celým diffem, takže
    /// zastavit se na konci znamená, že se člověk musí vracet ručně. Dokud se nikam neskočilo,
    /// míří dopředu na **první** výskyt a dozadu na **poslední** — ne na nulový: než se skočí,
    /// nestojí člověk nikde.
    static func searchStep(current: Int?, total: Int, _ direction: NavigationStep) -> Int? {
        guard total > 0 else { return nil }
        guard let current, (0..<total).contains(current) else {
            return direction == .forward ? 0 : total - 1
        }
        return switch direction {
        case .forward: (current + 1) % total
        case .backward: (current - 1 + total) % total
        }
    }

    /// Co udělá `↵` v poli hledání — a kdy se **propustí dál** (#152, nález z revize).
    ///
    /// Čisté `↵` skočí na další výskyt, `⇧↵` na předchozí. **Cokoli s `⌘`, `⌃` nebo `⌥` se
    /// propustí** (`nil`): `⌘↵` i `⌃↵` má v tomhle okně **otevření potvrzení odeslání review**
    /// (#151, #441), a spolknout je znamená rozbít tu zkratku na celou dobu, kdy je fokus v poli.
    /// `onKeyPress(keys:)` totiž dostane klávesu **se všemi modifikátory**, ne jen bez nich.
    ///
    /// Funkce nad hodnotou, ne `if` ve view: je to tvrzení o **kolizi zkratek**, tedy tatáž třída
    /// jako `claimsReturnShortcut` a `canCloseCommit` — a dá se projít testem.
    static func searchStepKey(modifiers: ShortcutModifiers) -> NavigationStep? {
        guard modifiers.subtracting(.shift).isEmpty else { return nil }
        return modifiers.contains(.shift) ? .backward : .forward
    }

    /// Co je v pruhu napsané u počtu — `4` + ` z 17 výskytů`, nebo `17` + ` výskytů` před prvním
    /// skokem.
    ///
    /// **Ne `0 z 17`**: nula by tvrdila, že stojím na nultém výskytu, kdežto pravda je, že nikde
    /// nestojím. Tatáž úvaha (a tentýž tvar dvou kusů kvůli tučné pozici) jako u procházení nálezů
    /// — viz `FindingNavigationView.counter`.
    static func searchCounter(position: Int?, total: Int) -> (position: String, rest: String) {
        guard let position else {
            return ("\(total)", " \(Plural.word(total, one: "výskyt", few: "výskyty", many: "výskytů"))")
        }
        // Za předložkou `z` je druhý pád (`z 1 výskytu`, `z 5 výskytů`), samotný počet první.
        let word = Plural.word(total, one: "výskytu", few: "výskytů", many: "výskytů")
        return ("\(position)", " z \(total) \(word)")
    }

    /// Stav pruhu z dotazu a z výsledku. Jedno místo, aby se počet a věta o něm nemohly rozejít.
    static func searchReport(query: DiffSearchQuery, total: Int, current: Int?) -> DiffSearchReport {
        guard query.isActive else { return .idle }
        guard total > 0 else { return .empty }
        // Pořadí se počítá od jedničky a jedině tehdy, když index na něco ukazuje: po přepsání
        // dotazu se výskyty přeskládají a stará pozice by ukazovala na výskyt, který tam není.
        let position = current.flatMap { (0..<total).contains($0) ? $0 + 1 : nil }
        return .hits(position: position, total: total)
    }

    /// Rozsah hledání jako kapsle u počtu. Krátké schválně — je to údaj k tomu číslu, ne věta.
    static let searchScopeNote = "jen v diffu"

    /// Rozsah v pruhu, když je místo. Zkrácená podoba celé věty z nápovědy.
    static let searchScopeSummary = "hunky a rozbalený kontext"

    /// Celá věta o rozsahu — do nápovědy pole. **Musí říct i to, co se nehledá**: bez druhé půlky
    /// by počet vypadal jako počet výskytů v souborech, a to není.
    static let searchScopeHelp = """
        Hledá se v hunkách a v rozbaleném kontextu. Zbytek souborů se kvůli hledání nenačítá — \
        rozbalením kontextu (⌄) se do hledání započítá.
        """

    /// Prázdný výsledek. **Nikdy „nic nenalezeno“**: to by tvrdilo něco o celém souboru, a přitom
    /// se mimo hunky nehledalo vůbec (řádek z tabulky v `CLAUDE.md` — text v UI nesmí tvrdit víc,
    /// než co data unesou).
    static let searchEmptyNote = "v diffu nic — mimo hunky se nehledá"

    /// Co se s tím dá udělat. Stojí vedle prázdného stavu, protože rozbalení kontextu je jediná
    /// cesta, jak hledání rozšířit.
    static let searchEmptyHint = "rozbal kontext (⌄) a započítá se"

    /// Kapsle v hlavičce souboru — `3 výskyty`. `nil` = v souboru není nic, kapsle se nekreslí.
    ///
    /// Ukazuje se **i u rozbaleného souboru**, ne jen u sbaleného: u sbaleného je to nutnost (jinak
    /// by se v něm počítalo a nebylo by z čeho to poznat), u rozbaleného zkratka „ve kterém souboru
    /// to je“ — tatáž úvaha jako u kapsle s nálezy o dva prvky vedle.
    static func fileSearchLabel(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return Plural.czech(count, one: "výskyt", few: "výskyty", many: "výskytů")
    }

    /// Co se v bloku toho souboru zvýrazní.
    ///
    /// **Aktuální výskyt se propouští jen do svého souboru**: `DiffLine` je porovnatelný, ale
    /// tentýž řádek (třeba `}` s týmiž čísly) může být ve dvou souborech — a sytější podklad by
    /// se pak rozsvítil na dvou místech naráz.
    static func searchHighlight(
        query: DiffSearchQuery,
        current: DiffSearchHit?,
        in path: String
    ) -> DiffSearchHighlight {
        guard query.isActive else { return .none }
        return DiffSearchHighlight(query: query, current: current?.path == path ? current : nil)
    }

    /// Bere si pruh hledání `⎋` pro sebe? (#152)
    ///
    /// V tabu `Commity` zavírá `⎋` diff commitu (#317), takže dvě věci na jedné klávese by
    /// znamenaly, že vyhraje ta zaregistrovaná později (#151, #184). Řeší se to vzorcem, který je
    /// v tomhle okně zavedený u `⌘⏎` v tabu `Zeptat se` (`claimsReturnShortcut`): zkratka **okna**
    /// se zakáže a klávesa propadne tomu, kdo je na obrazovce. Zakázané tlačítko klávesu nebere.
    ///
    /// Funkce nad hodnotou, ne `if` ve view: je to tvrzení o **kolizi zkratek v okně**, a to patří
    /// na jedno místo — vedle rozhodnutí, které tu klávesu druhé straně dává.
    static func claimsCancelShortcut(diffSearchOpen: Bool) -> Bool { diffSearchOpen }

    /// Dá se `⎋` zavřít diff commitu? (#317, od #152 s pruhem hledání)
    ///
    /// **Vyjmenované podmínky na jednom místě**, ať se dají projít testem: mimo tab `Commity`
    /// není co zavírat, nad otevřeným potvrzením odeslání a nad paletou patří klávesa jim —
    /// a od #152 i otevřenému pruhu hledání.
    static func canCloseCommit(
        tab: PullRequestTab,
        hasOpenedCommit: Bool,
        isSubmitting: Bool,
        isPaletteOpen: Bool,
        isDiffSearchOpen: Bool
    ) -> Bool {
        guard tab == .commits, hasOpenedCommit, !isSubmitting, !isPaletteOpen else { return false }
        return !claimsCancelShortcut(diffSearchOpen: isDiffSearchOpen)
    }
}
