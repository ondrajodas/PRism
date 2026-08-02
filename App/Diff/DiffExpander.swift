import Foundation

/// Skrytý úsek souboru — kód, který v diffu není a dá se dotáhnout.
///
/// Čísla jsou v **novém** souboru. Stará se dopočítají posunem, který nadělaly předchozí
/// hunky: bez něj by rozbalený řádek ukazoval cizí staré číslo.
struct DiffExpander: Equatable, Sendable {
    let firstLine: Int
    /// `nil` u úseku za posledním hunkem, dokud není načtený obsah — kde soubor končí,
    /// se z diffu vyčíst nedá.
    let lastLine: Int?
    /// `staré číslo = nové − shift`.
    let shift: Int

    var hiddenCount: Int? {
        lastLine.map { $0 - firstLine + 1 }
    }

    /// Rozsah, který odkryje krok dolů (od začátku úseku).
    func stepDown(_ step: Int) -> ClosedRange<Int> {
        firstLine...min(firstLine + step - 1, lastLine ?? .max)
    }

    /// Rozsah, který odkryje krok nahoru (od konce úseku). `nil`, dokud konec neznáme.
    func stepUp(_ step: Int) -> ClosedRange<Int>? {
        guard let lastLine else { return nil }
        return max(lastLine - step + 1, firstLine)...lastLine
    }

    /// Celý úsek. `nil`, dokud konec neznáme.
    var whole: ClosedRange<Int>? {
        lastLine.map { firstLine...$0 }
    }
}
