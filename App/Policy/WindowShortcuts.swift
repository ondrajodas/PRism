import Foundation

/// Modifikátory zkratky. Vlastní typ, ne `EventModifiers` ze SwiftUI, protože katalog žije
/// v `Policy` — a ta se testuje bez kreslení.
///
/// **Pořadí bitů je pořadí glyfů** (`⌘⌃⌥⇧`). Díky tomu se popiska skládá iterací přes ten výčet
/// a nedá se napsat `⌘⇧P` jednou a `⇧⌘P` podruhé.
///
/// Je to pořadí z **návrhu** (`docs/navrh.html`: `⌘⇧P`, `⌘⌥S`), ne z menu macOS, které píše
/// `⌃⌥⇧⌘`. Aplikace to tak kreslí od #333 a #181 a mockup je zdroj toho, jak má vypadat —
/// srovnat se s menu by znamenalo přepsat všechny kapsle v okně kvůli údaji, který se stejně
/// nikde nepotkají vedle sebe.
struct ShortcutModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let control = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)

    var glyphs: String {
        var text = ""
        if contains(.command) { text += "⌘" }
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        return text
    }
}

/// Klávesová zkratka, kterou registruje **hlavní okno** (#441).
///
/// Existuje jako katalog v `Policy` ze dvou důvodů, a oba se v repu už jednou vymstily:
///
/// 1. **Dvě tlačítka se stejnou kombinací znamenají, že vyhraje to zaregistrované později**
///    (#151, #184) — a pozná se to jedině tak, že jedna ze zkratek „nefunguje“. Dokud byly
///    kombinace rozseté po `ContentView`, `PullRequestDetailView`, `DiffView` a `DashboardView`,
///    nešlo se na kolizi zeptat jinak než grepem v hlavě. Katalog na jednom místě se dá projít
///    vyčerpávajícím testem.
/// 2. **Kreslená zkratka musí být skutečná.** Paleta ⌘K i nápovědy tlačítek psaly kombinaci
///    ručně (`"⌘⇧R"` vedle `KeyEquivalent("r")` v témže volání), takže se změna klávesy
///    s popiskou rozešla potichu. Popiska je proto **odvozená** z kombinace, ne opsaná vedle ní.
struct WindowShortcut: Equatable, Sendable {
    /// Co zkratka udělá. Enum, ne řetězec: `switch` v katalogu je tím pádem vyčerpávající, takže
    /// nová akce si vynutí rozhodnutí, jakou klávesu dostane.
    enum Action: Hashable, Sendable {
        // Hlavička okna (`ContentView`) — platí i z domácí záložky.
        case palette
        case nextTab
        case previousTab
        case closeTab
        case refresh
        case openSection(RailSection)
        // Detail pull requestu (`PullRequestDetailView`).
        case nextFinding
        case previousFinding
        case reviewPanel
        case backFromCommit
        case openSubmission
        case agentPrompt
        case cancelReview
        /// Zásuvka s terminálem (#459) — **jediná zkratka, která terminálu neustupuje.**
        case toggleTerminal
        // Obsah detailu a domácí záložky.
        case fileTree
        case runAllReviews
        case openDraft
    }

    /// Klávesa. Speciální klávesy se vyjmenovávají, protože se znakem zapsat nejdou.
    enum Key: Hashable, Sendable {
        case character(Character)
        case tab
        /// `⇧⇥` je pro AppKit **jiná klávesa než `⇥`** (#245) — viz `KeyEquivalent.backTab`.
        case backTab
        case `return`
        /// `⎋`, ale zapsané jako `.cancelAction` (#317): je to táž klávesa, jenže v tomhle okně
        /// je zavedený ten zápis a míchat dva znamená hádat, který AppKit spáruje dřív.
        case cancelAction
        case upArrow
        case downArrow

