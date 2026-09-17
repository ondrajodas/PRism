import Foundation

/// Tři věty o stavu aplikace, které složila session bez nástrojů (#516).
///
/// **Je to výsledek běhu, ne nález.** Neváže se na `headSha` žádného pull requestu (tvrdá
/// podmínka č. 5 se ho tedy netýká, stejně jako rozhovoru nad PR z #452) a nic z něj neplyne —
/// když se rozejde se skutečností, nová deska je o tik dál, kdežto brief zůstává tam, kde byl.
/// Proto u sebe nese **kdy vznikl**: věta o frontě z rána je v šest večer text o minulosti.
struct Brief: Codable, Equatable, Sendable {
    /// Co session napsala. Jeden odstavec, sražený na řádku (`BriefCommand.parse`).
    let text: String
    /// Kdy se shrnovalo. Do řádku pod textem — brief bez razítka tvrdí, že platí teď.
    let writtenAt: Date
    /// Co ten běh stál. **`nil` není nula**: zabitá session peníze stála taky, jen o nich nevíme
    /// (tatáž úvaha jako u `RunUsage.cost` a `DailySpend.unknown`).
    let cost: Double?
}

/// V jakém stavu je brief na desce (#516).
///
/// **Čtyři stavy, ne text a `Bool`.** Prázdný blok je k nerozeznání od „nic se neděje“, takže
/// každý stav má vlastní větu — a spadlá session ji má taky, protože právě ta by jinak vypadala
/// jako prázdno.
enum BriefState: Equatable, Sendable {
    /// Ještě se neshrnovalo — po prvním zapnutí a po startu, než se přečte uložený brief.
    case never
    /// Session běží.
    case running
    /// Hotovo. Text i razítko jsou v `Brief`.
    case ready(Brief)
    /// Session spadla, vytimeoutovala nebo nic nenapsala. **Důvod se ukazuje**; bez něj je to
    /// zase jen prázdno, jen s rámečkem.
    case failed(reason: String)

    /// Běží zrovna něco? Rozhoduje o tom, že se druhá session nespustí — a o tom, že tlačítko
    /// v bloku nebere kliknutí.
    var isRunning: Bool { self == .running }

    /// Poslední hotový brief, jestli nějaký je.
    var brief: Brief? {
        guard case .ready(let brief) = self else { return nil }
        return brief
    }
}
