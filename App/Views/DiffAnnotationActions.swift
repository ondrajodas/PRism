import Foundation

/// Popis změn (#524) tak, jak ho vidí lišta nad diffem.
///
/// **Jedna hodnota, ne čtyři parametry vedle sebe**, přesně jako `DiffFoldingActions`: stav a obě
/// akce k sobě patří a rozdělené by šlo předat běh bez zrušení nebo selhání bez opakování — tedy
/// zrovna ty dvojice, kterými se tichý konec vyrábí.
///
/// `nil` na straně lišty znamená **nekreslí se nic**: session není zapojená, hlava PR se nezná,
/// nebo je to obrazovka, na kterou akce nepatří (diff commitu, rozsahový diff, náhled).
struct DiffAnnotationActions {
    /// Ve kterém ze tří stavů ovladač je. Rozhoduje `Policy.annotationControl(isRunning:failure:)`,
    /// ne view — stav je odpověď nad daty, ne kresba.
    let state: Policy.AnnotationControl
    /// Spustit popis změn. Ve stavu `failed` je to „zkusit znovu“, což je tatáž akce.
    let start: () -> Void
    /// Zrušit běžící popis. Session dostane `SIGKILL` a neuloží se nic.
    let cancel: () -> Void
}
