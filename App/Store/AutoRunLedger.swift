import Foundation

/// Kolik review dnes spustil automat.
///
/// **Na disku, ne v paměti.** Limit je pojistka proti překvapení na účtu a pojistka, kterou
/// obejde restart aplikace, není pojistka — a restart je zrovna to, co se po nečekaném
/// utrácení udělá jako první.
///
/// Aktor ze stejného důvodu jako `ReviewStore`: čtení, zvýšení a zápis jsou tři kroky nad
/// jedním souborem a dvě auto review naráz jsou běžný stav.
actor AutoRunLedger {
    /// Obsah souboru. Jen dnešek — historie se k ničemu nehodí a starý den se přepíše.
    private struct Tally: Codable, Equatable {
        var day: String
        var count: Int
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

    /// Sáhne si o jedno spuštění. `false` znamená, že je na dnešek vyčerpáno.
    ///
    /// Zvýší se **před** spuštěním, ne po doběhnutí: běh trvá minuty a session je utracená
    /// v okamžiku, kdy začne. Počítat až doběhlé by pustilo dvacet běhů naráz.
    func take(limit: Int) -> Bool {
        guard limit > 0 else { return false }
        var tally = today()
        guard tally.count < limit else { return false }
        tally.count += 1
        write(tally)
        return true
    }

    /// Kolik review dnes automat spustil.
    ///
    /// Vrací se **spotřeba, ne zbytek**: zbytek závisí na limitu, a ten se dá v nastavení
    /// změnit kdykoli. Kdyby se z toho udělal snímek „zbývá 0“, držel by se až do dalšího
    /// tiku i po tom, co se limit zvedne — a UI by tvrdilo, že je pozastaveno, i když není.
    func used() -> Int {
        today().count
    }

    /// Dnešek podle **místního** dne — je to lidský den, ne UTC.
    private func today() -> Tally {
        let day = Self.day(from: time.now)
        if let cached, cached.day == day { return cached }
        // Nepřečtený soubor se bere jako prázdný den. Je to opačná volba než u nálezů, kde
        // se rozbitý soubor hlásí: tady je nejhorší následek pár běhů navíc, kdežto
        // zablokovat automat kvůli nečitelnému počitadlu by ho umlčelo potichu.
        guard let stored = try? decoder.decode(Tally.self, from: Data(contentsOf: layout.autoRunsFile)),
              stored.day == day
        else { return Tally(day: day, count: 0) }
        // Zapamatovat se to musí i po **čtení**, ne jen po zápisu. Jinak se disk čte
        // pokaždé znovu a jediné přechodné selhání čtení vrátí počitadlo na nulu — tedy
        // stejná díra v pojistce, kvůli které je zdrojem pravdy paměť.
        cached = stored
        return stored
    }

    /// Zapíše počitadlo — **nejdřív do paměti, pak na disk**.
    ///
    /// Pořadí je podstatné. Kdyby se počítalo jen podle souboru, trvale selhávající zápis
    /// (plný disk, práva) by počitadlo nikdy neposunul a limit by přestal platit **úplně** —
    /// tedy přesně to, proti čemu je. S pamětí jako zdrojem pravdy zůstane rozbitý disk
    /// nejvýš tím, že se limit resetuje restartem.
    private func write(_ tally: Tally) {
        cached = tally
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try? encoder.encode(tally).write(to: layout.autoRunsFile, options: .atomic)
    }

    /// `yyyy-MM-dd` v místní zóně. `DateFormatter` s `posix` locale, ať se den nepojmenuje
    /// pokaždé jinak podle nastavení systému.
    private static func day(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
