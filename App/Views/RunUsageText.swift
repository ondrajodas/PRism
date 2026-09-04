import Foundation

/// Cena, trvání a útrata jako text (#148).
///
/// Formátuje **view, ne model** — tatáž úvaha jako u `ReleaseRow`, kde datum formátuje okno:
/// texty závislé na locale se pak nedají testovat. Vlastní typ proto, že totéž potřebuje osa
/// v tabu `Průběh` i stavový řádek, a dvě kopie by se rozešly ve formátu.
enum RunUsageText {
    /// Cena v dolarech. Přes locale, protože peníze **jsou** množství — na rozdíl od čísla PR
    /// nebo řádku, které se píšou `verbatim`.
    ///
    /// Dvě desetinná místa i u částky, která je má tři (`0,232`): u jednoho běhu je ten haléř
    /// šum a u součtu za den se ztratí úplně. Kdo chce přesně, má `spend.json`.
    ///
    /// `presentation(.narrow)` proto, že v české locale by se `USD` psalo `US$` — tedy o dva
    /// znaky víc v pruhu, který je úzký, a o dva znaky navíc v hlavičce revieweera. Že jsou to
    /// dolary, říká `$` a nic jiného aplikace neúčtuje.
    static func cost(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").presentation(.narrow).precision(.fractionLength(2)))
    }

    /// Kolik stálo slévání konfliktů, k výsledku v potvrzení (#467). `nil` = **session cenu
    /// nenahlásila**.
    ///
    /// **Tady, ne v `Policy`**, a je to tatáž úvaha jako u `cost` o řádek výš: peníze se formátují
    /// přes locale, takže text s částkou se v `Policy` nedá testovat. `Policy` by k tomu navíc
    /// nepřidala žádné rozhodnutí — je to sazba, ne pravidlo.
    ///
    /// **`nil` není nula.** Zabitá session peníze stála taky, jen o nich nevíme — a `0,00 $` u ní
    /// by byla nepravda o účtu (tatáž úvaha jako u `spent` níž a u `DailySpend.unknown`).
    ///
    /// Kola se říkají **jedině tehdy, když bylo víc než jedno**: „1 kolo“ je informace, kterou si
    /// nikdo neklade, kdežto tři kola vysvětlují, proč je částka trojnásobná.
    static func conflictSpent(_ usage: RunUsage?, rounds: Int) -> String? {
        guard let value = usage?.cost else { return nil }
        guard rounds > 1 else { return "Slévání stálo \(cost(value))." }
        return "Slévání stálo \(cost(value)) ve \(Plural.czech(rounds, one: "kole", few: "kolech", many: "kolech"))."
    }

    /// Útrata za den — cena a před ní `≥`, když se do součtu nepodařilo započítat všechno.
    ///
    /// Je to **dolní odhad**: zabitý běh peníze stál taky, jen jeho cenu nikdo nenahlásil.
    /// Od #181 se na to ptají dvě místa (stavový řádek a blok `Dneska stálo` na desce) a druhá kopie by
    /// znamenala, že jedno z nich značku vynechá — tedy že součet vypadá jako úplný.
    static func spent(_ spend: DailySpend) -> String {
        (spend.unknown > 0 ? "≥ " : "") + cost(spend.cost)
    }

    /// Trvání. Pod minutu vteřiny s desetinou (`11,8 s`), nad ni minuty a vteřiny (`2 m 5 s`).
    ///
    /// Desetina jen dole schválně: u jedenácti vteřin je rozdíl mezi 11 a 12 vidět, u dvou
    /// minut nikoho nezajímá — a `.units` desetiny neumí, takže by se to jinak muselo lámat
    /// na celé vteřiny všude.
    static func duration(_ value: Duration) -> String {
        let seconds = Double(value.milliseconds) / 1000
        guard seconds >= 60 else {
            return "\(seconds.formatted(.number.precision(.fractionLength(1)))) s"
        }
        return value.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))
    }

    /// Hodiny běžícího review — `1:12`, nad hodinu `1:02:07` (#218).
    ///
    /// **Ne `duration(_:)`**: to je změřený čas doběhlého běhu (`11,8 s`, `2 m 5 s`), kdežto
    /// tohle jsou stopky, které tikají v pruhu — a stopky, u kterých se jednotka mění podle
    /// toho, jak dlouho běží, se špatně čtou, protože se pod okem přeskládají.
    ///
    /// Záporný čas (posunuté systémové hodiny) je nula, ne `-0:03`.
    static func elapsed(_ value: Duration) -> String {
        let total = max(value.milliseconds / 1000, 0)
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        guard hours > 0 else { return String(format: "%d:%02d", minutes, seconds) }
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    /// Kolik kol si session vyžádala (`num_turns`).
    static func turns(_ value: Int) -> String {
        Plural.czech(value, one: "kolo", few: "kola", many: "kol")
    }

    /// Řádek u revieweera: `0,23 $ · 11,8 s · 3 kola`. Vynechává, co nedorazilo — a `nil`,
    /// když nedorazilo nic, aby se prázdný text nekreslil jako prázdné místo.
    static func summary(of usage: RunUsage) -> String? {
        var parts: [String] = []
        if let value = usage.cost { parts.append(cost(value)) }
        if let value = usage.duration { parts.append(duration(value)) }
        if let value = usage.turns { parts.append(turns(value)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
