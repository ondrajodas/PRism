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
