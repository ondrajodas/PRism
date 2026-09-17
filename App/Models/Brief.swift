import Foundation

/// Na kterou ze tří otázek řádek briefu odpovídá (#516).
///
/// **Tři pojmenované části, ne odstavec** — a je to změna po proklikání: odstavec na čtyři řádky
/// natěsnal tři různé věci do souvislé prózy, takže se musel přečíst celý, aby z něj vypadla
/// jedna. Smysl briefu je přitom ten, že je **levnější než přečíst čtyři bloky pod ním**; špalek
/// textu tu vlastnost ruší.
///
/// **Návěští odpovídá otázce, ne pořadí.** Proto ne odrážky a ne číslované body: tři puntíky
/// vypadají jako výčet jednoho druhu věcí, kdežto tohle jsou tři **různé otázky**, a číslo by
/// navíc tvrdilo pořadí důležitosti, které nikdo nerozhodl.
///
/// **Část, na kterou ve vstupu odpověď není, se vynechá celá** — proto `[BriefLine]`, ne trojice
/// polí. Struktura, která si vynutí větu na každou otázku, je zrovna ta cesta, kterou se do
/// briefu dostane tvrzení, pro které nejsou data.
enum BriefPart: String, Codable, CaseIterable, Hashable, Sendable {
    /// Co přibylo nebo doběhlo.
    case added
    /// Co nejvíc hoří.
    case burning
    /// Co si vzít první.
    case next

    /// Klíč, kterým session řádek uvozuje (`ADDED:`).
    ///
    /// **ASCII a velkými, ne český popisek.** Podle klíče se odpověď parsuje a diakritika v něm je
    /// o jeden způsob, jak se dá rozejít, víc — model ji umí napsat bez háčků a řádek by propadl.
    /// Popisek v okně stojí vedle (`title`) a mění se nezávisle na protokolu.
    var key: String { rawValue.uppercased() }

    /// Návěští v okně. Krátké schválně: je to sloupec vedle vět, ne nadpis.
    var title: String {
        switch self {
        case .added: "Přibylo"
        case .burning: "Hoří"
        case .next: "První na řadě"
        }
    }
}

/// Jeden řádek briefu — na kterou otázku odpovídá a co na ni session odpověděla (#516).
struct BriefLine: Codable, Equatable, Sendable {
    let part: BriefPart
    let text: String
}

/// Shrnutí stavu aplikace, které složila session bez nástrojů (#516).
///
/// **Je to výsledek běhu, ne nález.** Neváže se na `headSha` žádného pull requestu (tvrdá
/// podmínka č. 5 se ho tedy netýká, stejně jako rozhovoru nad PR z #452) a nic z něj neplyne —
/// když se rozejde se skutečností, nová deska je o tik dál, kdežto brief zůstává tam, kde byl.
/// Proto u sebe nese **kdy vznikl**: věta o frontě z rána je v šest večer text o minulosti.
struct Brief: Codable, Equatable, Sendable {
    /// Co session napsala — **jedna až tři pojmenované věty** v pořadí `BriefPart.allCases`.
    ///
    /// **Prázdné pole se sem nedostane**: brief bez jediného řádku je porucha, ne prázdný brief,
    /// a rozhoduje se o tom už v `BriefCommand.parse`.
    let lines: [BriefLine]
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
    /// Hotovo. Řádky i razítko jsou v `Brief`.
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
