import Foundation

/// Co stojí v odznaku závažnosti u nálezu — a jestli se jeho text přeškrtne (#150).
///
/// Odznak závažnosti kreslí **čtyři** místa: karta v panelu, sloupec `závažnost` v tabulce,
/// značka bubliny u kódu a hlavička nálezu uvnitř bubliny. Kdyby si každé rozhodlo samo, kdy
/// v něm stojí `vyřešeno`, rozešla by se — a rozejít se v tomhle znamená, že jedna obrazovka
/// tvrdí `vyřešeno` a druhá `blokuje` o tomtéž nálezu. Rozhoduje proto `Policy`.
///
/// **`blokuje` se nikdy nenahrazuje, jen se k němu přidává.** „Vyřešeno“ je tvrzení modelu,
/// kdežto „blokuje“ je fakt o tom, co zastavuje merge — a nález s `vyřešeno` se dál počítá i dál
/// blokuje (sundat ho smí jedině odmítnutí, #113). Kdyby `vyřešeno` `blokuje` přebilo, řádek by
/// tvrdil „hotovo“ nad věcí, která pořád drží PR.
enum FindingSeverityBadge: Hashable, Sendable {
    /// Nález jsem odmítl (#113). **Rozhodnutí člověka přebíjí kontrolu**: o odmítnutém nálezu je
    /// rozhodnuto, takže se k němu druhý stav vedle nepřidává — a hlavně se nesmí splést
    /// s `resolved`, který je jen tvrzení modelu.
    case dismissed(FindingDismissal.Reason)
    /// Kontrola nových commitů ho má za opravený. `blocking` říká, jestli **pořád blokuje**;
    /// když ano, `blokuje` zůstává na řádku vedle.
    case resolved(RecheckStatus, blocking: Bool)
    /// Blokuje merge. Kontrola se k němu nevyjádřila, nebo řekla `pořád platí` / `nejasné` — obojí
    /// nechává závažnost, jak byla.
    case blocking
    /// Není co ukázat.
    case none

    /// Přeškrtnout **text nálezu**?
    ///
    /// Jen jeho — ne celý řádek. Celořádkové „tohle se nepočítá“ má v okně `DismissedRowStyle`,
    /// tedy rozhodnutí člověka; dát modelu tentýž obrázek by ten rozdíl smazalo (viz specifikace,
    /// záznam rozhodnutí k #150).
    var strikesFindingText: Bool {
        guard case .resolved = self else { return false }
        return true
    }

    /// Zůstává na řádku `blokuje`? Je to **fakt**, takže odsud musí vyjít `true` u obou stavů,
    /// ve kterých nález blokuje — jinak by ho `vyřešeno` potichu spolklo.
    var showsBlocking: Bool {
        switch self {
        case .blocking: true
        case .resolved(_, let blocking): blocking
        case .dismissed, .none: false
        }
    }
}

extension Policy {
    /// Odznak závažnosti u **jednoho** nálezu.
    static func severityBadge(
        isBlocking: Bool,
        recheck: RecheckStatus?,
        dismissal: FindingDismissal?
    ) -> FindingSeverityBadge {
        if let dismissal { return .dismissed(dismissal.reason) }
        if let recheck, recheck.verdict == .resolved {
            return .resolved(recheck, blocking: isBlocking)
        }
        return isBlocking ? .blocking : .none
    }

    /// Odznak závažnosti u **skupiny** nálezů na jednom místě v kódu — pro značku bubliny
    /// a sbalený řádek tabulky, které mluví za celé místo.
    ///
    /// `vyřešeno` vydá jedině tehdy, když ho kontrola dala **všem platným nálezům** skupiny. Jeden
    /// opravený a jeden pořád platný je zrovna ten případ, kdy by odznak za skupinu lhal — tam se
    /// stav nese u jednotlivých nálezů uvnitř bubliny. Věta k verdiktu se bere od **prvního**
    /// platného nálezu; verdikt mají shodný, jen zdůvodnění může být u každého jiné.
    static func severityBadge(
        of group: FindingGroup,
        categories: Set<String> = defaultBlockingCategories
    ) -> FindingSeverityBadge {
        let active = group.activeFindings
        guard !active.isEmpty else {
            // Skupina, ze které nezbyl platný nález, je odmítnutá — a mluví za ni důvod prvního.
            guard let dismissal = group.dismissal(of: group.findings[0]) else { return .none }
            return .dismissed(dismissal.reason)
        }
        let blocks = active.contains { isBlocking($0, categories: categories) }
        let statuses = active.compactMap { group.recheck(of: $0) }
        guard statuses.count == active.count,
              statuses.allSatisfy({ $0.verdict == .resolved })
        else {
            return severityBadge(isBlocking: blocks, recheck: nil, dismissal: nil)
        }
        return severityBadge(isBlocking: blocks, recheck: statuses.first, dismissal: nil)
    }
}
