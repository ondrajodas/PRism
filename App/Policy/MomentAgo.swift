import Foundation

extension Policy {
    /// Jak dávno to bylo, česky — `před 2 hodinami`, `včera`, `před 3 dny` (#533).
    ///
    /// **Existuje proto, že v paletě je čas uvnitř věty.** Všude jinde v okně se relativní čas
    /// kreslí `Text(date, format: .relative(presentation: .named))`, tedy jako samostatný prvek,
    /// který se sám přepočítává. Řádek palety má ale podtitulek jako **jeden řetězec** (hledá se
    /// v něm a zvýrazňuje se v něm shoda), a návrh do něj píše `naposledy před hodinou` —
    /// tedy slovo, čas a nic mezi tím. Rozdělit tu věty mezi `Policy` a view by znamenalo, že
    /// polovinu podtitulku skládá kresba.
    ///
    /// **Referenční okamžik je parametr, ne `Date.now`**, a je to podmínka testovatelnosti:
    /// `Date.RelativeFormatStyle` (to, co používá `Text(_:format:)`) referenci vzít **neumí**,
    /// takže se sem bere `RelativeDateTimeFormatter`, který ji jako jediný má. Řetězce z obou
    /// jsou tytéž — `dateTimeStyle = .named` a `unitsStyle = .full` je nastavení, kterým se to
    /// srovnává.
    ///
    /// **`.named`, ne `.numeric`**, tedy `včera` místo `před 1 dnem`: je to týž tvar, jaký kreslí
    /// zbytek okna (`presentation: .named`), a nemíchat je je celý důvod, proč tahle funkce má
    /// vypsané nastavení.
    ///
    /// Formátovač se **zakládá při každém volání**, což je v pořádku, dokud se volá jednotky krát
    /// za úhoz: řádků s časem je v paletě nejvýš strop skupiny. Kdo formátuje seznam, ať si vezme
    /// `momentsAgo(using:)` — jinak by z jednoho stisku klávesy byla stovka `NSObject`ů.
    static func momentAgo(_ date: Date, now: Date) -> String {
        momentAgoFormatter().localizedString(for: date, relativeTo: now)
    }

    /// Formátovač na dávku řádků — složí se jednou a použije se na celý seznam.
    ///
    /// Vrací se konkrétní typ z Foundation schválně: je to interní pomůcka pro volající uvnitř
    /// `Policy`, ne součást odpovědi, kterou by čtlo view.
    static func momentAgoFormatter() -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter
    }
}
