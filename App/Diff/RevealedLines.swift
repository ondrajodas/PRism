import Foundation

/// Které skryté řádky souboru už uživatel rozbalil. Čísla jsou v **novém** souboru.
///
/// Rozsahy se drží sloučené a seřazené: dvě kliknutí na sousední úsek jinak dají dva
/// záznamy a řádek na jejich hranici se vykreslí dvakrát.
struct RevealedLines: Equatable, Sendable {
    /// Souvislý kus skrytého úseku — buď je vidět, nebo ne.
    enum Part: Equatable, Sendable {
        case hidden(ClosedRange<Int>)
        case shown(ClosedRange<Int>)
    }

    private(set) var ranges: [ClosedRange<Int>] = []

    mutating func reveal(_ range: ClosedRange<Int>) {
        var merged = range
        var result: [ClosedRange<Int>] = []

        for existing in ranges {
            if touches(existing, merged) {
                merged = min(existing.lowerBound, merged.lowerBound)...max(existing.upperBound, merged.upperBound)
            } else {
                result.append(existing)
            }
        }

        result.append(merged)
        ranges = result.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Rozseká skrytý úsek na kusy podle toho, co už je vidět.
    func split(_ gap: ClosedRange<Int>) -> [Part] {
        var parts: [Part] = []
        var line = gap.lowerBound

        for shown in ranges.compactMap({ intersection(of: $0, and: gap) }) {
            if line < shown.lowerBound { parts.append(.hidden(line...(shown.lowerBound - 1))) }
            parts.append(.shown(shown))
            line = shown.upperBound + 1
        }

        if line <= gap.upperBound { parts.append(.hidden(line...gap.upperBound)) }
        return parts
    }

    /// Dotýkající se rozsahy se slévají taky, ne jen překrývající: `1...10` a `11...20` je
    /// jeden souvislý blok, ne dva vedle sebe.
    private func touches(_ lhs: ClosedRange<Int>, _ rhs: ClosedRange<Int>) -> Bool {
        lhs.lowerBound <= rhs.upperBound + 1 && rhs.lowerBound <= lhs.upperBound + 1
    }

    private func intersection(of range: ClosedRange<Int>, and gap: ClosedRange<Int>) -> ClosedRange<Int>? {
        let lower = max(range.lowerBound, gap.lowerBound)
        let upper = min(range.upperBound, gap.upperBound)
        return lower <= upper ? lower...upper : nil
    }
}
