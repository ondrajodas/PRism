import Foundation

/// Čí je pull request (#330).
///
/// **Vlastní typ, ne `Bool`.** U cizího PR je moje práce přečíst a odpovědět, u vlastního opravit
/// a pushnout — jsou to dvě různé práce, ne jedna s příznakem, a okno je od #331 kreslí vedle sebe.
/// Z `isMine == false` by navíc nebylo poznat, že „nevím, kdo se dívá“ spadá schválně do `theirs`.
enum PullRequestOwnership: Hashable, Sendable {
    /// Autor je někdo z mých loginů.
    case mine
    /// Autor je někdo jiný — **a taky to, když se ještě neví, kdo se dívá.**
    case theirs
}

extension Policy {
    /// Loginy, které se počítají za **moje** (#330) — viewer z `gh` plus to, co je v konfiguraci.
    ///
    /// **Množina, ne jeden řetězec**, a je to schválně dražší rozhodnutí, než dnešní data
    /// potřebují: agent s vlastním účtem (`github-actions[bot]`, Copilot) pushuje pod sebou, takže
    /// by do `.mine` nespadl. Dneska to nevadí — agenti v tomhle repu pushují přes moje `gh`
    /// a ověřeně mají autora `ondrajodas` — ale dolepovat druhý login potom by znamenalo projít
    /// všechna místa, která se ptají „je to moje“.
    ///
    /// **Prázdný viewer se nepřidává**, takže z něj vyjde prázdná množina a všechno je pak
    /// `.theirs`. Prázdné a bílé položky z konfigurace padají ze stejného důvodu jako u skillů:
    /// soubor se edituje ručně.
    ///
    /// Loginy se **normalizují na malá písmena**, protože GitHub je na velikost necitlivý a `gh`
    /// vrací kanonický tvar (`OndraJodas`), kdežto do konfigurace si je člověk píše, jak zrovna
    /// vidí v prohlížeči. Bez toho by se ručně zapsaný agent tiše nepoznal.
    static func ownLogins(viewer: String?, configured: [String] = []) -> Set<String> {
        var logins = Set(configured.compactMap { normalizedLogin($0) })
        if let viewer = normalizedLogin(viewer) { logins.insert(viewer) }
        return logins
    }

    /// Čí je pull request — podle **autora**, ne podle zdroje, ze kterého přišel (#330).
    ///
    /// Zdroj je search dotaz a jeden PR jich umí splňovat víc (`repo:foo/bar is:open` se překryje
    /// s obojím), takže rozřazení odvozené od zdroje by záviselo na tom, jak si člověk dotazy
    /// poskládal.
    static func ownership(of summary: PullRequestSummary, mine: Set<String>) -> PullRequestOwnership {
        ownership(ofAuthor: summary.author, mine: mine)
    }

    /// Tatáž otázka nad samotným autorem — pro místa, která `PullRequestSummary` nemají.
    ///
    /// Bere **optional**, protože „autora ještě neznám“ (detail nedorazil) je stav, o kterém se
    /// tady rozhoduje, a padá do `.theirs` stejně jako neznámý viewer. Je to **jediné místo, kde se
    /// s viewerem porovnává autor pull requestu** — `Policy.isOwn(author:viewer:)` z #114 chodí přes
    /// ni, aby na tu otázku nebyly dvě odpovědi.
    ///
    /// `Conversation.isMine(_:)` porovnává **taky loginy, ale jinou otázku**: čí je komentář nebo
    /// review uvnitř načtené konverzace. Zůstává v modelu schválně — viewer tam neoptional je
    /// (konverzace ho vždycky nese) a přesměrovat ho sem by z modelu udělalo závislost na `Policy`
    /// za jedno `==`, které nemá co rozhodovat.
    static func ownership(ofAuthor author: String?, mine: Set<String>) -> PullRequestOwnership {
        guard let author = normalizedLogin(author), mine.contains(author) else { return .theirs }
        return .mine
    }

