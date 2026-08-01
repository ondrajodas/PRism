import Foundation

/// Co se v běhu právě stalo. Podklad pro odznak v seznamu a pro tab Průběh.
enum ReviewProgress: Sendable, Equatable {
    /// Čeká na volný slot v limitu souběžných session.
    ///
    /// Hlásí se **vždycky**, i když je slot volný hned. Rozlišovat „čekal“ od „nečekal“ by
    /// znamenalo hádat, jestli se `acquire` opravdu uspalo, a UI z toho nic nemá.
    case queued
    /// Session naběhla; `sessionID` drží cestu k `claude --resume`.
    case started(sessionID: String)
    /// Reviewer si řekl o nástroj. **Pokus, ne použití** — odmítnutý nástroj je tu taky.
    case attemptedTool(String)
    /// Kolik nálezů zatím dorazilo.
    case findings(count: Int)
}

/// Kam běh hlásí průběh.
///
/// Synchronní schválně: události mají pořadí a to pořadí je v tabu Průběh vidět. Kdyby
/// každá odbíhala do vlastního tasku, rozhodovalo by o něm plánování, ne stream.
typealias ReviewProgressHandler = @Sendable (ReviewProgress) -> Void
