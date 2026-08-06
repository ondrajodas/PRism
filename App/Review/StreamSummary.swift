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
    /// Jména nástrojů v pořadí, jak si o ně reviewer řekl — pro tab Průběh.
    ///
    /// **Pokusy, ne použití:** odmítnutý nástroj je tu taky. Tvrdit „použil“ by u `Write`
    /// znamenalo hlásit, že reviewer zapisoval do repa, což je přesně to, co nesmí.
    var attemptedTools: [ToolAttempt] = []
    /// Nástroje, které session chtěla, ale nedostala. Není to chyba běhu.
    ///
    /// Bere se z `result` eventu, takže **zabitý běh je nemá** — u něj se odmítnutí
    /// nedozvíme. Druhý zdroj (`tool_result` s `is_error`) by šlo číst, ale rozeznat
    /// odmítnutí od běžné chyby nástroje se dá jen podle anglického textu hlášky, a to
    /// je křehčí než ta informace stojí.
    var deniedTools: [String] = []
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
