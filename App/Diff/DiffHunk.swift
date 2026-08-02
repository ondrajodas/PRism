import Foundation

/// Souvislý kus změny v jednom souboru.
struct DiffHunk: Hashable, Sendable {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    /// Text za druhým `@@` — funkce nebo sekce, ve které hunk leží. `git` ho dává jako
    /// nápovědu a nemusí být vždycky; pak je prázdný.
    let heading: String
    let lines: [DiffLine]

    /// `@@ -171,8 +171,14 @@` — hlavička tak, jak se ukazuje nad hunkem. Skládá se
    /// zpátky, místo aby se schovával původní řádek: rozsahy jsou stejně rozparsované
    /// a dvě pravdy o jedné věci by se rozešly.
    var header: String {
        "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
    }
}
