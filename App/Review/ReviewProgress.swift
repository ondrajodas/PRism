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
    case attemptedTool(ToolAttempt)
    /// Na pokus dorazila odpověď (#326): prošel, vrátil chybu, nebo byl odmítnut.
    ///
    /// **Není to nový krok, je to zavření toho, co v ose už je** — osa proto podle téhle události
    /// neroste a neposouvá se. Chodí zvlášť, a ne jako nový `attemptedTool`, přesně proto: jeden
    /// `tool_use` je v ose jeden řádek, ať se o něm dozvíme cokoli dalšího.
    case resolvedTool(ToolResolution)
    /// Kolik nálezů zatím dorazilo.
    case findings(count: Int)
    /// Zadání pro reviewera **není celé** (#345) — a proč.
    ///
    /// Hlásí se **na začátku běhu, ne po jeho konci**, a je to podmínka: zadání se připravuje před
    /// spuštěním session, takže v tu chvíli je odpověď hotová a nemá cenu s ní čekat. Pozdní
    /// událost by navíc mohla dorazit do osy, kterou už nikdo nečte.
    ///
    /// Hlásí se **za každého revieweera**, i když je to fakt o celém review: příznak žije na dráze
    /// (`ReviewerLane`), takže dráha bez události by o sobě tvrdila, že zadání dostala celé.
    case intentGap(IntentGap)
}

/// Kam běh hlásí průběh.
///
/// Synchronní schválně: události mají pořadí a to pořadí je v tabu Průběh vidět. Kdyby
/// každá odbíhala do vlastního tasku, rozhodovalo by o něm plánování, ne stream.
typealias ReviewProgressHandler = @Sendable (ReviewProgress) -> Void
