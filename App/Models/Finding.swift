import Foundation

/// Nález, jak si ho aplikace pamatuje.
///
/// K tomu, co nahlásil reviewer, přidává dvě věci, které ve streamu nejsou a vědět je může
/// jen aplikace: **kdo** nález našel (skill) a **proti čemu** (`headSha`). To druhé je
/// tvrdá podmínka — nálezy se klíčují head commitem, aby se po nových commitech nezobrazily
/// proti kódu, který už neexistuje.
struct Finding: Hashable, Codable, Sendable {
    let reported: ReportedFinding
    let reviewer: String
    let headSha: String
    /// Texty v jazyce z nastavení. `nil` = nepřekládalo se (reviewer už psal tím jazykem)
    /// nebo se to nepovedlo; pak se ukazuje originál.
    ///
    /// Volitelné i v uloženém tvaru — starší záznamy ho nemají a přijít o ně kvůli novému
    /// poli by znamenalo ztracené nálezy.
    let translation: FindingTranslation?

    init(
        reported: ReportedFinding,
        reviewer: String,
        headSha: String,
        translation: FindingTranslation? = nil
    ) {
        self.reported = reported
        self.reviewer = reviewer
        self.headSha = headSha
        self.translation = translation
    }

    var file: String? { reported.file }
    var line: Int? { reported.line }
    var category: String? { reported.category }
    var verdict: FindingVerdict? { reported.verdict }

    // Texty ke zobrazení. Překlad má přednost, ale **po polích**: kdyby překladateli jedno
    // pole vypadlo, je jeden anglický řádek pořád lepší než chybějící text. Ztracená věta
    // se v UI nedá odlišit od věty, kterou reviewer nenapsal.
    var summary: String { translation?.summary ?? reported.summary }
    var failureScenario: String? { translation?.failureScenario ?? reported.failureScenario }
    var shortSummary: String? { translation?.shortSummary ?? reported.shortSummary }
}
