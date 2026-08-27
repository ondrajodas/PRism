import Foundation

/// Co se dá v sekci `Větev` udělat (#465) — jedno místo, ne parametry rozeseté po view.
///
/// Tentýž vzor jako `MetadataActions`, `DraftActions` a `ThreadActions`: panel dostane akce jako
/// hodnotu, takže se dá složit i **bez** nich (offscreen render, náhled) a nemusí u toho znát
/// `AppStore`.
///
/// **Struktura, i když je akce zatím jedna.** Sekce je základ pro `Srovnat s main` (#466)
/// a `Řešení konfliktů session` (#467), takže druhá akce sem přibude jako pole — kdežto uzávěr
/// předaný napřímo by se v tu chvíli musel měnit na všech místech, která panel skládají.
struct BranchActions: Sendable {
    /// Otevřít potvrzení merge. **Neodesílá nic** — sheet je poslední brána a odesílá se z něj.
    var merge: @MainActor () -> Void = {}
}
