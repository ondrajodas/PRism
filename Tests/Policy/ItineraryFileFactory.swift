import Foundation

@testable import PRism

/// Skládá `FileDiff` pro testy itineráře (#506) — **jedno místo, ať se dvě sady neptají na
/// jinak postavený soubor**.
///
/// Jméno je jednoznačné napříč celým `Tests/` (konvence z #184): dva zdrojáky se stejným jménem
/// build položí, i když leží v různých podsložkách.
enum ItineraryFileFactory {
    static func file(
        _ path: String,
        change: FileDiff.Change = .modified,
        additions: Int = 1,
        deletions: Int = 1
    ) -> FileDiff {
        FileDiff(
            oldPath: change == .added ? nil : path,
            newPath: change == .deleted ? nil : path,
            change: change,
            isBinary: false,
            hunks: [
                DiffHunk(
                    oldStart: 1,
                    oldCount: deletions,
                    newStart: 1,
                    newCount: additions,
                    heading: "",
                    lines: (0..<additions).map {
                        DiffLine(kind: .added, oldNumber: nil, newNumber: $0 + 1, text: "x")
                    } + (0..<deletions).map {
                        DiffLine(kind: .removed, oldNumber: $0 + 1, newNumber: nil, text: "y")
                    }
                )
            ],
            blobs: "aaa..bbb"
        )
    }
}
