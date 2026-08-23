import Foundation
import Testing

@testable import PRism

/// Záznam dění na disku (#414) — `ActivityLog`.
///
/// Proti **skutečné** složce, ne fake souborovému systému: to hlavní tvrzení je, že se záznam
/// **nezahodí restartem**, a to o disku nic nepředstírá. Je to zároveň jediný rozdíl proti zvonku
/// ve stavovém řádku (`DeliveredNotification`), který je v paměti schválně (#138).
@Suite("Záznam dění na disku (#414)")
struct ActivityLogTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "keboola", name: "vault"), number: 85)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func event(_ id: String, at seconds: TimeInterval) -> ActivityEvent {
        ActivityEvent(
            id: id,
            kind: .findings,
            pullRequest: pr,
            at: Date(timeIntervalSince1970: seconds),
            headline: "3 nálezy · 1 blokuje",
            detail: "correctness: chybí kontrola",
            wasAnnounced: false,
            head: nil
        )
    }

    /// **Kvůli tomuhle celý záznam existuje.** Notifikace proletí a nikde nezůstane; dění je
    /// opačná otázka, takže musí přežít restart.
    @Test("Záznam přežije restart")
    func survivesARestart() async {
        await ActivityLog(layout: layout).record([event("a", at: 1_000_000)])

        let read = await ActivityLog(layout: layout).load().events

        #expect(read.count == 1)
        #expect(read[0].id == "a")
        #expect(read[0].at == Date(timeIntervalSince1970: 1_000_000))
        #expect(read[0].headline == "3 nálezy · 1 blokuje")
        #expect(read[0].detail == "correctness: chybí kontrola")
        #expect(read[0].wasAnnounced == false)
    }

    /// Strop je **na položky, ne na dny** (`Policy.activityLimit`), a při jeho překročení odcházejí
    /// nejstarší — dění je o tom, co jsem prošvihl, a to nejstarší jsem prošvihl nejdřív.
    @Test("Strop odřízne nejstarší položky")
    func keepsOnlyTheNewestOverTheLimit() async {
        let log = ActivityLog(layout: layout, limit: 3)

        for index in 1...6 {
            await log.record([event("e\(index)", at: TimeInterval(index) * 100)])
        }

        let read = await ActivityLog(layout: layout, limit: 3).load().events
        #expect(read.map(\.id) == ["e6", "e5", "e4"])
    }

    /// Soubor mohl vzniknout s jiným stropem (změnila se konstanta), takže se stropuje **i po
    /// přečtení** — jinak by v paměti bylo víc, než kolik se zapisuje.
    @Test("Čtení srovná pořadí i strop")
    func ordersAndTrimsOnRead() async {
        await ActivityLog(layout: layout, limit: 10).record([
            event("stary", at: 100),
            event("novy", at: 300),
            event("prostredni", at: 200)
        ])

        let read = await ActivityLog(layout: layout, limit: 2).load().events

        #expect(read.map(\.id) == ["novy", "prostredni"])
    }

    /// Chybějící soubor znamená **prázdno, ne pád**: prázdná sekce se pozná (má vlastní prázdný
    /// stav) a plní se dál.
    @Test("Chybějící soubor dá prázdný záznam, ne poruchu")
    func readsNothingWithoutAFile() async {
        let stored = await ActivityLog(layout: layout).load()

        #expect(stored.events.isEmpty)
        // První spuštění **není** porucha: prázdno je tady normální stav.
        #expect(!stored.isUnreadable)
    }

    /// Rozbitý soubor dá taky prázdno — ale **musí se poznat**: prázdný záznam a ztracená historie
    /// dají obojí prázdný seznam a klidné „nic se nestalo“ by nad tím druhým lhalo.
    @Test("Rozbitý soubor se pozná od prázdného")
    func tellsABrokenFileFromAnEmptyOne() async throws {
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try Data("{ tohle není záznam".utf8).write(to: layout.activityFile)

        let stored = await ActivityLog(layout: layout).load()

        #expect(stored.events.isEmpty)
        #expect(stored.isUnreadable)
    }

    /// Prázdný zápis soubor **nezakládá** ani nepřepisuje: tik bez novinek se děje pořád a psát
    /// při každém z nich na disk je práce za nic.
    @Test("Prázdný zápis se souboru nedotkne")
    func writesNothingForNoEvents() async {
        let log = ActivityLog(layout: layout)

        let result = await log.record([])

        #expect(result.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: layout.activityFile.path))
    }

    /// Vrací se **celý** záznam, ne jen to, co se přidalo — volající si ho položí do paměti
    /// a nepočítá strop podruhé.
    @Test("Zápis vrátí celý záznam")
    func returnsTheWholeLog() async {
        let log = ActivityLog(layout: layout)

        await log.record([event("a", at: 100)])
        let result = await log.record([event("b", at: 200)])

        #expect(result.map(\.id) == ["b", "a"])
    }
}
