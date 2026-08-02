import Foundation

/// Diff pull requestu tak, jak se dá zobrazit.
struct Diff: Hashable, Sendable {
    let files: [FileDiff]
    /// Kolik řádků parser nepoznal.
    ///
    /// Musí být vidět: diff, ze kterého kus tiše vypadl, vypadá jako úplný — a review se
    /// dělá nad tím, co je na obrazovce. Stejné pravidlo jako u `droppedFindings`.
    let unrecognizedLines: Int

    var isEmpty: Bool { files.isEmpty }
    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
}
