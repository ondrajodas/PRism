import Foundation

/// Proč o téhle záložce polling nic neví (#527, rozšiřuje #531).
///
/// **Výčet, ne dva `Set`y vedle sebe.** Otevřená záložka nad PR mimo seznam z tiku potřebuje
/// **tři** věci a všechny tři jsou u obou důvodů stejné: shrnutí se skládá z dotaženého detailu
/// (`AppStore.summary(for:)`), úklid po tiku ji nesmí zahodit (`pullRequestsInPlay(besides:)`)
/// a čekání na detail se nesmí kreslit jako „pull request zmizel“
/// (`Policy.tabContent(summary:detail:adoption:)`). Rozdíl je **jediný**: pilulka v hlavičce, a to
/// je jedna funkce (`Policy.origin(of:adopted:sources:)`). Dvě množiny se skoro stejným významem
/// by znamenaly, že se na těch třech místech dá zapomenout jedna z nich — a potichu.
enum TabAdoption: String, Codable, Hashable, Sendable {
    /// Otevřel ji člověk **odkazem**, paletou ⌘K nebo `prism://` (#531). Hlavička to říká
    /// pilulkou `mimo zdroje · jen ke čtení`.
    case link
    /// Vrátila se z `tabs.json` **po restartu** (#527).
    ///
    /// **Pilulku nedostane**, a je to rozhodnutí, ne opomenutí. Obnovení běží **před prvním
    /// tikem**, takže je seznam ze zdrojů v tu chvíli prázdný a `mimo zdroje` by chvíli svítilo
    /// u **každé** obnovené záložky — tedy přesně to bliknutí, kvůli kterého odznak přestává něco
    /// znamenat. A po tiku by zbylo u těch, které z fronty vypadly, kde je správná odpověď „PR se
    /// mergnul“, ne „otevřel jsi ho odkazem“.
    case restored
}

/// Kde stál výřez v diffu (#527) — **soubor a řádek**, ne rámeček ani offset.
///
/// Offset po restartu neplatí: diff se v pohledu pod sebou **zalamuje** podle šířky okna, takže
/// tentýž řádek leží po jiném rozvržení jinde (změřeno u #152 — odhad z počtu řádků byl proti
/// skutečnosti trojnásobně mimo). Soubor a řádek jsou proti tomu údaj o **kódu**, takže platí
/// i tehdy, když se okno mezitím zúžilo.
///
/// `line == nil` znamená „ten soubor, začátek“ — přistane se na jeho hlavičce. Je to legitimní
/// odpověď, ne chyba: v diffu jsou i soubory bez řádku, na který by se dalo ukázat (binárka,
/// přejmenování beze změny obsahu).
struct DiffScrollAnchor: Codable, Hashable, Sendable {
    /// Cesta souboru tak, jak ji nese diff (`FileDiff.displayPath`) — tedy **nová** cesta
    /// u přejmenovaného souboru. Skok si ji přeloží sám (`Diff.file(at:)` zná obě).
    let file: String
    /// Číslo řádku v **nové** verzi souboru, tedy to, se kterým pracuje `DiffRow.anchor`.
    let line: Int?

    init(file: String, line: Int?) {
        self.file = file
        self.line = line
    }
}

/// Jedna otevřená záložka, jak se ukládá do `tabs.json` (#527).
struct OpenTab: Codable, Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Tab pull requestu, na kterém se skončilo.
    var tab: PullRequestTab
    /// Kde stál výřez v diffu. `nil` = do `Změněných souborů` se u tohohle PR nekouklo.
    var anchor: DiffScrollAnchor?
    /// Byla ta záložka otevřená **odkazem** (#531)? Bez toho by po restartu ztratila pilulku
    /// `mimo zdroje` a s ní i odpověď na „proč tenhle PR není ve frontě“.
    var openedByLink: Bool

    init(
        pullRequest: PRIdentifier,
        tab: PullRequestTab,
        anchor: DiffScrollAnchor? = nil,
        openedByLink: Bool = false
    ) {
        self.pullRequest = pullRequest
        self.tab = tab
        self.anchor = anchor
        self.openedByLink = openedByLink
    }
}

/// Co bylo otevřené, když aplikace skončila (#527).
///
/// **Snímek, ne log.** Zapisuje se celý při každé změně záložky a čte se **jednou** při startu,
/// takže nic neroste a nemusí se nic uklízet: velikost je velikost pruhu záložek. Je to tentýž
/// tvar jako `announced.json` (`AnnouncedPullRequests`) a ze stejného důvodu.
struct OpenTabs: Codable, Hashable, Sendable {
    /// Záložky **v pořadí, ve kterém stály v pruhu**. Pořadí je součást stavu, ne detail:
    /// `⌃Tab` po nich cyklí a přeskládaný pruh je po restartu vidět.
    var tabs: [OpenTab]
    /// Který pull request byl vidět. `nil` = domácí záložka.
    ///
    /// **Identifikátor, ne index.** Index by po vypadnutí jedné záložky ukazoval na jinou —
    /// a tady se zapisuje snímek, který se čte po restartu, kdy už seznam nemusí být týž.
    var active: PRIdentifier?

    static let none = OpenTabs(tabs: [], active: nil)

    init(tabs: [OpenTab], active: PRIdentifier?) {
        self.tabs = tabs
        self.active = active
    }

    var isEmpty: Bool { tabs.isEmpty }

    /// Aktivní pull request, **jen když je mezi záložkami**. Snímek může být rozpadlý
    /// (ručně editovaný soubor), a aktivní záložka, která v pruhu není, znamená okno bez
    /// jediné zvýrazněné záložky nad prázdnou plochou.
    var activeAmongTabs: PRIdentifier? {
        guard let active, tabs.contains(where: { $0.pullRequest == active }) else { return nil }
        return active
    }
}
