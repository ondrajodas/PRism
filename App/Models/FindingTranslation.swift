import Foundation

/// Texty nálezu přeložené do jazyka z nastavení.
///
/// Vlastní typ, ne přepsaný `ReportedFinding`: ten je **to, co poslal reviewer**, a na tom
/// stojí celý `ReviewStore`. Překlad je zobrazení, ne tvrzení — originál musí zůstat.
///
/// Nese jen prózu. `category` se nepřekládá (je to slug, na který se váže blokující sada),
/// `file`, `line` ani `verdict` prózou nejsou.
struct FindingTranslation: Hashable, Codable, Sendable {
    let summary: String
    let shortSummary: String?
    let failureScenario: String?

    init(summary: String, shortSummary: String? = nil, failureScenario: String? = nil) {
        self.summary = summary
        self.shortSummary = shortSummary
        self.failureScenario = failureScenario
    }
}