        /// Jak se klávesa kreslí v paletě a v nápovědě.
        ///
        /// **`Tab` a `esc` slovem, ne glyfem** (`⇥`, `⎋`), a je to změřené, ne vkus: monospace
        /// systémové písmo, kterým se kapsle sází (`.AppleSystemUIFontMonospaced-Regular`), ty dva
        /// glyfy **nemá** — `CTFontGetGlyphsForCharacters` vrátí `false`. Text by se tím propadl do
        /// náhradního písma, tedy do jiné šířky i kresby než zbytek kapsle. `⌘`, `⌃`, `⌥`, `⇧`,
        /// `⏎`, `↑` a `↓` v něm jsou, takže se kreslí glyfem. Aplikace to tak psala i před #441
        /// (`⌃Tab` v nápovědě pruhu, `esc zavřít` v patce palety), takže se tím nic nemění.
        var glyph: String {
            switch self {
            case .character(let character): String(character).uppercased()
            case .tab, .backTab: "Tab"
            case .return: "⏎"
            case .cancelAction: "esc"
            case .upArrow: "↑"
            case .downArrow: "↓"
            }
        }
    }

    /// Jedna kombinace kláves.
    struct Combination: Hashable, Sendable {
        var key: Key
        var modifiers: ShortcutModifiers = []

        /// `⌘R`, `⌃1`, `⌥↓` — to, co se kreslí.
        var display: String { modifiers.glyphs + key.glyph }
    }

    /// Titulek tlačítka. U schovaných zkratek se nikde nekreslí, ale píše se poctivě — je to
    /// jediné, z čeho se v kódu pozná, co ta zkratka dělá.
    var title: String
    /// Kombinace, která se **kreslí**. Uložená zvlášť od ostatních schválně: kdyby to bylo pole,
    /// dal by se katalog složit s prázdným, a popiska by pak musela hádat, co nakreslit.
    var primary: Combination
    /// Další kombinace na **tutéž akci**.
    ///
    /// Existují kvůli české klávesnici (#441): `keyboardShortcut` páruje na **znak**, a pod
    /// klávesami `1`–`5` je v české mapě `+ ě š č ř`. Samotné `⌃1` na ní tedy nezabere vůbec.
    /// Dvě tlačítka se **stejnou akcí a jinou klávesou** jsou v pořádku — to, co se v tomhle okně
    /// rozbíjí, jsou dvě se **stejnou kombinací** (#151, #184).
    var alternates: [Combination] = []

    /// Všechny kombinace, které tu akci spustí. Nikdy prázdné.
    var combinations: [Combination] { [primary] + alternates }

    /// Zkratka tak, jak se kreslí — vždycky ta primární.
    ///
    /// **Alternativy se nekreslí**, a je to vědomé: v řádku palety je na kombinaci jedna kapsle
    /// a `⌃1 / ⌃+` by z ní udělalo dvě kvůli údaji, který se člověk naučí jednou. Na české
    /// klávesnici je navíc číslice na téže klávese natištěná, takže `⌃1` je i tam poznat.
    var display: String { primary.display }
}

