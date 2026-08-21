import Foundation

/// Jedna událost přepisu surové session (#327).
///
/// **Vysázená je jen hlavička** (čas, druh, čeho se to týká); `body` je text tak, jak v transcriptu
/// stojí — jen ořezaný na strop události (`Policy.rawSessionEventBytes`). Je to schválně tak málo:
/// „surová“ znamená **úplná**, ne *v JSONu*, a čím víc by se z transcriptu překreslovalo, tím víc
/// by z toho byl druhý pohled na to, co už kreslí výpis kroků.
struct TranscriptEvent: Identifiable, Hashable, Sendable {
    /// Druh události. **Vyjmenovaný**, protože z něj se skládá popisek v hlavičce — a neznámý
    /// `type` z novější verze CLI má být vidět jako neznámý (`system`), ne zmizet.
    enum Kind: Hashable, Sendable {
        /// Systémová událost — nese svůj `type`/`subtype`, aby se poznalo, co to bylo.
        case system(String)
        /// Text, který session dostala jako zadání (`user` event s obsahem v `String`u).
        case prompt
        /// Materiál vložený do session (blok `text` v `user` eventu) — typicky obsah skillu.
        case input
        /// Próza modelu. Přesně to, co výpis kroků schválně zahazuje.
        case prose
        /// `thinking` blok.
        case thinking
        /// Pokus o nástroj; nese jméno tak, jak si o něj model řekl.
        case tool(String)
        /// `ReportFindings` — vlastní druh, ne `tool`: je to výstup review, ne krok nad kódem.
        case report
        /// Odpověď nástroje, ke které se **nenašel** pokus. Stává se to u okna: `tool_use` leží
        /// před jeho začátkem. Vlastní druh, protože „výsledek bez kroku“ je jiné tvrzení než krok.
        case result
        /// Obrázek. Base64 se **nevypisuje nikdy** — jen se přizná, že tam je a kolik váží.
        case image(bytes: Int)
        /// Řádek, který se nepodařilo přečíst. Vlastní druh, ne zahození: tiše spolknutý řádek
        /// vypadá jako řádek, který v transcriptu nebyl.
        case unreadable
    }

    /// Pořadí v okně. `Date` na identitu nestačí — `last-prompt` časovou značku nemá vůbec
    /// a dva eventy umí padnout do stejné milisekundy.
    let id: Int
    /// `nil` = řádek časovou značku nenese (`last-prompt`). Kreslí se prázdno, ne domyšlený čas
    /// z předchozí události: ten by tvrdil, kdy se to stalo.
    let at: Date?
    let kind: Kind
    /// Čeho se to týká — cesta, příkaz, velikost, počet nálezů. `nil` = není co dodat.
    var subject: String?
    /// Tělo tak, jak v transcriptu stojí, po ořezu na strop události. `nil` = tělo nemá.
    var body: String?
    /// Co za ořezem těla zbylo (`… + 61 řádků nad strop události`). `nil` = neořezalo se.
    ///
    /// Nese se **vedle** těla, ne v něm: ořez se přiznává **na místě, kde nastal**, a text
    /// přiznání má jinou barvu než tělo.
    var bodyCut: String?
    /// Nástroj se neprovedl, protože chybí povolení.
    ///
    /// **Štítek, ne červený řádek** — tatáž úvaha jako u výpisu kroků (#326): read-only reviewer
    /// je tvrdá podmínka č. 2, takže odmítnutí je normální stav běhu. Červený řádek by sváděl
    /// ten režim vypnout.
    var isDenied = false
}

/// Snímek transcriptu k okamžiku otevření (#327).
///
/// **Snímek, ne sledování rostoucího souboru.** Sledování už v okně je, o patro výš (živý výpis
/// kroků, #325), a dvě věci nad touž session jsou dvě místa, kde se dá splést pořadí. Kolik od té
/// chvíle přibylo, hlásí patička sheetu; vedle je `Načíst znovu`.
struct RawTranscript: Equatable, Sendable {
    var events: [TranscriptEvent] = []
    /// Kolik bajtů souboru se do okna nevešlo. `0` = okno je celý soubor.
    ///
    /// **Bajty, ne události.** Kolik událostí je před oknem, by se dalo zjistit jedině přečtením
    /// celého souboru — tedy tou cenou, kvůli které okno existuje (největší změřený transcript má
    /// 53 MB). Odhad by byl text, který tvrdí víc, než data unesou.
    var omittedBytes = 0
    /// Velikost souboru ve chvíli snímku. Z rozdílu proti dnešní velikosti je přírůstek v patičce.
    var fileBytes = 0
    /// Kdy se snímek vzal — hlavička to říká, protože za běhu soubor roste dál.
    var takenAt = Date.distantPast
    /// Kolik řádků okna se nepodařilo přečíst.
    ///
    /// Počítá se i tehdy, když se z nich stane událost druhu `unreadable`: hlavička o tom mluví
    /// souhrnně, kdežto událost ukazuje **to místo**, kde se to stalo.
    var unreadableLines = 0

    var isTruncated: Bool { omittedBytes > 0 }
}

/// Co se v sheetu se surovou session doopravdy ukazuje (#327).
///
/// **Tři různá „přepis tu není“**, která se nesmí slít ani hláškou, ani nabídnutými akcemi — je to
/// tatáž úvaha, jaká drží oddělené `čisté` a `session spadla`. Který stav nabízí co, rozhoduje
/// `Policy.rawSessionActions(for:)`.
enum RawTranscriptState: Equatable, Sendable {
    /// Čte se z disku. Sheet se otevírá hned, obsah dorazí za chvíli.
    case loading
    case shown(RawTranscript)
    /// Transcript **není** — konečná odpověď. Bez `Načíst znovu`, protože se nezmění.
    case missing
    /// Je, ale nedal se přečíst. Věta je z chyby, ne vymyšlená.
    case unreadable(String)
    /// Je, ale není v něm co ukázat. Nese velikost, aby hláška nelhala: prázdný soubor a soubor,
    /// ze kterého se nedala přečíst ani jedna událost, jsou dvě různé věty.
    case empty(bytes: Int)
}

/// Akce v patičce sheetu.
enum RawSessionAction: Hashable, Sendable {
    case close
    case copyTranscript
    case copyPath
    case revealInFinder
    case reload
}

/// Kterou session sheet ukazuje (#327).
///
/// **Bez `session_id` a bez pracovního stromu se tlačítko nekreslí** — z těch dvou se cesta
/// k transcriptu odvozuje (`TranscriptLocation`), takže bez nich není co otevřít. Je to tatáž
/// podmínka jako u `Zkopírovat resume`; rozhoduje o ní `Policy.rawSessionTarget(of:slug:)`.
struct RawSessionTarget: Identifiable, Hashable, Sendable {
    let sessionID: String
    let worktree: URL
    /// Jméno skillu do titulku sheetu.
    let skill: String
    /// `owner/repo#412` do podtitulku — ať je z otevřeného sheetu poznat, čí session to je.
    let slug: String

    /// Identita sheetu. `sessionID` je unikátní na běh, takže dvě dráhy otevřou různý obsah.
    var id: String { sessionID }
}
