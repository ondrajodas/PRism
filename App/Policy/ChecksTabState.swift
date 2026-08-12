import Foundation

/// Co je v tabu `Kontroly` k vidění (#306).
///
/// Tab se od #306 kreslí **vždycky**, takže musí mít odpověď na **každý** stav dat — a ty čtyři
/// se nesmí slít. Zvlášť „ještě nedorazily“ a „žádné nejsou“: obojí je prázdno, ale jen to druhé
/// smí říct, že PR nemá CI. Je to tentýž rozdíl jako mezi `čisté` a `failed` u review, a tentýž,
/// kvůli kterému drží `AppStore.checks` chybějící klíč odděleně od prázdného pole.
///
/// **Vlastní typ, ne trojice optionalů ve view.** Kombinací vstupů je šest (`checks` nenačtené /
/// prázdné / neprázdné × `failure` je / není) a vyjde z nich čtvero odpovědí; skládat to na místě,
/// kde se kreslí, znamená skládat to podruhé u odznaku — a odznak by pak mohl mluvit o jiném stavu
/// než plocha pod ním.
enum ChecksTabState: Equatable, Sendable {
    /// Ještě nedorazily. **Nesmí tvrdit, že CI není** — čeká se na odpověď.
    case loading
    /// Načetly se a žádné nejsou: PR bez CI. Běžný stav, ne porucha.
    case empty
    /// Seznam checků. `failure` = poslední pokus o načtení selhal, takže je to **poslední známý
    /// stav**; stará sada se po selhání nechává být (#215).
    case list([PullRequestCheck], failure: String?)
    /// Nepodařilo se je načíst a není co ukázat.
    case failed(String)
}

extension Policy {
    /// Co ukázat v tabu `Kontroly` (#306).
    ///
    /// Tři rozhodnutí v pořadí, ve kterém se ptají:
    ///
    /// 1. **Neprázdný seznam přebíjí poruchu.** Zastaralá sada s větou nad sebou je pořád lepší
    ///    než plocha s chybou místo checků, které se před chvílí načetly (#215).
    /// 2. **Porucha přebíjí obě prázdna.** Když není co ukázat, odpovídá poslední pokus — jinak by
    ///    z chyby sítě vyšlo „tenhle PR nemá CI“, tedy zrovna ta záměna, kvůli které `checkFailures`
    ///    vznikly. Platí to i nad `checks == []`: prázdno je z **předchozího** načtení, kdežto
    ///    porucha je to, co víme teď.
    /// 3. **Chybějící klíč je „nenačteno“, prázdné pole „žádné“.** Ten rozdíl je celý důvod,
    ///    proč `AppStore.checks` drží obojí zvlášť.
    static func checksTab(checks: [PullRequestCheck]?, failure: String?) -> ChecksTabState {
        if let checks, !checks.isEmpty { return .list(checks, failure: failure) }
        if let failure { return .failed(failure) }
        return checks == nil ? .loading : .empty
    }

    /// Odznak u záložky `Kontroly` — **podle nejhoršího stavu, ne podle většiny** (#215).
    ///
    /// Tatáž úvaha jako u chipu v hlavičce (#209): dvanáct zelených a jeden červený je červený
    /// stav, takže odznak mluví o tom jednom. Skládá se ze tří případů:
    ///
    /// - **spadlé** → červená kapsle s jejich počtem (`blocking`). Je to počet, ve kterém něco
    ///   blokuje merge, takže tichá kapsle by se čtla jako neškodný údaj o množství;
    /// - **běžící** → puntík (`live`), stejně jako u `Průběhu`. „Běží“ je stav, ne množství —
    ///   u dvou běžících jobů by dvojka o průběhu neřekla nic;
    /// - **zelené nebo přeskočené** → **žádný odznak**. Zelené CI je výchozí stav a číslo u něj
    ///   by byl šum, kvůli kterému by se přestaly čít i ty ostatní dva.
    ///
    /// **Bere stav tabu, ne `ChecksSummary`** (#306). Do #306 mu stačil souhrn, protože se tab
    /// u PR bez CI vůbec nekreslil — nenačtený a prázdný stav se k odznaku nedostaly. Teď se
    /// kreslí vždycky, takže „mlčet, dokud není seznam“ musí být vidět **ze zápisu funkce**:
    /// jeden `guard` na začátku místo tří míst, kde by se na prázdno muselo pamatovat. Souhrn se
    /// z něj počítá dál — `worst` umí jedno místo a druhé počítání by se rozešlo s chipem
    /// v hlavičce.
    ///
    /// **`.cancelled` je dnes nedosažitelné a zůstává schválně** (nález Copilota na #215): `worst`
    /// ho nevrátí, protože `Policy.summary` počítá zrušené ke spadlým. Je to ale switch nad
    /// **cizím** výčtem, takže odpověď musí mít každý jeho případ — a odpověď pro zrušený check je
    /// „červeně“, ne „mlčet“. Přidat ho k tiché větvi by znamenalo, že se z něj po případné změně
    /// v `summary` stane check bez odznaku, a to potichu.
    static func checksBadge(of state: ChecksTabState) -> PullRequestTabBadge? {
        // Nenačteno, prázdno ani porucha odznak nedostanou: prázdná kapsle ani nula by neřekly nic
        // a nad nenačteným stavem by nula navíc tvrdila, že se spočítalo.
        guard case .list(let checks, _) = state else { return nil }

        let summary = summary(of: checks)
        switch summary.worst {
        case .failed, .cancelled: return .blocking(summary.failed)
        case .running: return .live
        case .passed, .skipped, nil: return nil
        }
    }
}
