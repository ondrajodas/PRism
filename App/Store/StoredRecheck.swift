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
    /// Stav po **mých odeslaných komentářích** (#522). Klíčem je **identita vlákna z GitHubu**,
    /// ne `FindingKey`: komentář není nález a jeho text se mezi koly mění, kdežto identita ne.
    ///
    /// Vlastní mapa, ne přimíchání do `statuses`: dvě klíčování v jedné mapě je tiché
    /// rozpárování — nález a vlákno by v ní nešly od sebe poznat.
    ///
    /// **Že mi někdo do vlákna odpověděl, tady není** a nebude: to je fakt z konverzace (#72),
    /// který se čte živě. Uložit ho sem by znamenalo zmrazit ho do chvíle posledního běhu a od
    /// té chvíle o něm v okně lhát.
    let replyStatuses: [String: RecheckStatus]
    /// Kdy se výsledek zapsal.
    let finishedAt: Date
    /// Co běh stál (#148). `nil` znamená „nevíme“, ne nula — stejná úmluva jako u běhu.
    let usage: RunUsage?

    init(
        againstHeadSha: String,
        outcome: ReviewRunOutcome,
        sessionID: String?,
        statuses: [FindingKey: RecheckStatus],
        replyStatuses: [String: RecheckStatus] = [:],
        finishedAt: Date,
        usage: RunUsage? = nil
    ) {
        self.againstHeadSha = againstHeadSha
        self.outcome = outcome
        self.sessionID = sessionID
        self.statuses = statuses
        self.replyStatuses = replyStatuses
        self.finishedAt = finishedAt
        self.usage = usage
    }

    /// Dekóduje se ručně **jen kvůli `replyStatuses`** (#522): syntetizovaný `init(from:)` sahá
    /// na každý neoptional klíč bez ohledu na výchozí hodnotu, takže by soubor uložený do #522
    /// (a je jich na disku plno) skončil `keyNotFound` — tedy ztracenou kontrolou kvůli poli,
    /// které v něm být nemůže. Tatáž úvaha jako u `dismissals` v `ReviewRecord`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        againstHeadSha = try container.decode(String.self, forKey: .againstHeadSha)
        outcome = try container.decode(ReviewRunOutcome.self, forKey: .outcome)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        statuses = try container.decode([FindingKey: RecheckStatus].self, forKey: .statuses)
        replyStatuses = try container.decodeIfPresent(
            [String: RecheckStatus].self,
            forKey: .replyStatuses
        ) ?? [:]
        finishedAt = try container.decode(Date.self, forKey: .finishedAt)
        usage = try container.decodeIfPresent(RunUsage.self, forKey: .usage)
    }
}
