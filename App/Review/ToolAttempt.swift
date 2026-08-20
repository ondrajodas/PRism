import Foundation

/// Pokus o nástroj: co si reviewer vyžádal, nad čím a jak to dopadlo.
///
/// **Pokus, ne použití.** Že nástroj prošel, říká teprve odpověď na něj (`outcome`) — do #326
/// to nešlo poznat vůbec, protože se odpovědi ze streamu nečetly a odmítnutí se dozvěděla
/// aplikace až ze závěrečného `result` eventu, tedy o minuty později.
struct ToolAttempt: Hashable, Codable, Sendable {
    let name: String
    /// Soubor, vzor nebo příkaz — podle nástroje. `nil`, když se z volání nedá vytáhnout
    /// nic užitečného. Samotné „Read“ v tabu Průběh nic neřekne.
    let detail: String?
    /// `tool_use.id` ze streamu — **jediný** klíč, kterým se k pokusu páruje odpověď (#326).
    ///
    /// Volitelné dvakrát, a obojí schválně: osy uložené před #326 ho v souboru nemají a volání
    /// bez `id` by se jinak nedalo do osy zapsat vůbec. Pokus bez `id` zůstane nespárovatelný —
    /// v ose je z něj krok, který se nikdy nezavře, a to je pravdivější než párovat podle jména
    /// (`Bash` je v jednom běhu padesátkrát).
    let id: String?
    /// Jak pokus dopadl. **`nil` znamená „ještě běží“, ne „prošel“** (#326): odpověď na `tool_use`
    /// chodí v `user` eventu jako `tool_result` a může dorazit s chybou, nebo taky vůbec ne.
    var outcome: Outcome?

    /// Klíče, pod kterými nástroje `claude` nesou to podstatné, v pořadí, v jakém se
    /// zkoušejí. Neznámý nástroj detail prostě nemá — hádat by znamenalo ukázat cizí číslo
    /// jako cestu.
    /// `skill` je mezi nimi od #78: bez něj je v ose vidět holé „Skill“ a nepozná se,
    /// **který** se načetl — a právě to je u něj ta zajímavá informace.
    static let detailKeys = [
        "file_path", "notebook_path", "pattern", "command", "path", "query", "url", "skill",
    ]

    init(name: String, input: [String: Any]?, id: String? = nil) {
        self.name = name
        self.id = id
        detail = ToolAttempt.detailKeys
            .lazy
            .compactMap { input?[$0] as? String }
            .first { !$0.isEmpty }
    }

    init(name: String, detail: String?, id: String? = nil, outcome: Outcome? = nil) {
        self.name = name
        self.detail = detail
        self.id = id
        self.outcome = outcome
    }

    /// Detail bez toho, co je na každém řádku stejné.
    ///
    /// Reviewer běží v pracovním stromě, takže **každá** cesta začíná sedmdesáti znaky
    /// cache a příkazy navíc uvozuje `cd <strom> &&`. V ose z toho není poznat nic — a
    /// zajímavý je soubor, ne kde ho aplikace má.
    func shortened(inside worktree: URL?) -> String? {
        guard let detail, let worktree else { return detail }
        let path = worktree.path(percentEncoded: false)

        var result = detail
        for prefix in ["cd \"\(path)\" && ", "cd '\(path)' && ", "cd \(path) && "] {
            if result.hasPrefix(prefix) {
                result.removeFirst(prefix.count)
                break
            }
        }
        // Zbylé výskyty jsou cesty uvnitř příkazu (`grep … <strom>/apps`).
        result = result.replacingOccurrences(of: path + "/", with: "")
        result = result.replacingOccurrences(of: path, with: "")
        return result
    }

    /// Ořezávat zprava, nebo zleva? U cesty je zajímavý konec (jméno souboru), u příkazu
    /// začátek (co se spouští).
    var keepsTail: Bool {
        ToolAttempt.pathTools.contains(name)
    }

    private static let pathTools: Set<String> = ["Read", "NotebookRead", "Edit", "Write"]
}

extension ToolAttempt {
    /// Jak dopadl pokus o nástroj (#326) — z bloku `tool_result`, který na něj přišel.
    ///
    /// Tři stavy, ne dva, a je to ta hranice, na které celé #326 stojí: **odmítnutí je stav
    /// povolení, chyba nástroje výsledek jeho práce.** `grep` bez shody a `Read` neexistujícího
    /// souboru se vrací s `is_error` pořád, takže odznak `ODMÍTNUTO` u nich by z read-only režimu
    /// (tvrdá podmínka č. 2) udělal poplach nad úplně běžným krokem.
    struct Outcome: Hashable, Sendable {
        enum Kind: String, Hashable, Sendable, Codable {
            /// Nástroj odpověděl a chybu neohlásil.
            case passed
            /// Nespustil se — chybí povolení. **Není to chyba běhu**: `Bash(gh:*)` se odmítnout
            /// *má* a session po něm skončí `success`.
            case denied
            /// Běžel a vrátil chybu. Vlastní stav, ne `denied` (viz výš) a ne `passed`: tvrdit
            /// „prošel“ nad chybou je totéž, co tvrdit „čisto“ nad nepřečtenými nálezy.
            case failed
        }

        let kind: Kind
        /// Jak dlouho se na odpověď čekalo. `nil` u odmítnutí (nástroj neběžel, takže není co
        /// měřit) a u os uložených před #326.
        let after: Duration?
        /// Hláška z `tool_result` — sražená na jeden řádek a ostříhaná (`Policy.toolOutcome`).
        /// `nil` u `passed`, kde je obsahem odpovědi celý soubor nebo celý diff.
        let reason: String?

        init(kind: Kind, after: Duration? = nil, reason: String? = nil) {
            self.kind = kind
            self.after = after
            self.reason = reason
        }

        /// Doplní změřené trvání.
        ///
        /// Měří ho **osa, ne parser**: parser hodiny nemá a druhý zdroj času ve streamu
        /// (`timestamp` na eventech) by se rozešel s časy, podle kterých se osa kreslí — a osa
        /// je to jediné, kde se trvání ukazuje.
        ///
        /// **Odmítnutí trvání nedostane.** Nástroj neběžel, takže by to bylo trvání toho, jak
        /// dlouho se čekalo na „ne“ — a u záchrany z `permission_denials` (odpověď, která nikdy
        /// nedorazila) rovnou trvání celého zbytku běhu.
        func measured(after wait: Duration) -> Self {
            kind == .denied ? self : Self(kind: kind, after: wait, reason: reason)
        }
    }
}

extension ToolAttempt.Outcome: Codable {
    /// Na disku vlastní tvar, ne syntetizovaný — tatáž úvaha jako u `RunUsage`: `Duration` se
    /// `Codable`m kóduje jako dvojice int128, což je v souboru, do kterého se dá kouknout,
    /// nečitelné. Klíč proto nese jednotku (`afterMS`).
    private enum CodingKeys: String, CodingKey {
        case kind
        case afterMS
        case reason
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        after = try container.decodeIfPresent(Int.self, forKey: .afterMS).map(Duration.milliseconds)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(after.map { $0.milliseconds }, forKey: .afterMS)
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}

/// Odpověď na jeden pokus o nástroj, jak ji vydá parser (#326).
///
/// Nese `id`, ne celý pokus: párování je práce toho, kdo drží osu — parser jen říká „na tohle
/// `tool_use_id` přišla tahle odpověď“.
struct ToolResolution: Hashable, Sendable {
    let id: String
    let outcome: ToolAttempt.Outcome
}
