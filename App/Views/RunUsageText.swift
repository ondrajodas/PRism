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
