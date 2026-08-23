import Foundation

/// Záznam dění (#414) — co se na pull requestech stalo, se stropem **200 položek**.
///
/// **Na disku, na rozdíl od zvonku ve stavovém řádku.** `DeliveredNotification` je v paměti
/// schválně (#138): odpovídá na „funguje mi to teď“ a čas z minulého spuštění je k té otázce
/// zavádějící. Dění je otázka opačná („co se stalo“), takže se musí přežít restart — jako
/// `AnnouncedPullRequests` nebo `VisitLedger`.
///
/// **Strop je na položky, ne na dny** (`Policy.activityLimit`). Týdenní okno jako u `SpendLedger`
/// by usekávalo přesně tu dovolenou, kvůli které se sem chodí; a mez **musí být vyjmenovaná**,
/// protože cache bez ní je únik paměti s odkladem (#224). Vyprazdňuje se jedině tím stropem —
/// nic jiného ten soubor nemaže, ani úklid po PR, které vypadlo ze seznamu: dění je záznam
/// **toho, co se stalo**, a PR, který se mezitím zavřel, o tom nemění nic.
///
/// **Jeden soubor, ne soubor na PR**, a aktor ze stejného důvodu jako `HandoffLedger`: čtení,
/// vložení a zápis jsou tři kroky nad jedním souborem a doběhnout naráz umí klidně tři reviewery.
actor ActivityLog {
    /// Co bylo na disku — a jestli tam bylo něco, co se nepřečetlo.
    ///
    /// **Dvě věci, ne jedna.** Prázdný záznam a rozbitý soubor dají obojí prázdný seznam, ale
    /// znamenají něco úplně jiného: „nic se nestalo“ proti „historie je ztracená“. Bez toho
    /// příznaku by nad rozbitým souborem stálo v okně klidné *Za poslední dny se nic nestalo* —
    /// tedy text, který tvrdí víc, než data unesou.
    struct Stored: Sendable, Equatable {
        let events: [ActivityEvent]
        /// Soubor byl, ale nedekódoval se.
        let isUnreadable: Bool
    }

    private let layout: CacheLayout
    private let limit: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Záznam, se kterým se pracuje. `nil` = ještě se nečetl z disku.
    private var cached: [ActivityEvent]?
    /// Nepodařilo se přečíst soubor, který na disku byl? Drží se, dokud aplikace běží — je to
    /// tvrzení o tom, co se ztratilo, ne o tom, co je v souboru teď.
    private var unreadable = false

    init(layout: CacheLayout = .applicationSupport, limit: Int = Policy.activityLimit) {
        self.layout = layout
        self.limit = limit
        // ISO 8601 a odsazení jako u razítek předání: je to osobní nástroj a data se čtou i očima.
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Celý záznam, od nejnovějšího. Čte se **jednou při startu** — sekce i odznak v railu se pak
    /// ptají paměti (`AppStore.activityEvents`), protože je SwiftUI čte při každém překreslení okna.
    func load() -> Stored { read() }

    /// Zapíše položky a vrátí **celý** záznam, jak po nich vypadá.
    ///
    /// Vrací se celý schválně: volající si ho položí do paměti, takže vložení, odstranění duplicit
    /// ani strop nemusí počítat podruhé. Dvě implementace téhož by se rozešly — a rozejít se
    /// v tomhle znamená, že na obrazovce je jiný záznam než na disku.
    @discardableResult
    func record(_ events: [ActivityEvent]) -> [ActivityEvent] {
        guard !events.isEmpty else { return read().events }
        let updated = Policy.activityLog(read().events, adding: events, limit: limit)
        write(updated)
        return updated
    }

    /// Rozbitý nebo chybějící soubor znamená **prázdno**, ne pád — ale ne totéž prázdno.
    ///
    /// Prázdno je bezpečný směr: vymyšlený obsah by tvrdil, že se něco stalo, a nic zadaného
    /// uživatelem tu není. **Rozbitý soubor se ale musí poznat**, protože klidné „nic se nestalo“
    /// by nad ztracenou historií lhalo; nese to `Stored.isUnreadable` a v okně z toho je vlastní
    /// prázdný stav.
    private func read() -> Stored {
        if let cached { return Stored(events: cached, isUnreadable: unreadable) }
        // Chybějící soubor je **normální stav** (první spuštění), a proto se od nečitelného musí
        // odlišit dřív než dekódováním: `Data(contentsOf:)` vyhodí u obojího.
        guard let data = try? Data(contentsOf: layout.activityFile) else {
            cached = []
            return Stored(events: [], isUnreadable: false)
        }
        guard let stored = try? decoder.decode([ActivityEvent].self, from: data) else {
            cached = []
            unreadable = true
            return Stored(events: [], isUnreadable: true)
        }
        // Řadí a stropuje se i po přečtení: soubor mohl vzniknout s jiným stropem (změněná
        // konstanta) a pořadí je to, na čem stojí značka poslední návštěvy.
        let ordered = Policy.activityLog([], adding: stored, limit: limit)
        cached = ordered
        return Stored(events: ordered, isUnreadable: false)
    }

    /// Zapisuje **nejdřív do paměti, pak na disk**, jako `HandoffLedger`.
    ///
    /// Selhání zápisu se spolkne. Za běhu platí paměť, po restartu se záznam nenajde — tedy stav
    /// před #414, ne nový problém; a hlásit to ve stavovém řádku by zabralo místo hláškám, po
    /// kterých má následovat akce.
    private func write(_ events: [ActivityEvent]) {
        cached = events
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try? encoder.encode(events).write(to: layout.activityFile, options: .atomic)
    }
}
