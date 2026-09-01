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
    /// **První krok** srovnání větve (#466): přehrát commity nad základem **v kopii repa**.
    ///
    /// Potvrzení nemá, a je to schválně: rebase běží v cache, nic neopouští stroj a dá se to vzít
    /// zpět jedním tlačítkem. Nevratná je až druhá půlka — proto `push` níž.
    var sync: @MainActor () -> Void = {}
    /// **Druhý krok**: otevřít potvrzení přetlačení. **Neodesílá nic** — sheet je poslední brána
    /// a pushuje se z něj, tatáž konstrukce jako u merge.
    var push: @MainActor () -> Void = {}
    /// Zahodit, co po srovnání zůstalo v cache — rozdělaný rebase **i** přerovnanou větev, která
    /// neodešla.
    var discardSync: @MainActor () -> Void = {}
    /// Zapomenout hlášku o tom, jak dopadlo poslední srovnání.
    var clearSync: @MainActor () -> Void = {}
    /// Přepnout vlastní draft na *ready for review* (#482). **Odesílá to rovnou** — potvrzení
    /// nemá, protože payload je jeden bit; zdůvodnění je u `PanelBranchView.readyButton`.
    var markReady: @MainActor () -> Void = {}
    /// Zapomenout větu o tom, že se přepnutí nepovedlo.
    var clearReadyFailure: @MainActor () -> Void = {}
    /// Zabít session, která slévá konflikty (#467). Rozdělaný rebase v cache **zůstane** — zahodit
    /// ho za člověka by znamenalo zahodit i to, co už session slila.
    var cancelSync: @MainActor () -> Void = {}
    /// Otevřít zásuvku s terminálem **v tom stromě, kde rebase uvázl** (#467, návrh sekce 36).
    ///
    /// Je to ta půlka „co nerozřeší, nechá být“: v rozdělaném rebase má člověk plnou moc a kontext
    /// připravený, takže se nabízí místo hádání.
    var openTerminal: @MainActor () -> Void = {}
}
