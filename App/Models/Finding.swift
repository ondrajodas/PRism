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

    init(reported: ReportedFinding, reviewer: String, headSha: String) {
        self.reported = reported
        self.reviewer = reviewer
        self.headSha = headSha
    }

    var file: String? { reported.file }
    var line: Int? { reported.line }
    var category: String? { reported.category }
    var verdict: FindingVerdict? { reported.verdict }
    var summary: String { reported.summary }
    var failureScenario: String? { reported.failureScenario }
    var shortSummary: String? { reported.shortSummary }
}
