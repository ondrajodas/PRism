import Foundation

/// Jméno MCP nástroje na **text issue** (#345) a to, co se o něm dá říct pod polem v nastavení
/// (#389).
///
/// Do #389 se ta hodnota dala napsat jedině ručně do `config.json`, takže funkce, na které stojí
/// celé #345, byla bez editoru textu nedostupná. Pole v okně ale znamená tři stavy, které se
/// **nesmí slít**, a proto tenhle typ existuje:
///
/// - **prázdno je rozhodnutí „netahat“**, ne nedodělek. Pustit session, která nemá co zavolat,
///   stojí boot (~$0,2) a nevrátí nic;
/// - **vyplněné jméno znamená, že u PR s odkazem poběží session navíc** — a to je informace
///   o penězích, takže se u pole říct musí;
/// - **jméno bez prefixu `mcp__` session nezavolá.** Je to varování, ne zákaz: jméno je fakt
///   o cizím stroji a aplikace ho neumí ověřit, dokud session neběží.
enum IssueTextTool {
    /// Prefix, kterým `claude` adresuje nástroje z MCP serverů (`mcp__<server>__<nástroj>`).
    ///
    /// Konstanta, ne literál na dvou místech: čte ji varování pod polem i test, který ho hlídá.
    /// Jméno **za** prefixem kontrakt není — závisí na tom, jak si server pojmenoval uživatel.
    static let prefix = "mcp__"

    /// Nápověda v prázdném poli. Vzor, ne příklad z tohohle stroje: konkrétní
    /// `mcp__claude_ai_Linear__get_issue` by vypadal jako výchozí hodnota, kterou stačí potvrdit.
    static let namePattern = "mcp__<server>__<nástroj>"

    /// Co stojí pod polem v nastavení.
    ///
    /// Vlastní typ, ne `Bool` nebo `String?` — stejně jako `ReviewTimeout.Problem`: rozhodnutí
    /// („co se s tou hodnotou stane“) patří do `Policy`, kde se testuje výčtem, a view z něj jen
    /// sází text. `Bool` by navíc neunesl, že **dva ze tří stavů nejsou porucha**.
    enum Note: Hashable, Sendable {
        /// Prázdno — text issue se netahá.
        case notFetching
        /// Vyplněné jméno, které nástroj být může.
        case fetching
        /// Vyplněné jméno, které nástroj být nemůže: nezačíná na `mcp__`.
        case unlikelyName

        /// Věta pod polem. Doslova ta, která je v mockupu (sekce 10) — tři různé stavy mají tři
        /// různé věty, ne jednu se závorkou.
        var text: String {
            switch self {
            case .notFetching:
                "Nevyplněno — text issue se netahá."
            case .fetching:
                "Tahá se — u PR s odkazem na issue běží session navíc."
            case .unlikelyName:
                "Nezačíná na \(IssueTextTool.prefix) — session takový nástroj nezavolá."
            }
        }

        /// Má se to nakreslit jako varování?
        ///
        /// **Jen u nepravděpodobného jména.** Prázdno je odpověď a vyplněné jméno je normální
        /// stav; obarvit je taky by z pole udělalo pole, u kterého vždycky něco svítí — a takové
        /// se přestane čítat.
        var isWarning: Bool { self == .unlikelyName }
    }
}

extension Policy {
    /// Co se napíše pod pole `Jméno MCP nástroje` v nastavení (#389).
    ///
    /// **Prázdno se pozná po odstranění bílých znaků**, tedy tímtéž měřítkem, jakým se hodnota
    /// vyhodnocuje na cestě do běhu (`issueTextTool(from:)`). Dvě různá měřítka by znamenala pole,
    /// pod kterým stojí „tahá se“, a review, ve kterém se netahá.
    static func issueTextToolNote(for configured: String?) -> IssueTextTool.Note {
        guard let tool = issueTextTool(from: configured) else { return .notFetching }
        return tool.hasPrefix(IssueTextTool.prefix) ? .fetching : .unlikelyName
    }

    /// Co se z napsaného textu uloží do konfigurace (#389). `nil` = **klíč v souboru nebude**.
    ///
    /// Vymazané pole se ukládá jako chybějící klíč, ne jako prázdný řetězec: pro chování je to
    /// jedno (`issueTextTool(from:)` bere obojí jako `netahat`), ale v souboru, který se edituje
    /// ručně, je rozdíl mezi „o nástroji tu nic není“ a `"issueTextTool": ""`, což čte jako
    /// nastavení na nic.
    ///
    /// **Bílé znaky se nezahazují**, i když se na cestě do běhu orazí: kdo napíše mezeru do
    /// prázdného pole, by ji jinak viděl zmizet pod rukou — pole se překresluje z uložené hodnoty.
    /// Že se s takovou hodnotou netahá, řekne `issueTextToolNote(for:)`, tedy tatáž věta pod polem.
    static func issueTextToolEdit(typed: String) -> String? {
        typed.isEmpty ? nil : typed
    }
}
