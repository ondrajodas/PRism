import Foundation
import Testing

@testable import PRism

/// Měření, ne test (#184). Nic netvrdí — říká, kolik stojí jedno hledání v paletě.
///
/// Existuje kvůli jednomu rozhodnutí: katalog se skládá **při každém stisku klávesy**, ne jednou
/// při otevření palety. Snímek by za pár sekund ukazoval nálezy z review, které mezitím doběhlo —
/// ale platí se za to průchodem celého katalogu na písmeno, a hledání je `range(of:options:)`
/// s diakritikou, tedy ne úplně zdarma. Číslo je z toho důvodu měřené, ne odhadnuté.
///
/// Časy se **netvrdí** `#expect`em: na jiném stroji vyjdou jinak. Pouští se ručně,
/// `TEST_RUNNER_PRISM_MEASURE=1`, ze stejného důvodu jako `DiffPerformanceMeasurement`.
@Suite(
    "Měření hledání v paletě (#184)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct CommandPaletteMeasurement {
    private func catalog(of count: Int) -> [CommandPalette.Item] {
        (1...count).map { index in
            CommandPalette.Item(
                id: "finding:\(index)",
                group: .findings,
                title: "Chybějící kontrola návratové hodnoty v klientovi číslo \(index)",
                subtitle: "vault#85 · SecretClient\(index).php:81",
                mark: .finding,
                keywords: ["src/Vault/Secret/Client\(index).php", "code-review", "keboola/vault"],
                target: .action(.refresh)
            )
        }
    }

    @Test("Cena jednoho hledání podle velikosti katalogu")
    func searchCost() {
        // 2000 řádků je řádově víc, než kolik jich v okně vznikne: dvacet PR po padesáti
        // nálezech. Když je i tenhle případ pod milisekundou, snímek katalogu není potřeba.
        for count in [200, 2000] {
            let items = catalog(of: count)
            let clock = ContinuousClock()
            // Zahřátí — první průchod platí za líné inicializace v Foundation.
            _ = Policy.paletteResults(of: items, query: "secret")
            let elapsed = clock.measure {
                for _ in 0..<10 { _ = Policy.paletteResults(of: items, query: "klient hodnoty") }
            }
            print("MĚŘENÍ hledání, \(count) řádků: \((elapsed / 10).milliseconds) na stisk klávesy")
        }
    }
}
