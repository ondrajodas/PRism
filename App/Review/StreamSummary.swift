import Foundation

/// Co z jednoho běhu review vypadlo.
struct StreamSummary: Sendable, Equatable {
    var sessionID: String?
    var findings: [ReportedFinding] = []
    /// Zavolal reviewer `ReportFindings`?
    ///
    /// Odděleno od prázdného seznamu schválně: „nic jsem nenašel“ (nástroj zavolaný
    /// s prázdným polem) a „nereportoval jsem“ (nezavolaný nástroj) jsou různé věci.
    /// To druhé znamená, že se nálezy nemají kde vzít — třeba proto, že `ReportFindings`
    /// chybělo v `--allowedTools` (viz `docs/claude-cli.md`).
    var calledReportFindings = false
    /// Nástroje v pořadí, jak si o ně reviewer řekl — pro tab Průběh.
    ///
    /// **Pokusy, ne použití:** odmítnutý nástroj je tu taky. Tvrdit „použil“ by u `Write`
    /// znamenalo hlásit, že reviewer zapisoval do repa, což je přesně to, co nesmí. Jak pokus
    /// dopadl, nese od #326 `ToolAttempt.outcome` — a `nil` v něm znamená „ještě běží“.
    var attemptedTools: [ToolAttempt] = []
    /// Odpovědi na pokusy v pořadí, jak dorazily (#326).
    ///
    /// Přírůstek čte `ClaudeReviewRunner` a posílá ho do osy — tedy stejně, jako to dělá
    /// s `attemptedTools`. Bez toho seznamu by musel po každém řádku porovnávat celé pole
    /// pokusů, aby zjistil, kterému z nich se právě změnil stav.
    var resolvedTools: [ToolResolution] = []
    // **`deniedTools` tady od #326 není** a je to úklid, ne opomenutí. Bylo to pole jmen plněné
    // z `permission_denials`, tedy ze závěrečného `result` eventu — takže zabitý běh odmítnutí
    // neměl vůbec a **nikdo to pole nečetl**: ukázat se dalo jen u kroku, a krok o svém odmítnutí
    // nevěděl. Od #326 ho nese `ToolAttempt.outcome`, tedy tam, kde se kreslí; druhý seznam by byl
    // druhá pravda o tom samém. `permission_denials` zůstává jako **záchrana** — dopisuje odmítnutí
    // pokusu, kterému odpověď nedorazila (viz `StreamParser.rescueDenials`).
    /// Konec běhu. `nil` znamená, že `result` event nedorazil — typicky zabitý běh, ale
    /// taky rozbitý poslední řádek nebo proces, který vůbec nenaběhl.
    var outcome: ReviewOutcome?
    /// Co běh stál (#148). Ze stejného eventu jako `outcome`, takže **zabitý běh ji nemá** —
    /// a `nil` je proto vlastní odpověď, ne nula. Nula by tvrdila, že běh byl zdarma.
    var usage: RunUsage?
    /// Kolik řádků se nepodařilo přečíst. Nenulové číslo neznamená chybu běhu, ale stojí
    /// za zmínku v UI.
    var malformedLines = 0
    /// Kolik nálezů se nepodařilo přečíst. **Musí být vidět:** bez toho je „nález bez
    /// povinného pole“ k nerozeznání od „nic jsem nenašel“ — tedy od schváleného PR.
    var droppedFindings = 0
}

/// Konec běhu podle `result` eventu.
struct ReviewOutcome: Sendable, Equatable {
    let isError: Bool
    let subtype: String
    let text: String?
}