extension Policy {
    /// Katalog zkratek hlavního okna (#441) — **jediné místo, kde se rozhoduje, co je pod kterou
    /// klávesou**.
    ///
    /// Co v něm **není**: zkratky sheetů (zavření potvrzení odeslání, sheetu s kódem, se surovou
    /// session), okna nastavení, okna novinek a palety ⌘K. Jsou to vlastní okna nebo překryv, který
    /// existuje jen otevřený — a překryv i sheet si klávesu berou samy, takže se s oknem nepotkají.
    /// Tam, kde by se překryly, je zkratka **okna** zakázaná (`⌘⏎` a `⎋` nad otevřenou paletou):
    /// zakázané tlačítko klávesu nebere a propadne dál.
    ///
    /// `⌘,` (nastavení) v katalogu taky není: registruje ho scéna `Settings`, ne okno. Kreslí se
    /// v paletě jako literál a je to jediné takové místo.
    static func windowShortcut(_ action: WindowShortcut.Action) -> WindowShortcut {
        switch action {
        case .palette:
            return WindowShortcut(
                title: "Najít v okně",
                primary: .init(key: .character("k"), modifiers: .command)
            )
        case .nextTab:
            return WindowShortcut(
                title: "Další záložka",
                primary: .init(key: .tab, modifiers: .control)
            )
        case .previousTab:
            return WindowShortcut(
                title: "Předchozí záložka",
                primary: .init(key: .backTab, modifiers: [.control, .shift])
            )
        // `⌃W`, ne `⌘W`: `⌘W` patří systému (zavře okno) a `Control` je v tomhle okně už
        // navigace mezi záložkami. Zavírá se **aktivní záložka**, ne vybraný řádek v seznamu.
        case .closeTab:
            return WindowShortcut(
                title: "Zavřít záložku",
                primary: .init(key: .character("w"), modifiers: .control)
            )
        case .refresh:
            return WindowShortcut(
                title: "Obnovit seznam",
                primary: .init(key: .character("r"), modifiers: .command)
            )
        // Sekce railu jsou na `Control`u ze stejného důvodu jako zavírání záložky: `⌘1` a `⌘2`
        // patří uvnitř PR stromu souborů a panelu, takže by se srazily.
        case .openSection(let section):
            let keys = railSectionKeys(of: section)
            return WindowShortcut(
                title: "Otevřít sekci \(section.title)",
                primary: .init(key: .character(keys.digit), modifiers: .control),
                alternates: [.init(key: .character(keys.czech), modifiers: .control)]
            )
        case .nextFinding:
            return WindowShortcut(
                title: "Další nález",
                primary: .init(key: .downArrow, modifiers: .option)
            )
        case .previousFinding:
            return WindowShortcut(
                title: "Předchozí nález",
                primary: .init(key: .upArrow, modifiers: .option)
            )
        case .reviewPanel:
            return WindowShortcut(
                title: "Panel s mým review",
                primary: .init(key: .character("2"), modifiers: .command)
            )
        case .backFromCommit:
            return WindowShortcut(
                title: "Zpět na seznam commitů",
                primary: .init(key: .cancelAction)
            )
        // `⌃⏎` je **druhá klávesa k `⌘⏎`**, ne náhrada: `⌘⏎` je v tomhle okně zavedené a bere ho
        // i paleta ⌘K (otevřít výsledek na GitHubu), takže nad otevřenou paletou je zkratka
        // detailu zakázaná a `⌃⏎` je cesta, která se s ní nepotká. Obojí otevírá **potvrzení**,
        // neodesílá (tvrdá podmínka č. 1) — v samotném sheetu zkratka na odeslání není a nebude.
        case .openSubmission:
            return WindowShortcut(
                title: "Otevřít potvrzení odeslání",
                primary: .init(key: .return, modifiers: .command),
                alternates: [.init(key: .return, modifiers: .control)]
            )
        case .agentPrompt:
            return WindowShortcut(
                title: "Sestavit zadání pro agenta",
                primary: .init(key: .character("p"), modifiers: [.command, .shift])
            )
        // `⌘.` je systémové „přeruš, co běží“ — a přesně to tady dělá: zabije běžící review
        // na PR, který je v okně.
        case .cancelReview:
            return WindowShortcut(
                title: "Zastavit běžící review",
                primary: .init(key: .character("."), modifiers: .command)
            )
        // `` ⌃` `` je zkratka terminálu na macOS napříč aplikacemi (VS Code, Xcode, JetBrains) —
        // a hlavně **jediná okenní zkratka, která platí i s fokusem v zásuvce** (#459). Kdyby byla
        // na `⌘`, srazila by se s tím, co `⌘` v okně dělá; kdyby byla na `Control`u a nebyla
        // výjimkou, nešla by zásuvka zavřít klávesnicí vůbec.
        //
        // **Alternativa `⌃;` je pro českou klávesnici**, ze stejného důvodu jako `⌃+ěščř` u sekcí
        // railu: `keyboardShortcut` páruje na **znak**, a klávesa vlevo od `1` má v české mapě
        // `;`, ne `` ` ``. Bez ní by se zásuvka na české mapě nedala otevřít.
        case .toggleTerminal:
            return WindowShortcut(
                title: "Terminál",
                primary: .init(key: .character("`"), modifiers: .control),
                alternates: [.init(key: .character(";"), modifiers: .control)]
            )
        case .fileTree:
            return WindowShortcut(
                title: "Strom souborů",
                primary: .init(key: .character("1"), modifiers: .command)
            )
        case .runAllReviews:
            return WindowShortcut(
                title: "Pustit review na vše, co neběželo",
                primary: .init(key: .character("r"), modifiers: [.command, .shift])
            )
        case .openDraft:
            return WindowShortcut(
                title: "Dopsat rozdělané review",
                primary: .init(key: .character("d"), modifiers: [.command, .shift])
            )
        }
    }

