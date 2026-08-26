import Foundation

/// Co je v tabu `Zeptat se` na obrazovce (#452).
///
/// Výčtem, ne příznaky vedle sebe: kombinace „prázdno a zároveň běží odpověď“ neexistuje
/// (běžet může jedině to, na co se někdo zeptal) a stav, který se nedá napsat, se nedá ani
/// omylem nakreslit.
enum AskTabContent: Equatable, Sendable {
    /// Nikdo se zatím na nic nezeptal — místo prázdné plochy otázky k odpíchnutí.
    ///
    /// Nese je **tenhle případ**, ne view: jsou to data, o kterých se rozhoduje, a rozhodnutí
    /// patří do `Policy`. Kdyby je držel view, nešlo by o nich nic tvrdit testem.
    case empty(tips: [String])
    /// Rozhovor. `isAnswering` znamená prstýnek **na místě příští bubliny** — odpověď přijde
    /// sem, tak ať je vidět, kde na ni čekat.
    case thread(messages: [AskMessage], isAnswering: Bool)

    /// Kreslí se `Nový rozhovor`? (#452)
    ///
    /// **V prázdném tabu ne** — nemá co zahodit, a tlačítko, které v tu chvíli nedělá nic, je
    /// otázka, na kterou obrazovka neodpovídá. Je to vlastnost **tohohle výčtu**, ne `if` ve
    /// view: „je co zahodit“ je totéž rozhodnutí jako „co je na obrazovce“, takže se počítá tam,
    /// kde se to rozhoduje, a dá se o něm něco tvrdit testem.
    var offersReset: Bool {
        switch self {
        case .empty: false
        case .thread: true
        }
    }
}

/// Jeden chip v pruhu `ví o tomhle PR:` (#452).
///
/// Je to výčet toho, co aplikace do promptu **doopravdy dá**, ne toho, co o PR ví — proto
/// se skládá z týchž hodnot, ze kterých se skládá materiál (`Policy.askBrief`). Chip, který
/// by tvrdil víc, je text tvrdící víc, než data unesou.
struct AskContextChip: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case diff
        case findings
        case comments
        case checks
    }

    let kind: Kind
    let count: Int
    /// Kreslí se u chipu puntík, a jakou barvu má? `nil` = bez puntíku.
    ///
    /// Jediný, který ho má, je `nálezy` — a jedině tehdy, když mezi nimi něco blokuje. Puntík
    /// u počtu komentářů by z údaje o množství udělal upozornění.
    let isBlocking: Bool

    var id: String { kind.rawValue }

    /// Text chipu — počet a podstatné jméno v pádu, který k němu patří.
    var label: String {
        switch kind {
        case .diff: Plural.czech(count, one: "soubor diffu", few: "soubory diffu", many: "souborů diffu")
        case .findings: Plural.czech(count, one: "nález", few: "nálezy", many: "nálezů")
        case .comments: Plural.czech(count, one: "komentář", few: "komentáře", many: "komentářů")
        case .checks: Plural.czech(count, one: "check", few: "checky", many: "checků")
        }
    }
}

extension Policy {
    /// Otázky k odpíchnutí v prázdném tabu (#452).
    ///
    /// **Klik je rovnou odešle** — jedno kliknutí je celý jejich smysl. Do prvního proklikání
    /// otázku jen předvyplnily do pole a tady stálo, že se proto dají přepsat; zahodilo se to,
    /// protože předvyplněná otázka chce po člověku **druhý klik na tomtéž místě**, kde měl stačit
    /// první. Přepsat se dá pořád — jen se napíše do pole místo kliknutí na nabídku. Cena je
    /// zaplacená session za jeden klik, a ta je vidět: každá bublina má u sebe útratu.
    ///
    /// **Nabídka se řídí tím, co na PR je**, ne pevným seznamem. Otázka „Který z těch nálezů je
    /// doopravdy problém?“ je nad PR bez nálezů dotaz na nic — nechá tedy session projít diff
    /// a odpovědět „žádné tam nejsou“ za dolar. Skládá se proto z **týchž chipů**, které kreslí
    /// pruh `ví o tomhle PR:`: dvě různá čísla o jedné věci na jedné obrazovce jsou horší než
    /// jedna otázka míň, a jediná pojistka, která to uhlídá, je společný zdroj — ne dvě místa,
    /// která počítají totéž.
    ///
    /// **Počet se píše číslicí**, i když ho návrh v próze vysází slovem („z těch tří nálezů“):
    /// v pruhu nad tím stojí `3 nálezy`, takže shodu je vidět a dá se o ní něco tvrdit. Číslovka
    /// slovem by znamenala druhou tabulku tvarů vedle `Plural` a překlad mezi dvěma zápisy téhož
    /// čísla v každém testu.
    static func askTips(context chips: [AskContextChip]) -> [String] {
        let findings = chips.first { $0.kind == .findings }?.count ?? 0
        return [
            "Co v tomhle PR nejvíc riskuje?",
            findingsTip(count: findings),
            "Co bych měl prověřit, než tohle schválím?",
        ]
        .compactMap { $0 }
    }

