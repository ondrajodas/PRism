import Foundation
import Testing

@testable import PRism

/// Poslední brief na disku (#516).
///
/// **Je to pojistka proti utrácení, ne pohodlí.** Režim `Při prvním tiku dne` se ptá, jestli je
/// dnešek shrnutý — a kdyby se den držel jen v paměti, spustil by se brief po každém restartu
/// znovu. Tvrzení, které se rozbije potichu: nová instance store musí **vidět** brief z minula.
@Suite("BriefStore — brief přežije restart")
struct BriefStoreTests {
    private let brief = Brief(
        lines: [
            BriefLine(part: .added, text: "Přes den přišly dva PR do fronty."),
            BriefLine(part: .burning, text: "Sandbox #4 blokuje."),
        ],
        writtenAt: Date(timeIntervalSince1970: 1_700_000_000),
        cost: 0.03
    )

    @Test("Uložený brief přečte druhá instance")
    func survivesRestart() async throws {
        let directory = try TemporaryDirectory()
        let layout = CacheLayout(root: directory.url)

        await BriefStore(layout: layout).save(brief)

        // **Druhá instance**, ne tatáž: kdyby se brief držel jen v paměti, prošlo by to i tak.
        let loaded = await BriefStore(layout: layout).load()
        #expect(loaded == brief)
    }

    /// Prázdná cache znamená „ještě se neshrnovalo“, ne chybu — a nečitelný soubor taky:
    /// nejhorší následek je jeden brief navíc, kdežto hlášená porucha kvůli odstavci textu je hluk.
    @Test("Prázdná i rozbitá cache znamená, že brief není")
    func missingOrBrokenMeansNone() async throws {
        let directory = try TemporaryDirectory()
        let layout = CacheLayout(root: directory.url)
        #expect(await BriefStore(layout: layout).load() == nil)

        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try Data("{ tohle není brief".utf8).write(to: layout.briefFile)
        #expect(await BriefStore(layout: layout).load() == nil)
    }
}
