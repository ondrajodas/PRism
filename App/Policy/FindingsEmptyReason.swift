import Foundation

/// Proč není v nálezech nic vidět (#242).
///
/// **Prázdná obrazovka svádí ke čtení „čisto“**, a to je nejdražší záměna, jakou tohle okno umí:
/// schválený PR s neohlášenou chybou. V panelu o 300 bodech to řešila jedna věta, v tabu přes celé
/// okno je ta věta potřebnější, ne méně — proto se důvod počítá tady a ne dvěma `if`y ve view.
enum FindingsEmptyReason: Hashable, Sendable {
    /// Nálezy jsou, ale schoval je filtr reviewerů. **Nikdy se nesmí slít s `clean`.**
    case hiddenByReviewerFilter
    /// Review doběhlo a nic nenašlo.
    case clean
    /// Session spadla — `detail` je proč. Není to čisto, i když je tabulka prázdná stejně.
    case failed(String)
    /// Pracovní kopii se nepodařilo připravit; reviewer se tedy ani nespustil.
    case checkoutFailed(String)
    /// Review právě běží, nálezy zatím nedorazily.
    case running
    /// Na tomhle commitu se nic nespustilo, nebo se výsledek nepodařilo přečíst.
    case nothingRan
}

extension Policy {
    /// Proč je tabulka nálezů prázdná.
    ///
    /// - Parameter visible: nálezy po filtru reviewerů, tedy to, co by v tabulce bylo.
    /// - Parameter record: uložený záznam, nebo `nil`, když žádný není.
    static func findingsEmptyReason(
        visible: [Finding],
        record: ReviewRecord?,
        isRunning: Bool,
        categories: Set<String> = defaultBlockingCategories
    ) -> FindingsEmptyReason? {
        guard visible.isEmpty else { return nil }
        guard let record else { return isRunning ? .running : .nothingRan }
        // Schované nálezy nejsou žádné nálezy. Rozhoduje **záznam**, ne to, co zbylo po filtru:
        // právě rozdíl mezi těmi dvěma je ta informace, kterou tahle věta nese.
        guard record.findings.isEmpty else { return .hiddenByReviewerFilter }

        return switch reviewState(for: record, categories: categories) {
        case .clean: .clean
        case .failed(let detail): .failed(detail)
        case .checkoutFailed(let detail): .checkoutFailed(detail)
        // Běžící review má vlastní věta přednost před `nothingRan`: „nespustilo se nic“ nad
        // rozjetým během je nepravda.
        default: isRunning ? .running : .nothingRan
        }
    }
}
