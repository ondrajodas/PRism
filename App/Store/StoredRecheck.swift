import Foundation

/// Kontrola nálezů z minula, jak si ji aplikace pamatuje (#150).
///
/// Leží **na záznamu, kterého se ptá** — tedy u nálezů z toho staršího commitu, ne u nálezů
/// nových. Záznam je klíčovaný commitem, na kterém nálezy vznikly, takže `againstHeadSha` je
/// ta **druhá** sha: hlava PR v době kontroly.
///
/// **Není to `StoredReviewRun`** a je to rozhodnutí, ne úspora: „vyřešeno / pořád platí“ je
/// jiná informace než nález. Kdyby to byl běh v `runs`, opakované review týmž skillem by ho
/// přepsalo (`ReviewRecord.replace`), počítal by se do chipů reviewerů, do návrhu verdiktu
/// i do stavu řádku — a kontrola by tím tvrdila, že něco našla.
///
/// **Jedna, ne historie.** Otázka je „co se změnilo od minula“, takže platí ta poslední;
/// starší kontrola nad starším commitem by se musela ukazovat u nálezů, ke kterým se
/// nevztahuje.
struct StoredRecheck: Hashable, Codable, Sendable {
    /// Commit, proti kterému se kontrolovalo — hlava PR v době běhu.
    ///
    /// Bez něj by odznaky visely nad kódem, který v PR už není (tvrdá podmínka č. 5): jak se
    /// hlava posune, kontrola přestane platit a `Policy.recheck(of:head:)` ji označí za
    /// zastaralou.
    let againstHeadSha: String
    /// Jak běh skončil. `failed` nese `detail` na stderr, ze kterého se pozná, co se stalo.
    let outcome: ReviewRunOutcome
    /// Cesta k `claude --resume <id>`.
    let sessionID: String?
    /// Stav po nálezech. Klíč skládá `Policy.key(of:)` — **nikde jinde**, jinak by se páry
    /// tiše rozešly.
    ///
    /// Nálezy, na které kontrola neodpověděla, tady **nejsou** a neukládá se ani jejich počet:
    /// spočítá se proti záznamu (`Policy.recheck(of:head:)`), a to je jediné číslo, které
    /// odpovídá tomu, co je vidět. Uložený počet by po odmítnutí nálezu (#113) přestal platit
    /// a byl by to stav, který nikdo nečte správně.
    let statuses: [FindingKey: RecheckStatus]
    /// Kdy se výsledek zapsal.
    let finishedAt: Date
    /// Co běh stál (#148). `nil` znamená „nevíme“, ne nula — stejná úmluva jako u běhu.
    let usage: RunUsage?

    init(
        againstHeadSha: String,
        outcome: ReviewRunOutcome,
        sessionID: String?,
        statuses: [FindingKey: RecheckStatus],
        finishedAt: Date,
        usage: RunUsage? = nil
    ) {
        self.againstHeadSha = againstHeadSha
        self.outcome = outcome
        self.sessionID = sessionID
        self.statuses = statuses
        self.finishedAt = finishedAt
        self.usage = usage
    }
}
