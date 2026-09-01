import Observation

/// Stav hledání v jednom diffu (#152).
///
/// **Třída, ne pole ve `AppStore`u, a je to výkonové rozhodnutí** (#472). `@Observable` sleduje po
/// vlastnostech, takže kdyby dotaz ležel ve slovníku ve store, probudilo by každé písmeno všechny
/// čtenáře toho slovníku — tedy i tělo detailu PR, které stojí desítky milisekund na průchod. Takhle
/// se mění vlastnost **objektu**, jehož identita je stálá: slovník ve store se nezmění a překreslí
/// se jedině to, co si tu vlastnost doopravdy čte. Tentýž vzorec jako `DiffViewport`.
///
/// Vlastnosti jsou proto rozdělené podle toho, **kdo je čte a jak často**:
///
/// - `isOpen` se mění dvakrát za hledání a čte ho tělo diffu (kreslí pruh) i lišta;
/// - `query` a `hits` se mění při každém písmenu; `query` čtou bloky kódu (zvýrazňují) a pruh,
///   `hits` a `counts` pruh a hlavičky souborů;
/// - `current` se mění při každém skoku a čtou ho bloky (sytější podklad) a pruh (`4 z 17`).
///
/// **Mění to store**, ne view: recompute výskytů potřebuje diff a rozbalený kontext, a to má
/// v ruce jedině on (`AppStore+DiffSearch`). Odsud se jen čte.
@Observable final class DiffSearchState {
    /// Je pruh otevřený? Zavřený pruh znamená **žádné zvýraznění** — dotaz si ale drží, aby
    /// druhé ⌘F pokračovalo tam, kde první skončilo.
    var isOpen = false
    /// Co je v poli.
    var query = ""
    var isCaseSensitive = false
    /// Výskyty v pořadí, ve kterém jsou na obrazovce.
    var hits: [DiffSearchHit] = []
    /// Kolik výskytů má který soubor (podle `displayPath`) — pro kapsli v jeho hlavičce.
    var counts: [String: Int] = [:]
    /// Index výskytu, na kterém člověk stojí. `nil` = zatím se nikam neskočilo.
    ///
    /// **Vlastní vlastnost, ne součást `hits`**: skok šipkou tím pádem nepřeskládá seznam a
    /// nepřebarví nic než dva podklady.
    var current: Int?
    /// Kolikrát se řeklo „zaostři pole“. Zvyšuje to otevření pruhu — **i to druhé ⌘F nad už
    /// otevřeným pruhem**, protože jinak by se fokus nedal vrátit zpátky do pole.
    ///
    /// Číslo, ne `Bool`: fokus se nastavuje **o průchod později** (#184), takže se na tu hodnotu
    /// věší `task(id:)` — a ten musí poznat i druhé stisknutí téže klávesy.
    var focusRequests = 0

    /// Dotaz tak, jak ho čte model.
    var searchQuery: DiffSearchQuery {
        DiffSearchQuery(text: query, isCaseSensitive: isCaseSensitive)
    }

    /// Dotaz, kterým se **kreslí** — zavřený pruh nezvýrazňuje nic (`⎋` zvýraznění zhasne).
    var drawnQuery: DiffSearchQuery {
        isOpen ? searchQuery : DiffSearchQuery(text: "", isCaseSensitive: isCaseSensitive)
    }

    /// Výskyt, na kterém člověk stojí.
    var currentHit: DiffSearchHit? {
        guard let current, hits.indices.contains(current) else { return nil }
        return hits[current]
    }

    /// Co pruh říká o výsledku.
    var report: DiffSearchReport {
        Policy.searchReport(query: searchQuery, total: hits.count, current: current)
    }
}

/// Co diff umí s hledáním. Jeden parametr místo šesti closures, které patří k sobě — tentýž vzorec
/// jako `DiffExpansionActions`.
///
/// **Prázdná výchozí hodnota znamená „tady se nehledá“**: náhledy a sondy nic nedodají a pruh se
/// v nich nekreslí, protože `state` je `nil`.
struct DiffSearchActions {
    /// Stav hledání v tomhle diffu. `nil` = ještě se v něm nehledalo (pruh nikdy nebyl otevřený).
    var state: DiffSearchState?
    /// ⌘F: otevřít pruh a zaostřit pole. Nad otevřeným pruhem jen zaostřit.
    ///
    /// **`nil` znamená „tady se nehledá“** — a je to jediný způsob, jak to poznat: `state` je `nil`
    /// i před prvním otevřením, takže z něj se to vyčíst nedá. Náhledy a sondy tedy nedostanou ani
    /// popisek v liště, ani zkratku.
    var open: (() -> Void)?
    /// `⎋` nebo `✕`: zavřít pruh. Dotaz se **nemaže** — zvýraznění zhasne tím, že je pruh zavřený.
    var close: () -> Void = {}
    var setQuery: (String) -> Void = { _ in }
    var setCaseSensitive: (Bool) -> Void = { _ in }
    /// Posun na další/předchozí výskyt. Vrací výskyt, na který se má skočit — kotvu si dopočítá
    /// diff, protože jedině on ví, jaký pohled kreslí a co je rozbalené.
    var step: (NavigationStep) -> DiffSearchHit? = { _ in nil }

    /// Kreslí se pruh?
    var isOpen: Bool { state?.isOpen ?? false }
}
