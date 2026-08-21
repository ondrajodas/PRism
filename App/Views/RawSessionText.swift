import Foundation

/// Texty sheetu se surovou session (#327).
///
/// Vlastní typ ze stejného důvodu jako `ReviewerLaneText`: věty, které tvrdí něco o datech, se dají
/// vyčerpat testem jen tehdy, když nejsou schované v těle view.
enum RawSessionText {
    /// **`Ukázat session`, ne `Ukázat surovou session`.** Tlačítko sedí v hlavičce výpisu kroků
    /// vedle pilulky `Sledovat konec`, tedy v úzkém místě, a slovo „surová“ v něm nese nejmíň:
    /// odkud se to otevírá, už samo říká, že jde o tuhle session, a *co* v sheetu je, vysvětluje
    /// nápověda i jeho hlavička. Pojem `Surová session` zůstává v nadpisu sheetu a v dokumentaci —
    /// mění se popis tlačítka, ne jméno té obrazovky.
    static let button = "Ukázat session"
    static let buttonHelp = "Přepis celého transcriptu téhle session — próza, uvažování, výstupy "
        + "nástrojů a systémové události, tedy to, co výpis kroků schválně zahazuje."

    static func title(skill: String) -> String { "Surová session — \(skill)" }

    static func slug(_ target: RawSessionTarget) -> String {
        "\(target.slug) · \(target.sessionID)"
    }

    /// Podtitulek: **snímek, okno a velikost na disku**.
    ///
    /// Že je to snímek, tady stát **musí**: za běhu soubor roste dál, a přepis, který o sobě
    /// mlčí, vypadá jako živý pohled — tedy jako druhé sledování téže session vedle výpisu kroků.
    ///
    /// **Počet událostí celého souboru se netvrdí**, a je to vědomá odchylka od mockupu (ten má
    /// `2 913 událostí ze 4 117`). Zjistit ten druhý počet znamená přečíst celý soubor — tedy
    /// zaplatit zrovna tu cenu, kvůli které okno existuje (53 MB u největšího změřeného
    /// transcriptu) —, a odhad by byl text, který tvrdí víc, než data unesou. Řekne se proto, kolik
    /// událostí je **v okně** a jak je okno velké.
    static func subtitle(_ transcript: RawTranscript) -> String {
        let events = Plural.czech(
            transcript.events.count,
            one: "událost",
            few: "události",
            many: "událostí"
        )
        let taken = transcript.takenAt.formatted(date: .omitted, time: .standard)
        let size = transcript.fileBytes.formatted(.byteCount(style: .file))
        let window = transcript.isTruncated
            ? "konec souboru, \(events) z posledních \(shownBytes(transcript))"
            : "celý soubor, \(events)"
        return "Snímek z \(taken) · \(window) · na disku \(size)"
    }

    /// Kolik bajtů okno pokrývá — velikost souboru bez toho, co se nevešlo.
    private static func shownBytes(_ transcript: RawTranscript) -> String {
        let shown = max(transcript.fileBytes - transcript.omittedBytes, 0)
        return shown.formatted(.byteCount(style: .file))
    }

    /// Řez na začátku textu — **druhé ze tří přiznání** zkrácení (hlavička, řez, ořez události).
    ///
    /// `nil` u neořezaného transcriptu: řez, který tvrdí ořez u celého souboru, je horší než žádný.
    static func topCut(_ transcript: RawTranscript) -> String? {
        guard transcript.isTruncated else { return nil }
        let size = transcript.omittedBytes.formatted(.byteCount(style: .file))
        return "starších \(size) se do okna nevešlo"
    }

    /// Kolik řádků okna se nepodařilo přečíst. `nil` = všechny se přečetly.
    ///
    /// Musí to být vidět **souhrnně v hlavičce**, i když je každý takový řádek zvlášť v přepisu:
    /// jeden nečitelný řádek se dá přerolovat, kdežto „ze čtyř set jich je nečitelných dvě stě“ je
    /// tvrzení o tom, jak moc se dá přepisu věřit.
    static func unreadableLines(_ transcript: RawTranscript) -> String? {
        guard transcript.unreadableLines > 0 else { return nil }
        return Plural.czech(
            transcript.unreadableLines,
            one: "řádek se nepodařilo přečíst",
            few: "řádky se nepodařilo přečíst",
            many: "řádků se nepodařilo přečíst"
        )
    }

