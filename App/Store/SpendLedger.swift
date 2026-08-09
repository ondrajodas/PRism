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
    /// Obsah souboru: dnešek a **posledních pár dní zpátky** (#181).
    ///
    /// Do #181 se držel jen dnešek. Historii si vyžádal dashboard, kde je útrata sloupcovým
    /// grafem — a ten z jednoho čísla nakreslit nejde. Delší historie by byla jiná otázka
    /// („kolik mě to stojí měsíčně“), na kterou tenhle soubor odpovídat nemá.
    private struct Tally: Codable, Equatable {
        var day: String
        var spend: DailySpend
        /// Starší dny, od nejnovějšího. Nikdy víc než `historyLength`.
        var history: [DaySpend] = []
    }

    /// Kolik dní zpátky se pamatuje — sedm, protože tolik má sloupců graf v dashboardu.
    static let historyLength = 7

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

    /// Útrata po dnech pro graf — od nejstaršího k dnešku, včetně **dnů, kdy se neutratilo nic**.
    ///
    /// Prázdné dny se dopočítávají schválně: graf bez nich by tři sloupce vedle sebe ukázal jako
    /// tři po sobě jdoucí dny, i kdyby mezi nimi byl týden pauzy — a sloupec by tím přestal
    /// znamenat den.
    func recentDays(_ count: Int = historyLength) -> [DaySpend] {
        let tally = today()
        let known = Dictionary(
            (tally.history + [DaySpend(day: tally.day, spend: tally.spend)]).map { ($0.day, $0) },
            uniquingKeysWith: { _, newer in newer }
        )
        return Self.days(endingAt: time.now, count: count).map {
            known[$0] ?? DaySpend(day: $0, spend: DailySpend())
        }
    }

    /// Dnešek podle **místního** dne — je to lidský den, ne UTC. Stejně jako `AutoRunLedger`,
    /// aby se ty dvě čísla ve stavovém řádku nelámala každé jinde.
    private func today() -> Tally {
        let day = Self.day(from: time.now)
        if let cached, cached.day == day { return cached }
        // Nepřečtený soubor se bere jako prázdný den, jako u `AutoRunLedger`: na rozdíl od
        // nálezů tady není co ztratit kromě informace o penězích, a hlásit chybu kvůli
        // počitadlu by zabralo místo hláškám, které mají následek.
        //
        // Dekóduje se **jednou**, i když je den starý: obě větve pracují s týmž souborem a druhé
        // čtení by ho po půlnoci louplo z disku podruhé při každém tiku pollingu.
        let stored = try? decoder.decode(Tally.self, from: Data(contentsOf: layout.spendFile))
        guard let stored, stored.day == day else {
            // Nový den se zapamatuje taky, i když se nic nezapsalo: po půlnoci se na útratu
            // ptá každý tik pollingu, a bez toho by se soubor s včerejškem četl každou minutu
            // dokola. Na disk nejde nic — prázdný den se od chybějícího souboru neliší.
            //
            // **Včerejšek se přitom neztrácí**: přesouvá se do historie, jinak by graf po
            // půlnoci osiřel. Soubor bez historie (z doby před #181) se přečte taky, jen
            // s prázdným polem.
            let fresh = Tally(day: day, spend: DailySpend(), history: stored.map { rolled($0) } ?? [])
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

    /// Starý záznam posunutý do historie a **oříznutý** na `historyLength` — bez toho by soubor
    /// rostl donekonečna o dny, které se nikde nekreslí.
    private func rolled(_ previous: Tally) -> [DaySpend] {
        ([DaySpend(day: previous.day, spend: previous.spend)] + previous.history)
            .prefix(Self.historyLength)
            .map { $0 }
    }

    /// Posledních `count` dní končících dneškem, od nejstaršího. Přes `Calendar`, ne odečítáním
    /// 86 400 sekund: letní čas dělá dny o hodinu kratší a delší, takže by se den občas přeskočil.
    private static func days(endingAt date: Date, count: Int) -> [String] {
        let calendar = Calendar.current
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: date).map { day(from: $0) }
        }
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
