import Foundation

/// Proč místo diffu nic není (#542).
///
/// **Výčet, ne řetězec**, a je to tentýž důvod jako u `GitHubError`: každý případ vede v okně
/// jinam. Do #542 tu byl jeden `String` a všechny příčiny se v něm slily do jedné věty
/// „Diff se nepodařilo načíst“ — takže z okna nešlo poznat, jestli je pull request nad stropem
/// GitHubu, jestli vypršel token, nebo jestli je repo nedostupné. Tři různé příčiny, jeden text.
///
/// Rozdíl mezi nimi není kosmetika: **u stropu je druhý pokus marný** (odpověď bude stejná,
/// dokud se nepřepíše historie) a **zbytek pull requestu se přesto dá číst** — přehled, commity,
/// kontroly i konverzace na diffu nestojí. U ostatních selhání je opakování naopak to jediné
/// rozumné, co se dá nabídnout.
enum DiffFailure: Equatable, Sendable {
    /// GitHub diff nevydal, protože pull request mění víc souborů, než jeho API pustí.
    ///
    /// - Parameters:
    ///   - limit: strop **přečtený z odpovědi**, ne konstanta v aplikaci — `nil`, když v ní
    ///     číslo nebylo. Kolik souborů pull request mění, aplikace v tu chvíli neví: dozvěděla
    ///     by se to právě z toho diffu, který nedorazil.
    ///   - response: syrová odpověď, jak přišla od `gh`.
    case tooManyFiles(limit: Int?, response: String)
    /// Cokoli jiného — text je věta od `GitHubError`, tedy to, co se ukazovalo vždycky.
    case other(String)
}
