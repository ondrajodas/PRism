import Foundation

/// Změny jednoho souboru.
struct FileDiff: Hashable, Sendable, Identifiable {
    enum Change: Hashable, Sendable {
        case added
        case deleted
        case modified
        case renamed
    }

    /// `nil` u nově přidaného souboru.
    let oldPath: String?
    /// `nil` u smazaného souboru.
    let newPath: String?
    let change: Change
    /// Binárka nemá hunky — `gh pr diff` u ní pošle jen `Binary files … differ`.
    let isBinary: Bool
    let hunks: [DiffHunk]

    /// Odvozené z cest, ne generované: skok na soubor v #20 musí přežít překreslení,
    /// takže identita nesmí vzniknout pokaždé jiná.
    var id: String { "\(oldPath ?? "/dev/null") → \(newPath ?? "/dev/null")" }

    /// Pod jakým jménem soubor v okně vystupuje — po přejmenování pod novým.
    var displayPath: String { newPath ?? oldPath ?? "?" }

    /// Je tenhle řádek nového souboru v některém hunku? Podle toho se pozná nález, ke
    /// kterému se musí kód teprve dotáhnout.
    func showsLine(_ line: Int) -> Bool {
        hunks.contains { hunk in hunk.lines.contains { $0.newNumber == line } }
    }

    var additions: Int { count(of: .added) }
    var deletions: Int { count(of: .removed) }

    private func count(of kind: DiffLine.Kind) -> Int {
        var total = 0
        for hunk in hunks {
            total += hunk.lines.count(where: { $0.kind == kind })
        }
        return total
    }
}
