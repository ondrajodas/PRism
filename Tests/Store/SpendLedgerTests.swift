import Foundation
import Testing

@testable import PRism

/// Denní útrata za review (#148). Proti skutečné dočasné složce jako `AutoRunLedger` — jde
/// právě o to, že číslo přežije restart.
@Suite("SpendLedger")
struct SpendLedgerTests {
    private func ledger(_ workspace: TemporaryDirectory, time: FakeTimeSource) -> SpendLedger {
        SpendLedger(layout: CacheLayout(root: workspace.url), time: time)
    }

    @Test("Ceny se sčítají")
    func addsUpCosts() async throws {
        let ledger = ledger(try TemporaryDirectory(), time: FakeTimeSource())

        await ledger.record(RunUsage(cost: 0.25))
        let spend = await ledger.record(RunUsage(cost: 0.5))

        #expect(spend.cost == 0.75)
        #expect(spend.runs == 2)
        #expect(spend.unknown == 0)
    }

    /// Zabitá session peníze stála taky, jen o nich nevíme. Kdyby se počítala jako nula,
    /// tvářil by se součet jako úplný — tatáž past jako u `droppedFindings`.
    @Test("Běh bez ceny se počítá jako neznámý, ne jako nula")
    func countsRunsWithoutACost() async throws {
        let ledger = ledger(try TemporaryDirectory(), time: FakeTimeSource())

        let spend = await ledger.record(nil)

        #expect(spend.cost == 0)
        #expect(spend.runs == 0)
        #expect(spend.unknown == 1)
        #expect(!spend.isEmpty)
    }

    /// Číslo, které vynuluje restart, na otázku „co mě dneska stálo review“ neodpovídá.
    @Test("Útrata přežije restart")
    func survivesARestart() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()
        await ledger(workspace, time: time).record(RunUsage(cost: 0.25))

        #expect(await ledger(workspace, time: time).spentToday().cost == 0.25)
    }

    @Test("Nový den začíná od nuly")
    func resetsTheNextDay() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()
        await ledger(workspace, time: time).record(RunUsage(cost: 0.25))

        try await time.sleep(for: .seconds(60 * 60 * 24))

        let spend = await ledger(workspace, time: time).spentToday()
        #expect(spend.isEmpty)
        #expect(spend.cost == 0)
    }

    @Test("Bez jediného běhu není co ukazovat")
    func startsEmpty() async throws {
        #expect(await ledger(try TemporaryDirectory(), time: FakeTimeSource()).spentToday().isEmpty)
    }

    // MARK: - Historie pro graf (#181)

    @Test("Historie končí dneškem a má tolik dní, kolik se řeklo")
    func returnsAWindowEndingToday() async throws {
        let time = FakeTimeSource()
        let ledger = ledger(try TemporaryDirectory(), time: time)
        await ledger.record(RunUsage(cost: 0.25))

        let days = await ledger.recentDays(7)

        #expect(days.count == 7)
        #expect(days.map(\.spend.cost) == [0, 0, 0, 0, 0, 0, 0.25])
    }

    /// **Nejcennější test téhle sady.** Včerejšek se musí přesunout do historie, jinak by graf
    /// po půlnoci osiřel — a sloupec dneška by vypadal jako jediný den, kdy se kdy něco utratilo.
    @Test("Včerejšek se po půlnoci přesune do historie")
    func carriesYesterdayIntoTheHistory() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()
        await ledger(workspace, time: time).record(RunUsage(cost: 0.25))

        try await time.sleep(for: .seconds(60 * 60 * 24))
        let ledger = ledger(workspace, time: time)
        await ledger.record(RunUsage(cost: 0.5))

        let days = await ledger.recentDays(7)
        #expect(days.map(\.spend.cost) == [0, 0, 0, 0, 0, 0.25, 0.5])
    }

    /// Den bez útraty zůstává v řadě prázdný. Kdyby se vynechal, ukázal by graf dva sloupce
    /// vedle sebe jako dva po sobě jdoucí dny, i kdyby mezi nimi byl týden pauzy.
    @Test("Den bez útraty v řadě zůstane")
    func keepsEmptyDaysInPlace() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()
        await ledger(workspace, time: time).record(RunUsage(cost: 0.25))

        try await time.sleep(for: .seconds(60 * 60 * 24 * 3))
        let days = await ledger(workspace, time: time).recentDays(7)

        #expect(days.map(\.spend.cost) == [0, 0, 0, 0.25, 0, 0, 0])
    }

    /// Historie je okno, ne archiv: soubor, který by rostl donekonečna, by se každý den
    /// dekódoval delší a delší kvůli dnům, které se nikde nekreslí.
    @Test("Historie se ořezává na sedm dní")
    func trimsTheHistory() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()

        for _ in 0..<10 {
            await ledger(workspace, time: time).record(RunUsage(cost: 1))
            try await time.sleep(for: .seconds(60 * 60 * 24))
        }

        // Sedm dní zpátky se pamatuje, osmý už v souboru není — vyjde tedy jako prázdný,
        // stejně jako dnešek, ve kterém se nic nespustilo.
        let days = await ledger(workspace, time: time).recentDays(9)
        #expect(days.map(\.spend.cost) == [0, 1, 1, 1, 1, 1, 1, 1, 0])
    }

    /// Nečitelný soubor se bere jako prázdný den, jako u `AutoRunLedger`: hlásit chybu kvůli
    /// počitadlu by zabralo místo hláškám, které mají následek.
    @Test("Rozbitý soubor útratu neshodí")
    func survivesABrokenFile() async throws {
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try Data("{ tohle není JSON".utf8).write(to: layout.spendFile)

        let spend = await SpendLedger(layout: layout, time: FakeTimeSource()).record(RunUsage(cost: 0.25))

        #expect(spend.cost == 0.25)
    }
}
