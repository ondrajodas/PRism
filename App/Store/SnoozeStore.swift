import Foundation

/// Odložená PR (#512) — jeden `snoozed.json` v kořeni cache.
///
/// **Jeden soubor, ne soubor na PR**, jako `HandoffLedger`: klíč na PR by se nedal projít, takže
/// by v cache zůstávalo každé odložení navždycky a blok `Odložené` by se nedal složit bez čtení
/// celé složky.
///
/// **V cache, ne v předvolbách.** Je to stav o pull requestech, tedy o materiálu, který v cache
/// leží celý — a hlavně: cache je to jediné, co dělí paralelní okna od sebe (#228), takže si slot
/// `a` a hlavní instance odložení nepřepisují.
///
/// Aktor ze stejného důvodu jako `HandoffLedger`: čtení, změna a zápis jsou tři kroky nad jedním
/// souborem a rozhlídka po tiku umí přijít doprostřed ručního odložení.
actor SnoozeStore {
    /// Jak dlouho odložení leží v cache, když se na PR nic nestane.
    ///
    /// Odložený PR, který se zavřel, ze seznamu vypadne — rozhlídka se ho pak nikdy nezeptá
    /// a odložení by v souboru zůstalo napořád. Devadesát dní je tatáž hodnota jako u razítek
    /// předání (#334) a ze stejného důvodu: nejde o místo, ale o to, aby slovník nerostl bez
    /// omezení (#224 — mez musí být vyjmenovaná).
    ///
    /// **Je to úklid, ne vypršení.** Odložení, které lhůtu přežije, se z fronty neodstraní tím,
    /// že by „skončilo“; prostě zmizí i s PR, kterého se týkalo. Rozhodnutí o návratu dělá jedině
    /// `Policy.snoozeExpired`.
    static let retention: TimeInterval = 90 * 24 * 60 * 60

    private let layout: CacheLayout
    private let time: any TimeSource
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Odložení, se kterými se pracuje. `nil` = ještě se nečetla z disku.
    private var cached: [PRIdentifier: Snooze]?

    init(layout: CacheLayout = .applicationSupport, time: any TimeSource = SystemTimeSource()) {
        self.layout = layout
        self.time = time
        // ISO 8601 a odsazení jako u razítek předání: je to osobní nástroj a data se čtou i očima.
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Všechna odložení. Čte se **jednou při startu**, a musí to být **před prvním tikem**: fronta,
    /// deska, odznak i automat se odložených ptají při každém překreslení, resp. tiku — a tik,
    /// který proběhne dřív, by na odložený PR pustil review, které si nikdo neobjednal.
    func load() -> [PRIdentifier: Snooze] { read() }

    /// Odloží PR a při té příležitosti zahodí, co se přežilo.
    ///
    /// Opakované odložení téhož PR to předchozí **přepíše**: otázka je „kdy ho chci vidět“, a dvě
    /// odpovědi naráz by znamenaly, že se PR vrátí podle té, kterou uhodne kód.
    func record(_ snooze: Snooze) {
        var snoozes = surviving()
        snoozes[snooze.pullRequest] = snooze
        write(snoozes)
    }

    /// Vrátí PR z odložení. Idempotentní — chybějící záznam není chyba, protože `Vrátit teď`
    /// a rozhlídka po tiku umí dojít na tentýž PR naráz.
    func forget(_ pullRequest: PRIdentifier) {
        var snoozes = read()
        guard snoozes.removeValue(forKey: pullRequest) != nil else { return }
        write(snoozes)
    }

    /// Vrátí víc PR naráz — **jeden zápis, ne jeden na PR**.
    ///
    /// Rozhlídka po tiku umí vrátit tři PR v jednom průchodu a `record`/`forget` sahá na disk;
    /// zápis v cyklu by ten soubor uložil třikrát. Prázdné pole se nedotkne ničeho.
    func forget(_ pullRequests: [PRIdentifier]) {
        guard !pullRequests.isEmpty else { return }
        var snoozes = read()
        var changed = false
        for pullRequest in pullRequests where snoozes.removeValue(forKey: pullRequest) != nil {
            changed = true
        }
        guard changed else { return }
        write(snoozes)
    }

    /// Zapíše odložení s doplněným měřidlem (`Policy.snoozeBaseline`) — **jeden zápis na dávku**,
    /// ze stejného důvodu jako u `forget(_:)`.
    ///
    /// **Zapisuje se jedině to, co v souboru pořád je.** Mezi rozhlídkou a zápisem umí přijít
    /// `Vrátit teď`, a doplnit základ k odložení, které mezitím skončilo, by ho vzkřísilo.
    func update(_ snoozes: [Snooze]) {
        guard !snoozes.isEmpty else { return }
        var stored = read()
        var changed = false
        for snooze in snoozes where stored[snooze.pullRequest] != nil {
            stored[snooze.pullRequest] = snooze
            changed = true
        }
        guard changed else { return }
        write(stored)
    }

    /// Odložení bez těch, která přežila lhůtu. Volá se **jen při zápisu**, jako u razítek
    /// předání — čtení nemá měnit obsah souboru.
    private func surviving() -> [PRIdentifier: Snooze] {
        let now = time.now
        return read().filter { now.timeIntervalSince($0.value.since) < Self.retention }
    }

    /// Rozbitý nebo chybějící soubor znamená **prázdno**, ne pád.
    ///
    /// Je to bezpečný směr, a u téhle věci to platí obzvlášť: prázdno vyjde jako „nic není
    /// odložené“, takže se PR objeví ve frontě. Opačná volba by je nechala schované na základě
    /// souboru, kterému aplikace nerozumí — tedy práci, o které nikdo neví, že leží.
    private func read() -> [PRIdentifier: Snooze] {
        if let cached { return cached }
        guard let data = try? Data(contentsOf: layout.snoozedFile),
              let stored = try? decoder.decode([PRIdentifier: Snooze].self, from: data)
        else {
            cached = [:]
            return [:]
        }
        cached = stored
        return stored
    }

    /// Zapisuje **nejdřív do paměti, pak na disk**, jako `HandoffLedger`.
    ///
    /// Selhání zápisu se spolkne. Za běhu platí paměť; po restartu se odložení nenajde, takže se
    /// PR vrátí do fronty — tedy stav před #512, ne schovaná práce.
    private func write(_ snoozes: [PRIdentifier: Snooze]) {
        cached = snoozes
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try? encoder.encode(snoozes).write(to: layout.snoozedFile, options: .atomic)
    }
}
