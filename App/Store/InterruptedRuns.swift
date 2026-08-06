import Foundation

/// Běhy, které začaly a nevíme, jestli doběhly (#97).
///
/// Značka se zapíše, jakmile ze session dorazí `session_id`, a **maže se uložením výsledku**.
/// Co v souboru po startu zbylo, jsou běhy, které aplikaci nepřežily — pád, `kill`, restart
/// Macu. Potvrzovací dialog při zavření (#94) tuhle díru nezacpe: ten pokrývá jen to, co
/// uživatel způsobí svým jednáním.
///
/// **Vlastní soubor, ne příznak v `ReviewStore`u.** Nabízelo se to (jedno místo na stav běhu),
/// ale `StoredReviewRun` je typ **výsledku**: má `outcome` i `finishedAt`, a rozdělaný běh
/// nemá ani jedno. Kdyby se tam vešel, musel by ho každý čtenář záznamů (stav řádku, návrh
/// verdiktu, chipy) umět odlišit — a zapomenuté rozlišení znamená „reviewer nic nenašel“ nad
/// během, který teprve běží. Tady je to jeden malý soubor, který čte jediný kód.
///
/// Aktor ze stejného důvodu jako `AnnouncedPullRequests`: čtení, změna a zápis jsou tři kroky
/// nad jedním souborem a značky se zapisují ze souběžných běhů.
actor InterruptedRuns {
    private let layout: CacheLayout
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Značky, se kterými se pracuje. `nil` = ještě se nečetly z disku.
    private var cached: [InterruptedRun]?

    init(layout: CacheLayout = .applicationSupport) {
        self.layout = layout
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// Zapamatuje si, že běh začal. Opakované volání pro tentýž klíč přepíše — session se
    /// při opakovaném review mění a stará by ukazovala na transcript minulého běhu.
    func remember(_ run: InterruptedRun) {
        var runs = load().filter { $0.key != run.key }
        runs.append(run)
        write(runs)
    }

    /// Běh doběhl a je uložený, takže se o něj už nemusí nikdo starat.
    func forget(_ key: ReviewRunKey) {
        let runs = load()
        let kept = runs.filter { $0.key != key }
        guard kept.count != runs.count else { return }
        write(kept)
    }

    /// Co zbylo — tedy běhy, které aplikaci nepřežily.
    func pending() -> [InterruptedRun] { load() }

    private func load() -> [InterruptedRun] {
        if let cached { return cached }
        guard let data = try? Data(contentsOf: layout.interruptedFile),
              let stored = try? decoder.decode([InterruptedRun].self, from: data)
        else {
            // Nečitelný soubor se bere jako prázdný. Nejhorší následek je jedno nedotažené
            // review, kdežto vyhozená chyba by položila start aplikace — a tohle je záchranná
            // síť, ne cesta, na které něco stojí.
            cached = []
            return []
        }
        cached = stored
        return stored
    }

    /// Zapisuje **nejdřív do paměti, pak na disk**, jako `AutoRunLedger`.
    ///
    /// Selhání zápisu se spolkne. Za běhu platí paměť; po restartu se značka nenajde, takže se
    /// nálezy nedotáhnou — což je přesně ten stav, který byl před #97, a ne nový problém.
    private func write(_ runs: [InterruptedRun]) {
        cached = runs
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try? encoder.encode(runs).write(to: layout.interruptedFile, options: .atomic)
    }
}
