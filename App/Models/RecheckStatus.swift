import Foundation

/// Co o **jednom nálezu z minula** říká kontrola nových commitů (#150).
///
/// Není to nález a nesmí se za něj vydávat: nález je věta revieweera o kódu, tohle je tvrzení
/// o tom nálezu. Proto to nebydlí v `Finding` ani ve `StoredReviewRun` — viz `StoredRecheck`.
///
/// **Nic to neschovává.** Odznak `vyřešeno` je tvrzení modelu, ne fakt; sundat nález smí jedině
/// člověk odmítnutím (#113). Kdyby „vyřešeno“ nález schovalo, dalo by se o něj přijít tím, že se
/// modelu něco zdálo — a schovaný nález se od neexistujícího nedá odlišit.
struct RecheckStatus: Hashable, Codable, Sendable {
    /// Jak nález obstál proti novým commitům.
    ///
    /// **Tři hodnoty, ne dvě.** `unclear` je tam schválně: „z kódu se to nedá poznat“ je jiná
    /// odpověď než „pořád platí“, a slít je do jedné by znamenalo tvrdit o nálezu něco, co běh
    /// neřekl. Reviewer, který nemá jak rozhodnout, si tak nemusí vybírat mezi dvěma nepravdami.
    enum Verdict: String, Hashable, Codable, Sendable, CaseIterable {
        /// Nové commity to opravily.
        case resolved
        /// Nález pořád platí.
        case stillApplies = "still-applies"
        /// Z kódu se to rozhodnout nedá.
        case unclear
    }

    let verdict: Verdict
    /// Věta, kterou to běh odůvodnil. **Volitelná** — verdikt bez důvodu je pořád verdikt, ale
    /// bez věty se nedá posoudit, jak k němu došel, takže se v okně ukazuje, kdykoli přijde.
    ///
    /// Zůstává v jazyce, ve kterém ji model napsal. Překlad nálezů (#94) je vlastní session na
    /// běh a kvůli jedné větě u odznaku se druhá utrácet nemá; nálezy samotné přeložené jsou.
    let note: String?

    init(verdict: Verdict, note: String? = nil) {
        self.verdict = verdict
        self.note = note
    }
}

extension RecheckStatus.Verdict {
    /// Popisek do odznaku. **Nese v sobě, odkud to je** (`kontrola:`), a je to podmínka, ne
    /// ozdoba: samotné `vyřešeno` vedle nálezu by se čtlo jako fakt, kdežto tohle říká, kdo to
    /// tvrdí. Tatáž úvaha jako u textů, které nesmí tvrdit víc, než data unesou.
    var label: String {
        switch self {
        case .resolved: "kontrola: vyřešeno"
        case .stillApplies: "kontrola: pořád platí"
        case .unclear: "kontrola: nejasné"
        }
    }

    /// Co to znamená — do nápovědy u odznaku.
    var explanation: String {
        switch self {
        case .resolved:
            "Podle kontroly nových commitů je to opravené. Je to tvrzení modelu, ne fakt — "
                + "nález zůstává, dokud ho neodmítneš."
        case .stillApplies:
            "Podle kontroly nových commitů to pořád platí."
        case .unclear:
            "Kontrola nedokázala z kódu rozhodnout, jestli je to opravené."
        }
    }
}
