import Foundation

/// Nálezy platí proti jinému commitu, než na kterém PR stojí (#174).
///
/// **Jeden zdroj pro všechna místa, která o tomhle stavu mluví** (#284): hlavičku nad taby
/// (`StaleHeadView`) i okrový odznak v pruhu „od tvé poslední návštěvy“. Do #284 si každé z nich
/// porovnávalo sha samo, takže se mohla rozejít — a přesně to je „druhá pravda“, kterou tvrdá
/// podmínka č. 5 zakazuje.
struct StaleFindings: Equatable, Sendable {
    /// Hlava, na které PR stojí teď.
    let head: String
    /// Sha, proti které nálezy vznikly.
    let findingsHead: String
    /// Je vůbec co zastarat? **Prázdný záznam je běžný stav** — review může doběhnout čistě —
    /// a odznak `nálezy zastaraly` by nad ním tvrdil něco, co data neunesou. Hlavička nad taby
    /// o rozchodu mluví tak jako tak, takže je to hranice mezi nimi, ne mezi „je“ a „není“.
    ///
    /// Počítají se i **odmítnuté** nálezy: odmítnutí nález nesundá (#113), takže je pořád na
    /// obrazovce a pořád patří ke staršímu commitu.
    ///
    /// **Příznak, ne počet**: číslo by se nikde nekreslilo, a držený stav, který nikdo nečte,
    /// svádí k tomu se na něj spolehnout.
    let hasFindings: Bool
}
