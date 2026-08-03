import Foundation
import Testing

@testable import PRism

/// Denní rozpočet automatu. Proti skutečné dočasné složce, ne fake filesystému — jde
/// právě o to, že počitadlo přežije restart.
@Suite("AutoRunLedger")
struct AutoRunLedgerTests {
    private func ledger(_ workspace: TemporaryDirectory, time: FakeTimeSource) -> AutoRunLedger {
        AutoRunLedger(layout: CacheLayout(root: workspace.url), time: time)
    }

    @Test("Do limitu se sáhne, nad limit ne")
    func stopsAtTheLimit() async throws {
        let ledger = ledger(try TemporaryDirectory(), time: FakeTimeSource())

        #expect(await ledger.take(limit: 2))
        #expect(await ledger.take(limit: 2))
        #expect(!(await ledger.take(limit: 2)))
    }

    /// Pojistka, kterou obejde restart, není pojistka — a restart je zrovna to, co se po
    /// nečekaném utrácení udělá jako první.
    @Test("Počitadlo přežije restart")
    func survivesARestart() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()
        _ = await ledger(workspace, time: time).take(limit: 1)

        #expect(!(await ledger(workspace, time: time).take(limit: 1)))
    }

    @Test("Nový den začíná od nuly")
    func resetsTheNextDay() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()
        #expect(await ledger(workspace, time: time).take(limit: 1))

        try await time.sleep(for: .seconds(60 * 60 * 24))

        #expect(await ledger(workspace, time: time).take(limit: 1))
    }

    @Test("Zbývající počet klesá")
    func reportsWhatIsLeft() async throws {
        let ledger = ledger(try TemporaryDirectory(), time: FakeTimeSource())

        #expect(await ledger.remaining(limit: 3) == 3)
        _ = await ledger.take(limit: 3)
        #expect(await ledger.remaining(limit: 3) == 2)
    }

    /// Nula znamená vypnuto, ne „bez omezení“ — opačná volba by z překlepu udělala
    /// neomezené utrácení.
    @Test("Nulový limit nepustí nic")
    func aZeroLimitStopsEverything() async throws {
        let ledger = ledger(try TemporaryDirectory(), time: FakeTimeSource())

        #expect(!(await ledger.take(limit: 0)))
        #expect(await ledger.remaining(limit: 0) == 0)
    }

    /// Pojistka, kterou vypne rozbitý disk, není pojistka: kdyby se počítalo jen podle
    /// souboru, trvale selhávající zápis by limit zrušil úplně.
    @Test("Nezapisovatelný disk limit nezruší")
    func holdsTheLimitWithoutAWritableDisk() async throws {
        let workspace = try TemporaryDirectory()
        // Soubor tam, kde má být složka: `createDirectory` i zápis pod ním selžou.
        try Data().write(to: workspace.url.appending(path: "obsazeno"))
        let ledger = AutoRunLedger(
            layout: CacheLayout(root: workspace.url.appending(path: "obsazeno")),
            time: FakeTimeSource()
        )

        #expect(await ledger.take(limit: 1))
        #expect(!(await ledger.take(limit: 1)))
    }

    /// Nečitelné počitadlo automat neumlčí: nejhorší následek je pár běhů navíc, kdežto
    /// tiché zablokování se nedá vysvětlit.
    @Test("Rozbitý soubor se bere jako prázdný den")
    func treatsABrokenFileAsAFreshDay() async throws {
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)
        try FileManager.default.createDirectory(at: workspace.url, withIntermediateDirectories: true)
        try "{tohle není json".write(to: layout.autoRunsFile, atomically: true, encoding: .utf8)

        #expect(await ledger(workspace, time: FakeTimeSource()).take(limit: 1))
    }
}