    /// Je mezi zdroji ten, který **přináší vlastní PR** (#330)?
    ///
    /// Rozřazení podle autora je k ničemu, dokud `author:@me is:open` není mezi zdroji: sekce
    /// `Moje PR` by u každého, kdo si ten řádek nedopsal ručně, zůstala navždycky prázdná — a to
    /// vypadá jako „nic nemám rozdělané“, ne jako „nemám kde se to dozvědět“. Konfigurace se kvůli
    /// tomu **nemigruje** (dopsat uživateli zdroj, o který si neřekl, je zásah do souboru, který se
    /// edituje ručně, a zdroj navíc je dotaz navíc při každém tiku), takže to musí poznat prázdný
    /// stav sekce. Větu k tomu kreslí #331, rozhodnutí je tady.
    ///
    /// Poznává se **token `author:` v dotazu**, ne jméno zdroje: jméno je popisek pro člověka
    /// a přejmenovaný řádek by rozpoznání vypnul. Bere se `author:@me` a `author:<některý z mých
    /// loginů>`; `-author:@me` (negace) ani `involves:@me` **ne** — obojí je jiný dotaz. Kdo si
    /// login vypíše ručně, dostane rozpoznání teprve tehdy, až je znám viewer; do té doby je
    /// množina prázdná a `author:@me` je jediná forma, která se pozná.
    static func tracksOwnPullRequests(in sources: [Source], mine: Set<String>) -> Bool {
        sources.contains { source in
            source.query.split(whereSeparator: \.isWhitespace).contains { token in
                guard let login = ownAuthorToken(token) else { return false }
                return login == "@me" || mine.contains(login)
            }
        }
    }

    /// Hodnota za `author:` v jednom tokenu dotazu, v malých písmenech. `nil` = není to `author:`.
    private static func ownAuthorToken(_ token: Substring) -> String? {
        let lowercased = token.lowercased()
        guard lowercased.hasPrefix("author:") else { return nil }
        let value = lowercased.dropFirst("author:".count)
        return value.isEmpty ? nil : String(value)
    }

    /// Přihlášený účet, jak se ukáže nad seznamem vlastních loginů v nastavení (#389).
    ///
    /// Existuje kvůli tomu, aby prázdný seznam v okně neznamenal „nevím, kdo jsem“: loginy
    /// z konfigurace jsou ty **navíc**, kdežto ten hlavní se bere z `gh api user` a napsat se nedá.
    /// Bez řádku nad polem by se prázdno (běžný stav) nedalo odlišit od nenačteného viewera (stav,
    /// ve kterém je **každý** PR cizí) — a to je tentýž rozdíl, který dole hlídá `ownership(of:)`.
    static func viewerAccount(login: String?) -> ViewerAccount {
        guard let login = normalizedLogin(login) else { return .unknown }
        return .known(login: login)
    }

    /// Login v porovnatelném tvaru. `nil` = nic, co by se dalo s někým porovnat.
    private static func normalizedLogin(_ login: String?) -> String? {
        guard let trimmed = login?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}

/// Přihlášený účet v nastavení (#389) — `gh` ho zjistí sám, napsat se nedá.
///
/// Vlastní typ, ne `String?`, ze stejného důvodu jako `ReviewTimeout.Problem`: u nenačteného
/// viewera se musí říct **co to znamená**, ne jen že tam nic není. „Nevím, kdo jsem“ totiž není
/// kosmetika — v tom stavu spadne každý pull request do cizí fronty.
enum ViewerAccount: Hashable, Sendable {
    /// `gh api user` odpověděl. Login je v porovnatelném tvaru, tedy tom, ve kterém se pak
    /// rozřazuje.
    case known(login: String)
    /// Login ještě není. Při startu je to normální okamžik, po chybě `gh` stav, který vysvětluje,
    /// proč je fronta plná a vlastní PR nikde.
    case unknown

    /// Co stojí v řádku vpravo.
    ///
    /// **`nezjištěno`, ne `zjišťuje se`**: dotaz na login jde **jednou při startu** a neopakuje se
    /// (`AppStore.loadViewer`), takže po selhání `gh` se ten stav sám nezmění. „Zjišťuje se“ by
    /// slibovalo práci, která neběží — a čekalo by se na ni marně.
    var label: String {
        switch self {
        case .known(let login): login
        case .unknown: "nezjištěno"
        }
    }

    /// Co je na tom stavu potřeba dovysvětlit. `nil` = nic, účet je znám.
    ///
    /// Nese **obojí**: co to znamená (všechno cizí) a proč to samo nepřejde (ptá se jen při
    /// startu, takže pomůže restart, ne čekání).
    var note: String? {
        switch self {
        case .known: nil
        case .unknown:
            "Login se zjišťuje jen při startu. Dokud není, počítá se každý pull request jako cizí."
        }
    }
}
