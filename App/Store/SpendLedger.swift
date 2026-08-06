import Foundation

/// Kolik dneska stálo review (#148).
///
/// **Vlastní počitadlo na disku, ne součet z uložených záznamů.** Vypadá to jako druhé místo,
/// které se umí rozejít s pravdou, ale odpovídá to na **jinou otázku**: `ReviewRecord` říká, co
/// který běh našel proti danému commitu, kdežto tohle říká, co mě dneska stálo utracení session.
/// Ty dvě věci se rozcházejí zákonitě a správně:
///
/// - **Zahozený záznam** (#81) i uklizený starý záznam (třicetidenní lhůta) by ze součtu peníze
///   odečetly. Utracené ale zůstaly utracené — číslo, které klesne tím, že zmáčknu koš, je
///   o mém účtu lež.
/// - Součet by musel při **každém** vykreslení projít a dekódovat celý výpis `reviews/`.
///   `AppStore` si přitom v paměti nechává jen `Policy.currentRecords`, takže by se na disk
///   muselo znovu — tedy „čtení všeho, když stačí předfiltr“ u operace, která běží pořád.
///
/// Na disku ze stejného důvodu jako `AutoRunLedger`: číslo, které vynuluje restart, na otázku
/// „co mě dneska stálo review“ neodpovídá. Aktor taky ze stejného důvodu — čtení, přičtení
/// a zápis jednoho souboru, a tři reviewery doběhnou klidně naráz.
actor SpendLedger {
    /// Obsah souboru. Jen dnešek, jako u `AutoRunLedger`: historie útraty se drží v release
    /// notes účtu, ne tady, a starý den se přepíše.
    private struct Tally: Codable, Equatable {
        var day: String
        var spend: DailySpend
    }

    private let layout: CacheLayout
    private let time: any TimeSource
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Počitadlo, se kterým se pracuje. Disk je **záloha**, ne jediná kopie — viz `write`.
    private var cached: Tally?

    init(layout: CacheLayout = .applicationSupport, time: any TimeSource = SystemTimeSource()) {
        self.layout = layout
        self.time = time
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// Přičte, co jeden doběhlý běh stál. `nil` znamená „cenu nenahlásil“ a počítá se do
    /// `unknown`, ne do nuly: zabitá session peníze stála taky, jen o nich nevíme.
    @discardableResult
    func record(_ usage: RunUsage?) -> DailySpend {
        var tally = today()
        if let cost = usage?.cost {
            tally.spend.cost += cost
            tally.spend.runs += 1
        } else {
            tally.spend.unknown += 1
        }
        write(tally)
        return tally.spend
    }

    func spentToday() -> DailySpend {
        today().spend
    }

    /// Dnešek podle **místního** dne — je to lidský den, ne UTC. Stejně jako `AutoRunLedger`,
    /// aby se ty dvě čísla ve stavovém řádku nelámala každé jinde.
    private func today() -> Tally {
        let day = Self.day(from: time.now)
        if let cached, cached.day == day { return cached }
        // Nepřečtený soubor se bere jako prázdný den, jako u `AutoRunLedger`: na rozdíl od
        // nálezů tady není co ztratit kromě informace o penězích, a hlásit chybu kvůli
        // počitadlu by zabralo místo hláškám, které mají následek.
        guard let stored = try? decoder.decode(Tally.self, from: Data(contentsOf: layout.spendFile)),
              stored.day == day
        else {
            // Nový den se zapamatuje taky, i když se nic nezapsalo: po půlnoci se na útratu
            // ptá každý tik pollingu, a bez toho by se soubor s včerejškem četl každou minutu
            // dokola. Na disk nejde nic — prázdný den se od chybějícího souboru neliší.
            let fresh = Tally(day: day, spend: DailySpend())
            cached = fresh
            return fresh
        }
        cached = stored
        return stored
    }

    /// Zapíše počitadlo — **nejdřív do paměti, pak na disk**, ze stejného důvodu jako
    /// `AutoRunLedger`: trvale selhávající zápis nemá číslo držet na nule.
    private func write(_ tally: Tally) {
        cached = tally
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try? encoder.encode(tally).write(to: layout.spendFile, options: .atomic)
    }

    /// `yyyy-MM-dd` v místní zóně, `posix` locale — ať se den nepojmenuje pokaždé jinak podle
    /// nastavení systému.
    private static func day(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
