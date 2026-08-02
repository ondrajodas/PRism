import Foundation

/// Co diff umí s rozbalováním kontextu. Jeden parametr místo tří closures, které patří
/// k sobě.
struct DiffExpansionActions {
    /// Co je u souboru rozbalené a jestli se jeho obsah zrovna načítá.
    let state: (FileDiff) -> FileExpansion
    let reveal: (FileDiff, ClosedRange<Int>) -> Void
    /// Sbalení zpátky na samotný diff. `nil`, když není co sbalit — tím se rovnou
    /// rozhoduje, jestli se tlačítko vůbec ukáže.
    let collapse: (() -> Void)?
}
