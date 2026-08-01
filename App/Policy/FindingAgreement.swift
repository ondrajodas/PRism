import Foundation

/// Nálezy, které se potkaly na jednom místě v kódu.
///
/// Texty se **nikdy neslučují** — nesouhlas dvou reviewerů je informace, ne šum. Slučuje se
/// jen bublina v diffu, a to, že za ní stojí víc reviewerů, říká odznak.
struct FindingGroup: Hashable, Sendable {
    /// `nil` u nálezu, který k žádnému řádku nepatří (chybějící testy, poznámka
    /// k architektuře). Takové se neslučují — „stejný soubor bez řádku“ není místo.
    let file: String?
    let line: Int?
    /// Nikdy prázdné.
    var findings: [Finding]

    /// Kolik **nezávislých** reviewerů to nahlásilo — odznak `2×`.
    ///
    /// Reviewery, ne nálezy: jeden reviewer, který na jednom řádku najde dvě různé věci,
    /// si nepřikyvuje.
    var agreement: Int { Set(findings.map(\.reviewer)).count }
}

extension Policy {
    /// Seskupí nálezy podle `file:line` napříč reviewery.
    ///
    /// Pořadí skupin kopíruje pořadí, ve kterém se místa poprvé objevila ve vstupu — takže
    /// setříděný vstup dá setříděný výstup a `Policy` nemá dvě různá řazení.
    static func groups(of findings: [Finding]) -> [FindingGroup] {
        var groups: [FindingGroup] = []
        var index: [Location: Int] = [:]

        for finding in findings {
            guard let file = finding.file, let line = finding.line else {
                groups.append(FindingGroup(file: finding.file, line: finding.line, findings: [finding]))
                continue
            }

            let location = Location(file: file, line: line)
            if let existing = index[location] {
                groups[existing].findings.append(finding)
            } else {
                index[location] = groups.count
                groups.append(FindingGroup(file: file, line: line, findings: [finding]))
            }
        }
        return groups
    }

    /// Místo v kódu. Jen jako klíč slučování — ven se nedostane.
    private struct Location: Hashable {
        let file: String
        let line: Int
    }
}
