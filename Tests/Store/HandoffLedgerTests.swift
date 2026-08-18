import Foundation
import Testing

@testable import PRism

/// Razítka předání na disku (#334) — `HandoffLedger`.
///
/// Proti **skutečné** složce, ne fake souborovému systému: to hlavní tvrzení je, že razítko
/// **přežije restart** (tedy druhou instanci nad tímtéž souborem), a to o disku nic nepředstírá.
@Suite("Razítka předání na disku (#334)")
struct HandoffLedgerTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 43)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func stamp(at seconds: TimeInterval, head: String? = "9c1de02") -> Handoff {
        Handoff(at: Date(timeIntervalSince1970: seconds), headSha: head, handed: ["f1", "t1"])
    }

    /// **Kvůli tomuhle celý ledger existuje**: „předáno v 14:20 proti 9c1de02“ musí přežít
    /// restart, protože prompt zaniká zavřením sheetu.
    @Test("Razítko přežije restart")
    func survivesARestart() async {
        let written = HandoffLedger(layout: layout, time: FakeTimeSource())
        await written.record(stamp(at: 1_000_000), for: pr)

        let read = await HandoffLedger(layout: layout, time: FakeTimeSource()).load()

        #expect(read[pr]?.at == Date(timeIntervalSince1970: 1_000_000))
        #expect(read[pr]?.headSha == "9c1de02")
        #expect(read[pr]?.handed == ["f1", "t1"])
    }

    /// Opakované předání téhož PR to předchozí přepíše — otázka je „co jsem poslal naposled“.
    @Test("Nové předání přepíše to předchozí")
    func replacesThePreviousStamp() async {
        let ledger = HandoffLedger(layout: layout, time: FakeTimeSource())
        await ledger.record(stamp(at: 1_000_000), for: pr)
        await ledger.record(
            Handoff(at: Date(timeIntervalSince1970: 1_000_500), headSha: "ff11223", handed: ["t9"]),
            for: pr
        )

        let read = await HandoffLedger(layout: layout, time: FakeTimeSource()).load()

        #expect(read.count == 1)
        #expect(read[pr]?.headSha == "ff11223")
        #expect(read[pr]?.handed == ["t9"])
    }

    /// Razítka jiných PR se zápisem nesmí ztratit — soubor je jeden pro všechny.
    @Test("Zápis nesmaže razítka ostatních PR")
    func keepsOtherPullRequests() async {
        let ledger = HandoffLedger(layout: layout, time: FakeTimeSource())
        await ledger.record(stamp(at: 1_000_000), for: pr)
        await ledger.record(stamp(at: 1_000_100), for: other)

        let read = await HandoffLedger(layout: layout, time: FakeTimeSource()).load()

        #expect(Set(read.keys) == [pr, other])
    }

    /// Po lhůtě se razítko zahodí — PR, který se zavřel, se do seznamu nevrátí, takže by jeho
    /// razítko leželo v cache napořád.
    @Test("Razítko starší než lhůta se zahodí")
    func prunesWhatOutlivedTheRetention() async {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let ledger = HandoffLedger(layout: layout, time: FakeTimeSource(start: old))
        await ledger.record(stamp(at: old.timeIntervalSince1970), for: pr)

        // O den víc než lhůta, a zápis jiného PR — úklid se dělá při zápisu.
        let later = FakeTimeSource(start: old.addingTimeInterval(HandoffLedger.retention + 86400))
        let pruning = HandoffLedger(layout: layout, time: later)
        await pruning.record(stamp(at: later.now.timeIntervalSince1970), for: other)

        let read = await HandoffLedger(layout: layout, time: later).load()

        #expect(Set(read.keys) == [other])
    }

    /// Rozbitý soubor znamená **prázdno, ne pád** — a je to bezpečný směr: prázdno vyjde jako
    /// „nepředáno“, takže odznak svítí a zadání se dá předat znovu.
    @Test("Rozbitý soubor se přečte jako prázdno")
    func readsBrokenFileAsEmpty() async throws {
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try Data("{ tohle není JSON".utf8).write(to: layout.handoffsFile)

        let read = await HandoffLedger(layout: layout, time: FakeTimeSource()).load()

        #expect(read.isEmpty)
    }

    /// Chybějící soubor je totéž — do prvního předání žádný neexistuje.
    @Test("Chybějící soubor se přečte jako prázdno")
    func readsMissingFileAsEmpty() async {
        let read = await HandoffLedger(layout: layout, time: FakeTimeSource()).load()

        #expect(read.isEmpty)
    }

    /// Identity se ukládají **řazené**, ať se soubor nemění bez důvodu — množina by je vypsala
    /// v nahodilém pořadí a atomický zápis by přepisoval tentýž obsah.
    @Test("Předané položky leží v souboru řazené")
    func writesHandedItemsSorted() async throws {
        let ledger = HandoffLedger(layout: layout, time: FakeTimeSource())
        await ledger.record(
            Handoff(at: Date(timeIntervalSince1970: 1_000_000), headSha: "9c1de02", handed: ["t9", "c2", "f1"]),
            for: pr
        )

        let text = try String(contentsOf: layout.handoffsFile, encoding: .utf8)
        let indexes = ["\"c2\"", "\"f1\"", "\"t9\""].compactMap { text.range(of: $0)?.lowerBound }

        #expect(indexes.count == 3)
        #expect(indexes == indexes.sorted())
    }
}
