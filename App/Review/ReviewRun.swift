import Foundation

/// Výsledek jednoho běhu review.
struct ReviewRun: Sendable, Equatable {
    let key: ReviewRunKey
    /// Co vypadlo ze streamu — nálezy, session id, pokusy o nástroje, počty nepřečteného.
    let summary: StreamSummary
    let outcome: ReviewRunOutcome

    /// Nálezy doplněné o to, co ví jen aplikace: **kdo** je našel a **proti čemu**.
    var findings: [Finding] {
        summary.findings.map {
            Finding(reported: $0, reviewer: key.skillID, headSha: key.headSha)
        }
    }

    var sessionID: String? { summary.sessionID }
}

/// Jak běh skončil.
///
/// `finished` **není** totéž co „něco našel“: doběhlá session bez nálezů je čisté review,
/// ne selhání. Rozlišit se to musí tady, protože výš už to nikdo nepozná — a schválený PR
/// s neohlášenou chybou je nejdražší chyba, kterou tahle aplikace umí udělat.
enum ReviewRunOutcome: Sendable, Hashable, Codable {
    /// Proces doběhl s nulovým návratovým kódem.
    case finished
    /// Nedoběhl v limitu a byl zabit. Nálezy, které do té doby dorazily, jsou v `summary`.
    case timedOut
    /// Nespustil se nebo skončil nenulovým kódem; `detail` je stderr, na kterém stojí UI.
    case failed(detail: String)
}