    /// Popisek druhu události — to, co je v přepisu vysázené.
    static func kind(_ kind: TranscriptEvent.Kind) -> String {
        switch kind {
        case .system: "systém"
        case .prompt: "zadání"
        case .input: "vstup"
        case .prose: "model"
        case .thinking: "uvažování"
        case .tool(let name): name
        case .report: "ReportFindings"
        case .result: "výsledek"
        case .image: "obrázek"
        case .unreadable: "nečitelný řádek"
        }
    }

    /// Čeho se to týká. U `system` a `image` se skládá z druhu, u ostatních to nese událost sama.
    static func subject(of event: TranscriptEvent) -> String? {
        switch event.kind {
        case .system(let type):
            return [type, event.subject].compactMap { $0 }.joined(separator: " · ")
        case .image(let bytes):
            let size = bytes.formatted(.byteCount(style: .file))
            return "\(size) · base64 se nevypisuje"
        default:
            return event.subject
        }
    }

    /// Štítek odmítnutého nástroje. **Tentýž text jako ve výpisu kroků** — dvě různá slova pro jednu
    /// věc by znamenala, že se z okna nedá poznat, že jde o totéž.
    static let denied = ReviewerLaneText.deniedStep

    // MARK: - Když přepis není

    /// Věta pro stav, ve kterém přepis není. `nil` u `.loading` a `.shown`.
    ///
    /// Tři různá „přepis tu není“ **se nesmí slít ani hláškou** — a proto se tady rozhoduje výčtem,
    /// ne skládáním jedné věty s doplňky.
    static func failure(_ state: RawTranscriptState) -> String? {
        switch state {
        case .loading, .shown:
            return nil
        case .missing:
            // **Příčina se netvrdí** (nálezem Copilota na #408): `nil` znamená „soubor tam není“ —
            // ať už ho sebral úklid cache, nebo se session nestihla ani založit. Poslat člověka
            // hledat problém v úklidu je horší než neříct nic. Co se tvrdit **dá**, je následek:
            // `claude --resume` čte tentýž soubor.
            return "Transcript téhle session na disku není — soubor chybí, takže se přepis nemá "
                + "odkud vzít a opakování by na tom nic nezměnilo. Platí to i pro `claude --resume`: "
                + "čte tentýž soubor a na neznámou session odpoví `No conversation found with "
                + "session ID`."
        case .unreadable(let reason):
            return "Transcript je na disku, ale nedal se přečíst. \(reason)"
        case .empty(let bytes):
            guard bytes > 0 else {
                return "Transcript je prázdný — session se zabila dřív, než stihla cokoli zapsat. "
                    + "U běžícího review je to dočasný stav, takže má smysl to zkusit znovu."
            }
            let size = bytes.formatted(.byteCount(style: .file))
            return "Transcript má \(size), ale ani jedna událost se z něj nedala přečíst. Soubor "
                + "leží dál, takže se dá prohlédnout mimo aplikaci."
        }
    }

    /// Krátký titulek stavu (`.rawstate .who` v návrhu) — `NENÍ`, `NEDÁ SE PŘEČÍST`, `JE PRÁZDNÝ`.
    static func failureTitle(_ state: RawTranscriptState) -> String? {
        switch state {
        case .loading, .shown: nil
        case .missing: "NENÍ"
        case .unreadable: "NEDÁ SE PŘEČÍST"
        case .empty: "JE PRÁZDNÝ"
        }
    }

    static let loading = "Čtu konec transcriptu…"

    // MARK: - Patička

    static func action(_ action: RawSessionAction) -> String {
        switch action {
        case .close: "Zavřít"
        case .copyTranscript: "Zkopírovat přepis"
        case .copyPath: "Zkopírovat cestu k transcriptu"
        case .revealInFinder: "Ukázat v Finderu"
        case .reload: "Načíst znovu"
        }
    }

    /// Přírůstek od otevření. `nil` = nepřibylo nic — pilulka, která hlásí nulu, je šum.
    static func growth(_ bytes: Int?) -> String? {
        guard let bytes else { return nil }
        return "od otevření přibylo \(bytes.formatted(.byteCount(style: .file)))"
    }
}
