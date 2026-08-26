import Foundation

/// Jedna zpráva rozhovoru v tabu `Zeptat se` (#452).
///
/// **Bublina, ne karta.** Kdo mluví, se pozná stranou a barvou, takže se v modelu drží
/// `speaker` a nic víc — jméno, avatar ani hlavička u zprávy nejsou, protože mluvčí jsou
/// právě dva a oba jsou z pohledu okna známí.
struct AskMessage: Codable, Equatable, Sendable, Identifiable {
    enum Speaker: String, Codable, Sendable {
        /// Moje otázka — vpravo, na akcentu.
        case mine
        /// Odpověď — vlevo, na tichém podkladu.
        case claude
    }

    let id: UUID
    let speaker: Speaker
    let text: String
    /// Kdy zpráva vznikla. U odpovědi je to okamžik, kdy session doběhla.
    let at: Date
    /// Soubory, které si session cestou k odpovědi otevřela — „co si přečetl“ **nad** bublinou.
    ///
    /// Je to **doklad, ne obsah**: prázdné pole znamená, že session odpověděla z toho, co měla
    /// v promptu. Nedopočítává se z ničeho jiného než ze streamu, takže se nedá splést s tím,
    /// co se jí *nabídlo*.
    var readFiles: [String] = []
    /// Čas a cena té jedné odpovědi — drobně pod bublinou. `nil` = session je nenahlásila
    /// (zabitý běh), a to není nula: nula by tvrdila, že odpověď byla zdarma.
    var usage: RunUsage?
    /// Proč odpověď není celá. `nil` = doběhla.
    ///
    /// Ukládá se **se zprávou**, ne vedle rozhovoru: hláška patří k té odpovědi, u které se to
    /// stalo, a příští otázka ji nesmí přepsat ani smazat.
    var failure: String?

    init(
        id: UUID = UUID(),
        speaker: Speaker,
        text: String,
        at: Date,
        readFiles: [String] = [],
        usage: RunUsage? = nil,
        failure: String? = nil
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.at = at
        self.readFiles = readFiles
        self.usage = usage
        self.failure = failure
    }
}

/// Rozhovor nad jedním pull requestem (#452).
///
/// **Ukládá se k PR, ne k `headSha`** — a je to vědomá výjimka z toho, jak se v téhle aplikaci
/// klíčuje všechno ostatní kolem review. Tvrdá podmínka č. 5 mluví o **nálezech**: ty nesmí
/// platit pro kód, který už neexistuje, takže je nový commit zneplatní. Otázka „proč se ten
/// mutex bere kolem celého `fetch`“ ale pushem nezastará — je to rozhovor o záměru, ne tvrzení
/// o řádku. Klíčovat ho commitem by znamenalo, že se rozhovor po každém pushnutí ztratí zrovna
/// ve chvíli, kdy se k němu člověk vrací.
///
/// `sessionID` drží `--resume`, takže druhá otázka navazuje na první. `nil` znamená, že příští
/// otázka založí novou session — tedy že se do promptu musí znovu složit celý kontext PR.
struct AskConversation: Codable, Equatable, Sendable {
    let pullRequest: PRIdentifier
    var messages: [AskMessage] = []
    /// `session_id` poslední odpovědi. **Bere se z každé doběhlé session znovu**, protože
    /// `claude --resume` id **může vrátit jiné** — v naměřeném běhu (viz `docs/claude-cli.md`)
    /// zůstalo totéž, ale spoléhat se na to znamená, že by se změněné id ztratilo a třetí otázka
    /// by navazovala na tu první.
    var sessionID: String?

    init(pullRequest: PRIdentifier, messages: [AskMessage] = [], sessionID: String? = nil) {
        self.pullRequest = pullRequest
        self.messages = messages
        self.sessionID = sessionID
    }

    var isEmpty: Bool { messages.isEmpty }
}