    /// Klávesy sekce railu: číslice a **znak, který je na téže klávese v české mapě**.
    ///
    /// Vyjmenované `switch`em nad `RailSection`, takže šestá sekce si vynutí rozhodnutí, co
    /// dostane — a ne aby se tiše přidala bez zkratky. Pod `1`–`5` je v české mapě `+ ě š č ř`;
    /// `charactersIgnoringModifiers` ignoruje všechny modifikátory kromě shiftu, takže se
    /// s `Control`em doručí právě tenhle znak.
    private static func railSectionKeys(of section: RailSection) -> (digit: Character, czech: Character) {
        switch section {
        case .overview: ("1", "+")
        case .queue: ("2", "ě")
        case .mine: ("3", "š")
        case .drafts: ("4", "č")
        case .activity: ("5", "ř")
        }
    }

    /// Všechny akce v katalogu — pro vyčerpávající test kolizí.
    ///
    /// Ručně vypsané, protože `Action` má u sekce railu asociovanou hodnotu a `CaseIterable`
    /// tím pádem nejde. Že se na nový případ nezapomnělo, hlídá tvrzení o počtu
    /// (`WindowShortcutsTests`) — vyjmenovaný počet, ne „aspoň tolik“.
    static let windowShortcutActions: [WindowShortcut.Action] =
        [.palette, .nextTab, .previousTab, .closeTab, .refresh]
        + RailSection.allCases.map(WindowShortcut.Action.openSection)
        + [
            .nextFinding, .previousFinding, .reviewPanel, .backFromCommit,
            .openSubmission, .agentPrompt, .cancelReview, .toggleTerminal,
            .fileTree, .runAllReviews, .openDraft,
        ]

    static let windowShortcuts: [WindowShortcut] = windowShortcutActions.map(windowShortcut)

    /// Nápověda tlačítka se zkratkou v závorce — `Obnovit seznam (⌘R)`, jak to má `⌘,`
    /// u nastavení.
    ///
    /// **Jedno místo, aby se kombinace nedala opsat vedle té skutečné.** Do #441 stálo v repu
    /// devět takových závorek jako literál (`(⌘1)`, `(⌘2)`, `(⌥↓)`, `⌘⇧R`, …) a změna klávesy
    /// by o nich nevěděla.
    static func shortcutHelp(_ text: String, _ action: WindowShortcut.Action) -> String {
        "\(text) (\(windowShortcut(action).display))"
    }

    /// Co zavře `⌃W` — `nil` znamená, že není co zavírat.
    ///
    /// **Aktivní záložka, ne vybraný řádek v seznamu**: `selection` je „na co se v seznamu
    /// kouká“, kdežto zavřít se má to, co je zrovna v okně. Na domácí záložce se nesmí stát
    /// **nic** — zavřít poslední otevřené review, na které se člověk ani nedíval, je horší než
    /// zkratka, která nedělá nic. Zakázané tlačítko klávesu nebere, takže propadne dál.
    static func closableTab(in tab: WindowTab) -> PRIdentifier? { tab.pullRequest }
}
