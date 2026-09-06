import Foundation

/// Běhy odložené do tichých hodin (#519) — jeden `deferred.json` v kořeni cache.
///
/// **Na disku, ne v paměti, a je to celý smysl toho odkladu.** Automat slíbí, že se velké PR pustí
/// ve 22:00; kdyby ten slib žil jen v paměti, noc bez běžící aplikace by nepustila nic a ráno by to
/// vypadalo, že automat nefunguje. Restart je přitom v tomhle repu běžná věc — po každém mergi.
///
/// **Jeden soubor, ne soubor na PR**, jako `SnoozeStore` a `HandoffLedger`: klíč na PR by se nedal
/// projít, takže by v cache zůstával každý odklad navždycky a lhůta by neměla co uklidit.
///
/// **V cache** (tvrdá podmínka č. 3), a je to i to jediné, co dělí paralelní okna od sebe (#228) —
/// slot `a` a hlavní instance si odklady nepřepisují.
///
/// Aktor ze stejného důvodu jako `SnoozeStore`: čtení, změna a zápis jsou tři kroky nad jedním
/// souborem, a tik umí přijít doprostřed toho, jak se běh odkládá.
actor DeferredRunStore {
    /// Jak dlouho odklad leží v cache, když ho nikdo nevyzvedne.
    ///
    /// **Osiřelý zápis se pozná stářím, ne existencí procesu** — a je to rozdíl proti
    /// `RunningSessions` (#351), kde se osiřelost pozná z `(pid, startedAt)`. Odložený běh žádný
    /// proces nemá: je to slib, ne běh. Osiří tím, že PR, kterého se týkal, ze seznamu zmizí
    /// (zavřel se, mergnul se, přestal se sledovat) — a **vystřelit už nemůže**, protože
    /// `Policy.deferralsToRelease` bere seznam z tiku, ne obsah tohohle souboru. Zbývá ho tedy
    /// jenom uklidit, aby slovník nerostl bez omezení (#224 — mez musí být vyjmenovaná).
    ///
    /// **Sedm dní, ne devadesát jako u odložení PR.** Odklad je slib na jednu noc; co po týdnu
    /// nikdo nevyzvedl, se nevyzvedne. Delší lhůta by jen držela záznamy, které nemá kdo přečíst.
    static let retention: TimeInterval = 7 * 24 * 60 * 60

    private let layout: CacheLayout
    private let time: any TimeSource
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Odklady, se kterými se pracuje. `nil` = ještě se nečetly z disku.
    private var cached: [PRIdentifier: DeferredRun]?

    init(layout: CacheLayout = .applicationSupport, time: any TimeSource = SystemTimeSource()) {
        self.layout = layout
        self.time = time
        // ISO 8601 a odsazení jako u odložených PR: je to osobní nástroj a data se čtou i očima.
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Všechny odklady. Čte se **jednou při startu**, a musí to být **před prvním tikem**: tik,
    /// který proběhne dřív, by odložený PR poslal do automatu znovu a zaplatil za `gh pr view`,
    /// jehož odpověď je už na disku.
    func load() -> [PRIdentifier: DeferredRun] { read() }

    /// Odloží běh a při té příležitosti zahodí, co přežilo lhůtu.
    ///
    /// Opakovaný odklad téhož PR ten předchozí **přepíše**: rozhoduje se pokaždé nad dnešní hlavou
    /// a dnešními pravidly, takže dvě odpovědi naráz by znamenaly, že se běh pustí podle té, kterou
    /// uhodne kód.
    func record(_ run: DeferredRun) {
        var runs = surviving()
        runs[run.pullRequest] = run
        write(runs)
    }

    /// Zruší odklad. Idempotentní — `Pustit teď` a tik umí dojít na tentýž PR naráz, a běh, který
    /// se rozjel, ruší odklad taky.
    func forget(_ pullRequest: PRIdentifier) {
        var runs = read()
        guard runs.removeValue(forKey: pullRequest) != nil else { return }
        write(runs)
    }

    /// Odklady bez těch, které přežily lhůtu. Volá se **jen při zápisu**, jako u odložených PR —
    /// čtení nemá měnit obsah souboru.
    private func surviving() -> [PRIdentifier: DeferredRun] {
        let now = time.now
        return read().filter { now.timeIntervalSince($0.value.deferredAt) < Self.retention }
    }

    /// Rozbitý nebo chybějící soubor znamená **prázdno**, ne pád.
    ///
    /// Bezpečná strana je tady „nic není odložené“: PR se tím dostane do automatu a nejhorší
    /// následek je běh ve tři odpoledne. Opačná volba by běh držela na základě souboru, kterému
    /// aplikace nerozumí — tedy slib, o kterém nikdo neví, že leží.
    private func read() -> [PRIdentifier: DeferredRun] {
        if let cached { return cached }
        guard let data = try? Data(contentsOf: layout.deferredFile),
              let stored = try? decoder.decode([PRIdentifier: DeferredRun].self, from: data)
        else {
            cached = [:]
            return [:]
        }
        cached = stored
        return stored
    }

    /// Zapisuje **nejdřív do paměti, pak na disk**, jako `SnoozeStore`.
    ///
    /// Selhání zápisu se spolkne. Za běhu platí paměť; po restartu se odklad nenajde, takže se PR
    /// dostane do automatu — tedy stav před #519, ne ztracený běh.
    private func write(_ runs: [PRIdentifier: DeferredRun]) {
        cached = runs
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try? encoder.encode(runs).write(to: layout.deferredFile, options: .atomic)
    }
}
