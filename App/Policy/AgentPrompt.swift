import Foundation

/// Ke kterému PR zadání patří (#333) — a proti čemu vzniklo.
///
/// `headSha` je tady schválně, i když se z něj skládá jen řádka textu: nálezy jsou jím klíčované
/// (tvrdá podmínka č. 5) a zadání se **předává dál**, takže musí jít poznat, proti čemu platí —
/// jinak agent opraví řádky, které mezitím zmizely. `nil` znamená „nevíme“, ne „nezáleží na tom“,
/// a text to v takovém případě říká nahlas.
struct AgentPromptSubject: Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Větev, ze které se merguje. Prázdná = detail ji nenese (starší uložená odpověď) nebo
    /// se ještě nenačetl.
    var branch = ""
    /// Hlava PR. `nil` = zatím nevíme.
    var headSha: String?

    /// Zkrácená hlava do textu — sedm znaků, jak ji píše `git`.
    var shortHead: String? {
        guard let headSha, !headSha.isEmpty else { return nil }
        return String(headSha.prefix(7))
    }
}

/// Které druhy položek jdou do zadání a jestli se k nim přikládá diff hunk (#333).
///
/// **Množina, ne sedm `Bool`ů**: panel je kreslí jednou smyčkou přes `AgentPromptChoice.allCases`,
/// takže nová volba znamená nový případ výčtu a nic víc. Sedm polí by znamenalo sedm řádků
/// v panelu, sedm v testu a sedm míst, kde se dá zapomenout.
struct AgentPromptOptions: Hashable, Sendable {
    private var enabled: Set<AgentPromptChoice>

    init(enabled: Set<AgentPromptChoice>) {
        self.enabled = enabled
    }

    /// Výchozí volba: **všechno nevyřízené a diff hunk**, bez vyřešených vláken a odmítnutých
    /// nálezů. Je to ten stav, ve kterém je zadání odpovědí na „co zbývá opravit“ — a zrovna
    /// proto se ty dvě vypnuté volby v panelu ukazují s počtem, ne aby se schovaly.
    static let standard = AgentPromptOptions(
        enabled: [.findings, .unresolvedThreads, .comments, .reviews, .diffHunks]
    )

    func includes(_ choice: AgentPromptChoice) -> Bool { enabled.contains(choice) }

    mutating func toggle(_ choice: AgentPromptChoice) {
        if enabled.contains(choice) {
            enabled.remove(choice)
        } else {
            enabled.insert(choice)
        }
    }
}

/// Kolik čeho je — jednou pro to, co je k dispozici, a jednou pro to, co je v textu (#333).
///
/// Tentýž typ na obojí schválně: „6 položek z 8“ a „1 vyřešené vynecháno“ je rozdíl dvou týchž
/// tabulek, ne dvě různé věci. Dva typy by znamenaly dvě pravdy o jednom počtu.
struct AgentPromptInventory: Hashable, Sendable {
    private var counts: [AgentPromptChoice: Int]

    init(_ items: [AgentPromptItem]) {
        counts = items.reduce(into: [:]) { counts, item in counts[item.choice, default: 0] += 1 }
    }

    /// Kolik položek téhle volby. `nil` u `diffHunks` — není to druh položky, takže by nula
    /// tvrdila, že se něco spočítalo a nic nevyšlo.
    func count(of choice: AgentPromptChoice) -> Int? {
        guard choice.countsItems else { return nil }
        return counts[choice] ?? 0
    }

    /// Kolik položek dohromady.
    var total: Int { counts.values.reduce(0, +) }
}

/// Hotové zadání pro agenta (#333) — text tak, jak se zkopíruje, a k němu počty.
///
/// **Nese celý text, ne recept na jeho složení.** Sheet ukazuje to, co se zkopíruje (stejné
/// pravidlo jako u potvrzení odeslání), takže text musí vzniknout jednou a putovat dál. Kam jde:
/// do schránky nebo do souboru. Nikam jinam — `ReviewPublishing` se u vlastního PR nepoužívá
/// vůbec (tvrdá podmínka č. 1).
struct AgentPrompt: Identifiable, Hashable, Sendable {
    let subject: AgentPromptSubject
    /// Markdown, seskupený po souborech.
    let text: String
    /// Co všechno se dalo vzít — z toho se kreslí počty u zaškrtávacích řádků.
    let inventory: AgentPromptInventory
    /// Co je v textu.
    let included: AgentPromptInventory
    /// Kolik z položek v textu blokuje (`Policy.isBlocking`).
    let blocking: Int
    /// Byla načtená konverzace? `false` = cizí komentáře se **nemají kde vzít**, a to musí být
    /// vidět v okně i v textu. Prázdný seznam by jinak vypadal jako „nikdo nic nenapsal“.
    let isConversationLoaded: Bool

    /// Identita sheetu — pull request a hlava, proti které zadání vzniklo. **Ne obsah textu:**
    /// sheet je snímek, který se otevře jedním kliknutím a zavře druhým, takže se jeho identita
    /// nemá měnit pod rukama.
    var id: String { "\(subject.pullRequest)@\(subject.headSha ?? "?")" }

    /// Kolik bajtů text má. Do hlavičky sheetu, protože u dlouhého PR je to jediné, z čeho se
    /// pozná, že se do promptu agenta nevejde — a že se má vypnout diff hunk.
    var byteCount: Int { text.utf8.count }

    /// Velikost do popisku. **Stejným formátem jako velikost logu u checků** (`CheckLogText`),
    /// ať se v jednom okně nepíšou bajty dvěma způsoby.
    var sizeText: String { byteCount.formatted(.byteCount(style: .file)) }

    /// Není co předávat. Tlačítko `Sestavit prompt` je pak zakázané s důvodem — prázdný sheet
    /// s hlavičkou a bez položek by vypadal jako rozbitá aplikace.
    var isEmpty: Bool { included.total == 0 }

    /// Kolik položek se do textu nedostalo, protože se jejich volba nezapnula.
    var omittedCount: Int { inventory.total - included.total }
}
