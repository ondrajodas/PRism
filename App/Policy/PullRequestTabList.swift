import Foundation

extension Policy {
    /// Které záložky PR se v pruhu kreslí (#215).
    ///
    /// **`Kontroly` odpadnou, když checky nejsou.** PR bez CI je běžná věc a prázdný tab
    /// s nadpisem by o něm tvrdil, že se něco nepovedlo — tatáž úvaha, kvůli které se
    /// nekreslí ani chip v hlavičce (#209).
    ///
    /// Rozhoduje **jeden bool**, ne `[PullRequestCheck]`: „nenačteno“ a „žádné“ jsou dva různé
    /// stavy (`AppStore.checks`), ale pro pruh záložek z obou plyne totéž — není čím tab naplnit.
    /// Ten rozdíl proto řeší volající, kde se dá na chybějící klíč reagovat i jinak.
    ///
    /// Vrací **pole, ne `Set`**: pořadí záložek je součást odpovědi a bere se z `allCases`, aby
    /// se nedalo rozejít s pořadím ve výčtu.
    static func tabs(hasChecks: Bool) -> [PullRequestTab] {
        PullRequestTab.allCases.filter { hasChecks || $0 != .checks }
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
    /// Bere `ChecksSummary`, ne pole checků: souhrn už umí `worst` a počítá ho jedno místo —
    /// druhé počítání by se s chipem v hlavičce rozešlo.
    ///
    /// **`.cancelled` je dnes nedosažitelné a zůstává schválně** (nález Copilota na #215): `worst`
    /// ho nevrátí, protože `Policy.summary` počítá zrušené ke spadlým. Je to ale switch nad
    /// **cizím** výčtem, takže odpověď musí mít každý jeho případ — a odpověď pro zrušený check je
    /// „červeně“, ne „mlčet“. Přidat ho k tiché větvi by znamenalo, že se z něj po případné změně
    /// v `summary` stane check bez odznaku, a to potichu.
    static func checksBadge(of summary: ChecksSummary) -> PullRequestTabBadge? {
        switch summary.worst {
        case .failed, .cancelled: .blocking(summary.failed)
        case .running: .live
        case .passed, .skipped, nil: nil
        }
    }
}
