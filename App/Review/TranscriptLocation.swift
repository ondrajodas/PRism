import Foundation

/// Kde `claude` vede transcript session (#97).
///
/// Cesta je **odvoditelná z pracovního stromu**, takže se transcript zabitého běhu dá najít
/// i po restartu aplikace: `claude` si pro každý pracovní adresář zakládá složku
/// v `~/.claude/projects/` pojmenovanou podle té cesty, a v ní jeden `<session-id>.jsonl`
/// na session.
///
/// Čistá funkce, žádné I/O — číst umí `TranscriptStore`.
enum TranscriptLocation {
    /// Výchozí kořen, ve kterém `claude` složky zakládá.
    static var defaultProjects: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")
    }

    /// Transcript jedné session nad daným pracovním stromem.
    static func transcript(ofSession sessionID: String, in worktree: URL, projects: URL) -> URL {
        projects
            .appending(path: mangled(worktree))
            .appending(path: "\(sessionID).jsonl")
    }

    /// Jméno složky, kterou si `claude` pro pracovní adresář zakládá.
    ///
    /// **Změřeno, ne odhadnuto** (#97). Zadání mluvilo o „`/` a mezery na `-`“, jenže pravidlo
    /// je širší: nahrazuje se **všechno mimo `[A-Za-z0-9-]`**. Ověřeno spuštěním `claude`
    /// ve složkách s vyrobenými názvy:
    ///
    /// ```
    /// …/scratchpad/tečka test.v2/sub      → …-scratchpad-te-ka-test-v2-sub
    /// …/scratchpad/a_b+c~d(e)f'g,h@i#j    → …-scratchpad-a-b-c-d-e-f-g-h-i-j
    /// ```
    ///
    /// Z toho plyne i to, co se **nemění**: velikost písmen zůstává (`PRism` → `PRism`)
    /// a existující pomlčky se nesluřují — `/-Users` dá `--Users`. Kdyby se slučovaly, dvě
    /// různé cesty by vyšly na jednu složku.
    ///
    /// Nezachovává se ani informace o tom, co se nahradilo, takže **zpětně to nejde přeložit**
    /// — proto se hledá vždycky od pracovního stromu, ne od jména složky.
    static func mangled(_ worktree: URL) -> String {
        let path = worktree.standardizedFileURL.path(percentEncoded: false)
        return String(path.map { isKept($0) ? $0 : "-" })
    }

    private static func isKept(_ character: Character) -> Bool {
        character == "-" || character.isASCII && (character.isLetter || character.isNumber)
    }
}