    /// Otázka na nálezy — `nil`, když žádné nejsou.
    ///
    /// Jediný nález dostane vlastní větu: „Který z těch 1 nálezů“ je česky nesmysl a „Který
    /// z těch nálezů“ by u jednoho tvrdilo, že je z čeho vybírat.
    private static func findingsTip(count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "Je ten jediný nález doopravdy problém?"
        default: "Který z těch \(count) nálezů je doopravdy problém?"
        }
    }

    /// Co se v tabu kreslí.
    ///
    /// **Běh bez jediné zprávy je pořád `empty`**, a je to schválně: otázka se do rozhovoru
    /// zapisuje **dřív**, než se session spustí (viz `AppStore+Ask`), takže tenhle stav znamená
    /// „něco běží a nikdo se na nic nezeptal“ — tedy rozpor, ze kterého se nemá kreslit prstýnek
    /// nad prázdnem.
    ///
    /// `context` jsou tytéž chipy, které se kreslí v pruhu `ví o tomhle PR:` — nabídka otázek
    /// z nich vychází, aby nemohla tvrdit jiná čísla než pruh o kus výš.
    static func askTab(
        conversation: AskConversation?,
        isAnswering: Bool,
        context chips: [AskContextChip] = []
    ) -> AskTabContent {
        let messages = conversation?.messages ?? []
        guard !messages.isEmpty else { return .empty(tips: askTips(context: chips)) }
        return .thread(messages: messages, isAnswering: isAnswering)
    }

    /// Chipy `ví o tomhle PR:`.
    ///
    /// **Nula chip nedostane.** „0 checků“ je pravdivé, ale v pruhu, který odpovídá na „co o PR
    /// ví“, se čte jako selhání — a prázdný pruh je poctivější: co tam není, o tom se nemluví.
    /// Diff je jediný, který se bez chipu neobejde… i on: PR bez načteného diffu má nulu a chip
    /// by nad ním tvrdil, že se něco spočítalo.
    static func askContextChips(
        diffFiles: Int,
        findings: Int,
        blockingFindings: Int,
        comments: Int,
        checks: Int
    ) -> [AskContextChip] {
        [
            AskContextChip(kind: .diff, count: diffFiles, isBlocking: false),
            AskContextChip(kind: .findings, count: findings, isBlocking: blockingFindings > 0),
            AskContextChip(kind: .comments, count: comments, isBlocking: false),
            AskContextChip(kind: .checks, count: checks, isBlocking: false),
        ]
        .filter { $0.count > 0 }
    }

    /// Co stojí u prstýnku, dokud session neřekla, co dělá.
    ///
    /// **Ne prázdný řádek.** Prstýnek sám o sobě říká „něco se děje“, ale ne co — a první
    /// události ze streamu chodí až po startu session, což je jednotky sekund. Prázdno v té
    /// mezeře vypadá jako zaseknuté okno.
    static let askStartingActivity = "přemýšlí…"

    /// Co session právě dělá, do řádku u prstýnku (#452).
    ///
    /// **Sloveso podle nástroje, ne jméno nástroje.** `Read` v okně nic neřekne; „čte
    /// SecretClient.php“ ano — a je to zároveň jediné místo, kde je vidět, že session doopravdy
    /// otevírá kód, ne odpovídá z materiálu.
    ///
    /// Neznámý nástroj dostane obecnou větu, ne své jméno: sada je vyjmenovaná (`AskCommand`),
    /// takže sem nic jiného přijít nemá — a kdyby přišlo, je „pracuje“ pravdivější než jméno,
    /// které v okně nikomu nic neřekne.
    static func askActivity(of tool: ToolAttempt, inside worktree: URL?) -> String {
        let detail = tool.shortened(inside: worktree).flatMap { $0.isEmpty ? nil : $0 }
        switch tool.name {
        case "Read": return detail.map { "čte \($0)" } ?? "čte soubor…"
        case "Grep": return detail.map { "hledá \($0)" } ?? "hledá v kódu…"
        case "Glob": return detail.map { "hledá soubory \($0)" } ?? "hledá soubory…"
        case "Bash": return detail.map { "pouští \($0.singleLine)" } ?? "pouští git…"
        default: return "pracuje…"
        }
    }

    /// Bere si tenhle tab `⏎` pro sebe? (#452)
    ///
    /// V detailu PR je `⌘⏎` zabrané na **otevření potvrzení odeslání** (#151) a od #441 je vedle
    /// něj `⌃⏎`. Composer v tabu `Zeptat se` má ale odesílat otázku — a dvě tlačítka s toutéž
    /// kombinací v jednom okně znamenají, že vyhraje **to zaregistrované později** (#184), tedy
    /// stav, který se pozná jedině tím, že jedna ze zkratek „nefunguje“.
    ///
    /// Řeší se to tím vzorcem, který je v tomhle okně zavedený u `⌘2` a `⎋`: zkratka **okna** se
    /// v tom tabu **zakáže** a klávesa propadne dál, tomu, kdo je na obrazovce. Zakázané tlačítko
    /// klávesu nebere.
    ///
    /// Funkce nad výčtem, ne vlastnost `PullRequestTab`: je to tvrzení o **kolizi zkratek v okně**,
    /// ne fakt o tabu jako `czechLabel`. Vlastnost by svedla ohnout na totéž i `showsReviewPanel`,
    /// a to je přesně ta záměna, před kterou `PullRequestTab.showsReviewPanel` varuje.
    static func claimsReturnShortcut(_ tab: PullRequestTab) -> Bool {
        switch tab {
        case .overview, .filesChanged, .commits, .conversation, .checks, .findings, .progress: false
        case .ask: true
        }
    }
}
