import Foundation

/// Jak dopadl běh agenta na vlastním PR (#511) — **jeden výčet pro všechna tři místa**, která
/// o něm mluví: věta v panelu `Větev`, notifikace a řádek v `Dění`.
///
/// **Existuje proto, že ta tři místa se do #511 neměla o co opřít.** #510 skládalo větu přímo
/// z `BranchSyncState`, takže se dala napsat jedině tam, kde stav je — a notifikace ani dění stav
/// nevidí (přijdou o vteřinu později, ze store). Tři skládání téže věty by se rozešla první
/// úpravou textu; tohle je ta jedna odpověď, ze které si každé místo vezme svou sazbu.
///
/// **Pět případů, ne čtyři ze zadání.** Zadání jmenuje *hotovo / částečně / spadlo / zahozeno*.
/// Chybí v nich `nothing` — a to je stav, který #510 **výslovně** oddělilo od selhání: „nemám co
/// opravit“ a „na tohle nestačím“ je doběhlá práce, po které v cache nic neleží (tečka, ne
/// vykřičník). Slít ho do `failed` by to rozhodnutí zrušilo, slít ho do `partial` by tvrdilo, že
/// část opravy leží v kopii repa, přestože `git` řekl, že se nezměnilo nic.
///
/// **O testech se v žádné z těch vět nemluví, a je to podmínka, ne opomenutí** (#511). Zadání
/// deck mělo tvar *„2 soubory, testy zelené“*; session ale testy pustit **nemůže** (`Bash` v její
/// sadě není, viz `AgentFixCommand`) a aplikace je nad jejím výsledkem nepouští. Věta o zelených
/// testech by tedy tvrdila víc, než data unesou — a je to zrovna ta třída textu, kterou tenhle
/// repozitář hlídá. Hlídá to test (`AgentRunReportTests`), ne tenhle komentář.
enum AgentRunOutcome: Equatable, Sendable {
    /// **Hotovo** — commit leží v kopii repa a agent nic nevynechal.
    case done(files: Int)
    /// **Částečně** — commit leží v kopii repa, ale část zadání agent nechal být **a řekl proč**.
    ///
    /// `skipped` je věta od modelu, takže se sází až na konec: co se stalo, ví aplikace, kdežto
    /// tohle je cizí text neznámé délky.
    case partial(files: Int, skipped: String)
    /// **Nic** — session doběhla a ve stromě se nezměnilo nic. `detail` je věta od ní; `nil`
    /// znamená, že neřekla nic.
    case nothing(detail: String?)
    /// **Spadlo** — session nedoběhla, nebo se nad ní nepovedlo něco, co dělá aplikace.
    case failed(detail: String)
    /// **Zahozeno** — výsledek se **nepřijal**: session psala mimo strom, nedoběhla a něco ve
    /// stromě nechala, nebo ji zrušil člověk. `detail` už nese, co dál.
    case discarded(detail: String)
}
