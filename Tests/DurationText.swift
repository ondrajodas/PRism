import Foundation

extension Duration {
    /// Milisekundy na tři desetiny — `Duration` se jinak vypisuje v attosekundách.
    ///
    /// Bydlí to tady, ne u jednoho měření: od #184 vypisují čas dvě měřicí suity (layout diffu
    /// a hledání v paletě) a dvě kopie téhož formátování by znamenaly, že se čísla v logu
    /// najednou porovnávají v různých jednotkách.
    var milliseconds: String {
        let value = Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.3f ms", value)
    }
}
