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
    /// Odmítnutí, která platí na nálezy **v téhle skupině** (#113).
    ///
    /// Filtrovaná mapa, ne celá ze záznamu: skupina je hodnota v `DiffRow`, takže by ji jinak
    /// změnilo odmítnutí nálezu v úplně jiném souboru — a líný seznam by překresloval bubliny,
    /// se kterými se nic nestalo.
    var dismissals: [FindingKey: FindingDismissal] = [:]

    /// Platí na nálezu odmítnutí? Bublina se podle toho kreslí sbalená.
    func dismissal(of finding: Finding) -> FindingDismissal? {
        dismissals[Policy.key(of: finding)]
    }

    /// Nálezy, které pořád platí. Ty odmítnuté ze skupiny **nemizí** — schovaný nález se nedá
    /// přečíst a nedá se odlišit od neexistujícího.
    var activeFindings: [Finding] { findings.filter { dismissal(of: $0) == nil } }

    /// Kolik **nezávislých** reviewerů to nahlásilo — odznak `2×`.
    ///
    /// Reviewery, ne nálezy: jeden reviewer, který na jednom řádku najde dvě různé věci,
    /// si nepřikyvuje.
    ///
    /// A jen ty platné: shoda dvou reviewerů, ze kterých jednomu nevěřím, není shoda. Když
    /// z dvojice zbyde jeden, odznak proto zmizí — tatáž lekce jako u odznaku „už je
    /// v draftu“ (#66), kde odmítnutí jednoho revieweera nesmí mluvit za druhého.
    var agreement: Int { Set(activeFindings.map(\.reviewer)).count }
}

extension Policy {
    /// Seskupí nálezy podle `file:line` napříč reviewery.
    ///
    /// Pořadí skupin kopíruje pořadí, ve kterém se místa poprvé objevila ve vstupu — takže
    /// setříděný vstup dá setříděný výstup a `Policy` nemá dvě různá řazení.
    ///
    /// - Parameter dismissals: celá mapa ze záznamu; každá skupina si z ní vezme jen to své.
    static func groups(
        of findings: [Finding],
        dismissals: [FindingKey: FindingDismissal] = [:]
    ) -> [FindingGroup] {
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

        guard !dismissals.isEmpty else { return groups }
        // Jde se po **nálezech ve skupině** a mapa se jen dotazuje, ne filtruje: filtr přes
        // celou mapu s lineárním hledáním uvnitř je O(skupiny × odmítnutí × nálezy) a tohle
        // běží při každém překreslení diffu.
        return groups.map { group in
            var group = group
            var mine: [FindingKey: FindingDismissal] = [:]
            for finding in group.findings {
                let key = Policy.key(of: finding)
                guard let dismissal = dismissals[key] else { continue }
                mine[key] = dismissal
            }
            group.dismissals = mine
            return group
        }
    }

    /// Místo v kódu. Jen jako klíč slučování — ven se nedostane.
    private struct Location: Hashable {
        let file: String
        let line: Int
    }
}
