import Foundation

extension Collection {
    /// Prvek na indexu, nebo `nil` mimo rozsah.
    ///
    /// Používá se tam, kde se **páruje pořadím** dvou seznamů, o kterých se ví, že si odpovídají
    /// (draft a payload z něj složený). Pád na neplatném indexu by tam byl chybný způsob, jak
    /// říct „rozešly se“ — ta situace nemá položit okno, má se v něm prostě nevykreslit údaj.
    subscript(safely index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
