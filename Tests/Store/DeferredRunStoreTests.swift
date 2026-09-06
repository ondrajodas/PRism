import Foundation
import Testing

@testable import PRism

/// Zápis a čtení odložených běhů (#519).
///
/// **Na tomhle stojí celé issue**: slib, který nepřežije restart, není slib — noc bez běžící
/// aplikace by nepustila nic a ráno by to vypadalo, že automat nefunguje. A protože restart je
/// v tomhle repu běžná věc (po každém mergi), není to okrajový případ.
@Suite("DeferredRunStore — odložené běhy (#519)")
struct DeferredRunStoreTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let pr = PRIdentifier("cli/cli#1")!
    private let other = PRIdentifier("cli/cli#2")!

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func run(
        _ pullRequest: PRIdentifier,
        deferredAt: Date? = nil,
        head: String = "aaaa1111"
    ) -> DeferredRun {
        let moment = deferredAt ?? start
        return DeferredRun(
            pullRequest: pullRequest,
            headSha: head,
            changedLines: 2790,
            threshold: 1500,
            deferredAt: moment,
            runAt: moment.addingTimeInterval(7 * 3600)
        )
    }

    /// **Základní tvrzení**: co se zapsalo, přečte si nová instance — tedy i ta po restartu.
    @Test("Odložený běh přežije restart")
    func survivesARestart() async {
        let clock = FakeTimeSource(start: start)
        await DeferredRunStore(layout: layout, time: clock).record(run(pr))

        let restarted = await DeferredRunStore(layout: layout, time: clock).load()

        #expect(restarted == [pr: run(pr)])
    }

    /// Rozhoduje se pokaždé nad dnešní hlavou a dnešními pravidly, takže dvě odpovědi naráz by
    /// znamenaly, že se běh pustí podle té, kterou uhodne kód.
    @Test("Opakovaný odklad ten předchozí přepíše")
    func recordingTwiceKeepsOneAnswer() async {
        let store = DeferredRunStore(layout: layout, time: FakeTimeSource(start: start))
        await store.record(run(pr, head: "aaaa1111"))
        await store.record(run(pr, head: "cccc3333"))

        let stored = await store.load()

        #expect(stored.count == 1)
        #expect(stored[pr]?.headSha == "cccc3333")
    }

    /// Idempotentní schválně: `Pustit teď` a tik umí dojít na tentýž PR naráz.
    @Test("Zrušení odkladu je idempotentní")
    func forgettingTwiceIsFine() async {
        let store = DeferredRunStore(layout: layout, time: FakeTimeSource(start: start))
        await store.record(run(pr))
        await store.record(run(other))

        await store.forget(pr)
        await store.forget(pr)

        #expect(await store.load().keys.map(\.self) == [other])
    }

    /// **Osiřelý zápis se pozná stářím, ne procesem** — odložený běh žádný nemá. Lhůta je jediné,
    /// co drží velikost souboru omezenou (#224: mez musí být vyjmenovaná), protože PR, který se
    /// zavřel, se rozhlídky po tiku už nikdy nedotkne.
    @Test("Zápis, který přežil lhůtu, se při dalším zápisu zahodí")
    func retentionDropsOrphans() async {
        let clock = FakeTimeSource(start: start)
        let store = DeferredRunStore(layout: layout, time: clock)
        await store.record(run(pr))

        clock.advance(by: DeferredRunStore.retention + 1)
        await store.record(run(other, deferredAt: clock.now))

        #expect(await store.load()[pr] == nil)
        #expect(await store.load()[other] != nil)
    }

    /// **Čtení obsah souboru neměnní** — jinak by lhůta zahodila zápis i tehdy, když se nic
    /// nezapisuje, a `load()` po startu by se choval jako úklid.
    @Test("Čtení lhůtu neuplatňuje")
    func readingDoesNotSweep() async {
        let clock = FakeTimeSource(start: start)
        await DeferredRunStore(layout: layout, time: clock).record(run(pr))

        let later = FakeTimeSource(start: start.addingTimeInterval(DeferredRunStore.retention + 1))
        let stored = await DeferredRunStore(layout: layout, time: later).load()

        #expect(stored[pr] != nil)
    }

    /// Bezpečná strana je „nic není odložené“: PR se tím dostane do automatu a nejhorší následek
    /// je běh ve tři odpoledne. Opačná volba by běh držela na základě souboru, kterému aplikace
    /// nerozumí — tedy slib, o kterém nikdo neví, že leží.
    @Test("Rozbitý soubor znamená prázdno, ne pád")
    func brokenFileReadsAsEmpty() async throws {
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try Data("{ tohle není JSON".utf8).write(to: layout.deferredFile)

        let stored = await DeferredRunStore(layout: layout, time: FakeTimeSource(start: start)).load()

        #expect(stored.isEmpty)
    }

    @Test("Chybějící soubor znamená prázdno")
    func missingFileReadsAsEmpty() async {
        #expect(await DeferredRunStore(layout: layout, time: FakeTimeSource(start: start)).load().isEmpty)
    }
}
