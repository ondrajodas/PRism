import Foundation

/// Jeden čtvereček poměru změny za `+X −Y` (#218, `.diffstat .blocks`).
enum DiffstatBlock: Equatable, Sendable {
    case added
    case removed
    /// Zbytek po zaokrouhlení dolů — kus změny, který ani jedna strana nedostala celý.
    case neither
}

extension Policy {
    /// Pět čtverečků poměru přidaných a odebraných řádků, jak je má návrh.
    ///
    /// Zaokrouhluje se **dolů**, každá strana zvlášť, a zbytek zůstává šedý. Návrh to tak
    /// kreslí (`+248 −96` → tři zelené, jeden červený, jeden šedý) a je to i jediné zaokrouhlení,
    /// které nikdy nelže: nahoru by z jednoho odebraného řádku ve dvousetřádkovém PR udělalo
    /// celý čtvereček, tedy pětinu změny.
    ///
    /// **Prázdný diff dá prázdno**, ne pět šedých: pruh, který je pořád stejný, nic neříká —
    /// a `+0 −0` vedle něj to říká líp.
    static func diffstatBlocks(additions: Int, deletions: Int, count: Int = 5) -> [DiffstatBlock] {
        let total = max(additions, 0) + max(deletions, 0)
        guard total > 0, count > 0 else { return [] }

        let added = max(additions, 0) * count / total
        let removed = max(deletions, 0) * count / total
        return Array(repeating: .added, count: added)
            + Array(repeating: .removed, count: removed)
            + Array(repeating: .neither, count: count - added - removed)
    }
}
