import Foundation

/// Co se dá dělat s nálezem (#113) — jedno místo pro bublinu u kódu i pro tabulku v panelu.
///
/// Rozhoduje store, ne view: bublina je buňka líného seznamu nad diffem, takže by si vlastní
/// stav při odscrollování zahodila. A dvě kopie téhle logiky by znamenaly, že se v jedné
/// z nich zapomene — tatáž úvaha jako u `ThreadActions`.
///
/// Jak nález dopadl, se **nepředává akcí**, ale daty (`FindingGroup.dismissal(of:)`,
/// `FindingRow.dismissal`): stav patří k tomu, co se kreslí, ne k tomu, co se dá zmáčknout.
struct FindingActions {
    var dismiss: (Finding, FindingDismissal.Reason) -> Void = { _, _ in }
    var restore: (Finding) -> Void = { _ in }
}
