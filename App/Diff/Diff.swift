import Foundation

/// Diff pull requestu tak, jak se dá zobrazit.
struct Diff: Hashable, Sendable {
    let files: [FileDiff]
    /// Kolik řádků parser nepoznal.
    ///
    /// Musí být vidět: diff, ze kterého kus tiše vypadl, vypadá jako úplný — a review se
    /// dělá nad tím, co je na obrazovce. Stejné pravidlo jako u `droppedFindings`.
    let unrecognizedLines: Int

    /// Soubor podle cesty — hledá se podle **obou**, protože přejmenovaný soubor umí
    /// reviewer nahlásit pod tou starou. Jedno místo na překlad: kotva skoku, dotahování
    /// kódu k nálezům i bubliny se jinak rozejdou.
    func file(at path: String) -> FileDiff? {
        files.first { $0.newPath == path || $0.oldPath == path }
    }

    var isEmpty: Bool { files.isEmpty }
    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
}
