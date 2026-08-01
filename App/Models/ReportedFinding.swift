import Foundation

/// Nález přesně tak, jak ho nahlásil reviewer — nic přidaného.
///
/// Odděleno od `Finding` schválně: tohle je obsah `ReportFindings` tool callu, kdežto
/// `Finding` je to, co si aplikace uloží, tedy včetně toho, kdo nález našel a proti
/// kterému commitu. Leží v `Models`, ne v `Review`, protože na něm staví i `Policy`
/// a `ReviewStore` — modul, který ho vyrábí, si ho nemá vlastnit.
struct ReportedFinding: Hashable, Codable, Sendable {
    /// Volitelné: nález, který nepatří k žádnému řádku (chybějící testy, architektonická
    /// poznámka), je platný a patří do tabulky.
    let file: String?
    let line: Int?
    /// Volný kebab-case slug od reviewera. Aplikace si vlastní škálu nevymýšlí.
    let category: String?
    let verdict: FindingVerdict?
    let shortSummary: String?
    let summary: String
    /// Volitelné: povinné je jen `summary`. Reviewer, který scénář nevyplní, nemá kvůli
    /// tomu o nález přijít — tichá ztráta nálezu se v UI nedá odlišit od čistého review.
    let failureScenario: String?
}

/// Jak si reviewer nálezem stojí. Neznámá hodnota se nehádá — zůstane `nil`.
///
/// **Ne** návrh verdiktu pro celý PR (approve / request changes) — ten patří `Policy`
/// a jmenuje se jinak, aby se ta dvě slova nepletla.
enum FindingVerdict: String, Codable, Sendable {
    case confirmed = "CONFIRMED"
    case plausible = "PLAUSIBLE"
}
