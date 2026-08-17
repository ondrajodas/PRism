/// Co udělat se stavem hoveru, když přijde nová poloha myši (#358).
///
/// Existuje proto, aby „nezapisuj, když se nic nezměnilo“ bylo **jedno rozhodnutí na jednom místě**,
/// a ne dvě kopie téže podmínky ve dvou views.
enum HoverChange<Cell: Equatable>: Equatable {
    /// Nechat být — hodnota je tatáž, jakou stav drží.
    case unchanged
    /// Zapsat tuhle hodnotu do stavu.
    case write(Cell?)
}

extension Policy {
    /// Jestli se nová hodnota hoveru má zapsat do `@State`, nebo se má stav **nechat být** (#358).
    ///
    /// **Proč to je funkce a ne `if next != hovered { hovered = next }` u volajícího.** Zápis do
    /// `@State` je to, co špiní graf, a `.onContinuousHover` **nedostává jen změny** — poloha přijde
    /// i tehdy, když se myš nehnula, protože si SwiftUI hover update naplánuje po každém přerovnání
    /// obsahu. Bezpodmínečný zápis proto zavíral kolo: zápis → neplatné tělo bloku → neplatné
    /// `LazySubviewPlacements` → přeloží se všechny podviews → změní se geometrie responderů →
    /// `EventBindingManager.enqueueHoverUpdateIfNeeded()` → další hover update. Ve vzorku ztuhlého
    /// okna to bylo **1630 z 1690** vzorků `Update.dispatchActions()` a hlavní vlákno na 99 % CPU.
    ///
    /// **Proč se hodnota vrací a nepředává se `inout`.** `@State` je počítaná vlastnost, takže
    /// `&hovered` by proběhlo přes **setter** i tehdy, když se hodnota nezměnila — a právě setter
    /// graf špiní. Rozhodnutí tedy musí padnout **před** zápisem, ne uvnitř něj.
    ///
    /// **Proč `Cell: Equatable`.** Do #358 byl stav hoveru ve split pohledu tuple
    /// `(index: Int, side: DiffSide)?`, a tuple v Swiftu `Equatable` **není** — takže se nová hodnota
    /// neměla s čím porovnat a žádné „zapiš jen při změně“ tam nebylo možné napsat. Proto je z toho
    /// `HoveredCell`.
    static func hoverChange<Cell: Equatable>(from current: Cell?, to next: Cell?) -> HoverChange<Cell> {
        current == next ? .unchanged : .write(next)
    }
}
