import Foundation

/// Rozbalení bubliny nálezu u kódu (#185) — jeden parametr místo dvou closures, které patří
/// k sobě, stejně jako u `ThreadActions`.
///
/// **Rozhoduje store, ne view.** Bublina je buňka líného seznamu, takže `@State` v ní
/// odscrollování nepřežije — a diff sám se přestaví při každém složení panelu vpravo, takže by
/// stav nepřežil ani tam. Je to tatáž past jako u rozbalení vláken.
///
/// Nepatří do `FindingActions`: tu drží detail PR **jedna** pro panel, tabulku i diff, a
/// v tabulce o rozbalení rozhoduje řádek sám. Sdílená hodnota by tedy tabulce zavřela nález,
/// který si člověk v ní otevřel.
struct FindingDisclosureActions {
    /// Jak je skupina rozbalená. Výchozí `.expanded` platí tam, kde o rozbalení rozhoduje
    /// volající — tabulka nálezů kreslí bublinu až po rozbalení řádku, takže by sbalená
    /// bublina uvnitř rozbaleného řádku neukázala nic.
    var state: (FindingGroup) -> FindingDisclosure = { _ in .expanded }
    var toggle: (FindingGroup) -> Void = { _ in }
}
