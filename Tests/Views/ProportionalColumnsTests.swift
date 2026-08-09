import Foundation
import Testing

@testable import PRism

/// Sloupce v poměru z návrhu (#181).
///
/// `Layout` se bez hostitelského okna vykreslit nedá, ale počítaná část ano — a je to zrovna ta,
/// kde se dá pokazit potichu: **mezery se musí odečíst dřív, než se dělí poměrem**, jinak sloupce
/// přetečou o mezeru a poslední se ořízne.
@Suite("Sloupce v poměru")
struct ProportionalColumnsTests {
    private let columns = ProportionalColumns(ratios: [1.45, 1], spacing: 16)

    @Test("Poměr sedí a mezery jsou odečtené")
    func dividesTheAvailableWidth() {
        let widths = columns.widths(in: 1000, count: 2)

        // Porovnává se s tolerancí: dělení poměrem je v plovoucí čárce, takže součet vyjde
        // o poslední bit jinak (`983.9999999999999`).
        let total: Double = widths.reduce(0, +)
        #expect(abs(total - 984) < 0.0001)
        #expect(abs(widths[0] / widths[1] - 1.45) < 0.0001)
    }

    /// Sloupec navíc, na který se v poměrech nedostalo, dostane `1` — návrh se tím nerozbije,
    /// jen se rozdělí rovným dílem. Spadnout na indexu by bylo horší.
    @Test("Sloupec bez poměru dostane rovný díl")
    func fallsBackToAnEqualShare() {
        let widths = columns.widths(in: 1000, count: 3)

        #expect(widths.count == 3)
        #expect(abs(widths[1] - widths[2]) < 0.0001)
    }

    /// Užší místo, než zaberou mezery, není důvod k zápornému rozměru — SwiftUI by na něm spadl.
    @Test("Šířka menší než mezery dá nuly, ne záporná čísla")
    func clampsToZero() {
        #expect(columns.widths(in: 8, count: 2) == [0, 0])
    }

    @Test("Bez sloupců není co počítat")
    func handlesNoColumns() {
        #expect(columns.widths(in: 1000, count: 0).isEmpty)
    }
}
