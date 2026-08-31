import Foundation

/// Co se dá v sekci `Větev` udělat (#465) — jedno místo, ne parametry rozeseté po view.
///
/// Tentýž vzor jako `MetadataActions`, `DraftActions` a `ThreadActions`: panel dostane akce jako
/// hodnotu, takže se dá složit i **bez** nich (offscreen render, náhled) a nemusí u toho znát
/// `AppStore`.
///
/// **Struktura, i když byla akce zpočátku jedna.** Sekce je základ i pro `Řešení konfliktů
/// session` (#467), takže další akce sem přibude jako pole — kdežto uzávěr předaný napřímo by se
/// v tu chvíli musel měnit na všech místech, která panel skládají.
struct BranchActions: Sendable {
    /// Otevřít potvrzení merge. **Neodesílá nic** — sheet je poslední brána a odesílá se z něj.
    var merge: @MainActor () -> Void = {}
    /// Srovnat větev se základem a přetlačit ji (#466).
    ///
    /// **Tahle akce potvrzení nemá**, na rozdíl od merge, a je to schválně: přetlačuje se
    /// **vlastní** větev vlastního PR, `--force-with-lease` na pohnutý remote nesáhne a co se
    /// stane, stojí v nápovědě nad tlačítkem. Je to tatáž třída jako label nebo komentář — jedno
    /// pojmenované tlačítko —, ne jako merge, který mění `main`.
    var sync: @MainActor () -> Void = {}
    /// Zahodit rozdělaný rebase v cache (`git rebase --abort`).
    var discardRebase: @MainActor () -> Void = {}
    /// Zapomenout hlášku o tom, jak dopadlo poslední srovnání.
    var clearSync: @MainActor () -> Void = {}
}
