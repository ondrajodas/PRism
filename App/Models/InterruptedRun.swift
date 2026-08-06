import Foundation

/// Běh, o kterém aplikace ví, že začal — a neví, jestli doběhl (#97).
///
/// Značka se zapíše, jakmile dorazí `session_id`, a maže se uložením výsledku. Co v ní po
/// startu zbylo, jsou běhy, které aplikaci nepřežily: pád, `kill`, restart Macu. Nálezy z nich
/// **nejsou pryč** — `claude` je má v transcriptu, který se najde podle `sessionID`
/// a `worktree` (viz `TranscriptLocation`).
///
/// Drží i **cestu ke stromu**, ne jen klíč běhu: transcript se bez ní nedá najít a strom si
/// aplikace pojmenovává podle `(PR, headSha)`, takže by se musela skládat podruhé — druhá
/// cesta k témuž údaji je druhé místo, kde se dá minout.
struct InterruptedRun: Codable, Hashable, Sendable {
    let pullRequest: PRIdentifier
    let headSha: String
    let skill: String
    let sessionID: String
    /// Pracovní strom, ve kterém session běžela.
    let worktree: URL

    /// Klíč běhu, pod kterým se výsledek ukládá.
    var key: ReviewRunKey {
        ReviewRunKey(pullRequest: pullRequest, headSha: headSha, skillID: skill)
    }
}
