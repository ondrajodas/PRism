import Foundation

/// Počet s podstatným jménem v českém tvaru.
///
/// `Text("\(count) nálezů")` dá „1 nálezů“ a jazyk aplikace je čeština, takže to praští do
/// očí hned. Tvary se rozlišují na třech místech v okně (soubory, nálezy, nepřečtené
/// řádky), a tři kopie stejného `switch`e by se dřív nebo později rozešly.
enum Plural {
    /// `1` → `one`, `2`–`4` → `few`, zbytek → `many`. Čeština nemá zvláštní tvar pro 21
    /// ani 101, takže víc pravidel není potřeba.
    static func czech(_ count: Int, one: String, few: String, many: String) -> String {
        "\(formatted(count)) \(word(for: count, one: one, few: few, many: many))"
    }

    private static func word(for count: Int, one: String, few: String, many: String) -> String {
        switch count {
        case 1: one
        case 2...4: few
        default: many
        }
    }

    /// Počet **je** množství, takže se skupinuje podle locale — na rozdíl od čísla PR nebo
    /// čísla řádku, které se píšou `verbatim`.
    private static func formatted(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic))
    }
}
