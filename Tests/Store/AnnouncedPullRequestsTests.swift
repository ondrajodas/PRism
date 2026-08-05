import Foundation
import Testing

@testable import PRism

/// Snímek ohlášených PR (#85).
///
/// Proti **skutečné** dočasné složce, jako `AutoRunLedger` — právě o to tady jde, že snímek
/// přežije restart. Fake filesystém by ověřoval sám sebe.
///
/// To hlavní není, co se ohlásí, ale co se **neohlásí**: první spuštění nesmí vyplivnout
/// všechna otevřená PR naráz, protože po takové lavině si notifikace každý vypne.
@Suite("AnnouncedPullRequests")
struct AnnouncedPullRequestsTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func store() -> AnnouncedPullRequests {
        AnnouncedPullRequests(layout: layout)
    }

    private func pr(_ text: String) -> PRIdentifier { PRIdentifier(text)! }

    @Test("První spuštění neohlásí nic")
    func staysQuietOnTheFirstRun() async {
        // Seznam je při startu prázdný, takže bez tohohle by každé otevřené PR vyšlo jako nové
        // a přišlo by jich deset naráz — po každém spuštění aplikace.
        let newcomers = await store().newcomers(in: [pr("cli/cli#1"), pr("cli/cli#2")])

        #expect(newcomers.isEmpty)
    }

    @Test("Po prvním spuštění se ohlásí jen to, co přibylo")
    func announcesOnlyWhatIsNew() async {
        let announced = store()
        _ = await announced.newcomers(in: [pr("cli/cli#1")])

        let newcomers = await announced.newcomers(in: [pr("cli/cli#1"), pr("cli/cli#2")])

        #expect(newcomers == [pr("cli/cli#2")])
    }

    @Test("Snímek přežije restart")
    func survivesARestart() async {
        // Tohle je ten důvod, proč je snímek na disku a ne v paměti.
        let first = store()
        _ = await first.newcomers(in: [pr("cli/cli#1")])
        await first.remember([pr("cli/cli#1")])

        // Nová instance nad tou samou složkou — jako po restartu aplikace.
        let newcomers = await store().newcomers(in: [pr("cli/cli#1"), pr("cli/cli#2")])

        #expect(newcomers == [pr("cli/cli#2")])
    }

    @Test("Zapsaný prázdný snímek není totéž jako první spuštění")
    func distinguishesAnEmptySnapshotFromAFirstRun() async {
        // Prázdná fronta je stav, ze kterého se **má** ohlašovat: „nic tam nebylo, teď tam
        // něco je“ je přesně ta informace, kvůli které issue existuje.
        let announced = store()
        _ = await announced.newcomers(in: [])

        let newcomers = await announced.newcomers(in: [pr("cli/cli#1")])

        #expect(newcomers == [pr("cli/cli#1")])
    }

    @Test("PR, které zmizelo a vrátilo se, se ohlásí znovu")
    func announcesAReturningPullRequestAgain() async {
        // Vypadává to ze snímku samo a je to tak zamýšlené: vrátilo se do fronty a je to
        // informace. Log ohlášených by na to musel mít vlastní lhůtu a vlastní úklid.
        let announced = store()
        _ = await announced.newcomers(in: [pr("cli/cli#1")])
        await announced.remember([pr("cli/cli#1")])
        _ = await announced.newcomers(in: [])
        await announced.remember([])

        let newcomers = await announced.newcomers(in: [pr("cli/cli#1")])

        #expect(newcomers == [pr("cli/cli#1")])
    }

    @Test("Snímek se nezvětšuje, drží velikost fronty")
    func doesNotGrow() async throws {
        // Snímek, ne rostoucí log — proto se nemusí nic uklízet.
        let announced = store()
        _ = await announced.newcomers(in: [pr("cli/cli#1"), pr("cli/cli#2")])
        await announced.remember([pr("cli/cli#1"), pr("cli/cli#2")])
        await announced.remember([pr("cli/cli#3")])

        let stored = try JSONDecoder().decode(
            [PRIdentifier].self,
            from: Data(contentsOf: layout.announcedFile)
        )

        #expect(stored == [pr("cli/cli#3")])
    }

    @Test("Pořadí kopíruje vstup, ne množinu")
    func keepsTheInputOrder() async {
        // Množina pořadí nemá, takže by notifikace mezi tiky poskakovaly. Vstup je řazený
        // `Policy.sorted`, tedy od naposledy změněného.
        let announced = store()
        _ = await announced.newcomers(in: [pr("cli/cli#1")])
        await announced.remember([pr("cli/cli#1")])

        let newcomers = await announced.newcomers(in: [
            pr("cli/cli#1"), pr("b/b#20"), pr("a/a#3"), pr("cli/cli#7"),
        ])

        #expect(newcomers == [pr("b/b#20"), pr("a/a#3"), pr("cli/cli#7")])
    }

    @Test("Nečitelný soubor se bere jako první spuštění")
    func treatsAnUnreadableFileAsAFirstRun() async throws {
        // Opačná volba než u nálezů, kde se rozbitý soubor hlásí: nejhorší následek je jedno
        // neohlášené kolo, kdežto lavina je to, čemu se tohle issue vyhýbá.
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try Data("{ tohle není JSON".utf8).write(to: layout.announcedFile)

        let newcomers = await store().newcomers(in: [pr("cli/cli#1")])

        #expect(newcomers.isEmpty)
    }

    @Test("Snímek na disku je stabilní a řazený číselně")
    func writesAStableSortedSnapshot() async throws {
        // Řazené pole, ne množina: soubor se nemá měnit bez důvodu. A `#10` musí jít **za**
        // `#2`, protože `PRIdentifier` řadí čísla číselně (viz pravidla v `CLAUDE.md`).
        await store().remember([pr("cli/cli#10"), pr("cli/cli#2")])

        let stored = try JSONDecoder().decode(
            [PRIdentifier].self,
            from: Data(contentsOf: layout.announcedFile)
        )

        #expect(stored == [pr("cli/cli#2"), pr("cli/cli#10")])
    }
}
