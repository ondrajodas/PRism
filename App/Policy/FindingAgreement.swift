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
    /// Co o nálezech **v téhle skupině** říká kontrola z minula (#150).
    ///
    /// Filtrovaná mapa ze stejného důvodu jako u odmítnutí: skupina je hodnota v `DiffRow`, takže
    /// by ji celá mapa překreslovala kvůli nálezu v jiném souboru.
    var rechecks: [FindingKey: RecheckStatus] = [:]

    /// Platí na nálezu odmítnutí? Bublina se podle toho kreslí sbalená.
    func dismissal(of finding: Finding) -> FindingDismissal? {
        dismissals[Policy.key(of: finding)]
    }

    /// Co o nálezu řekla kontrola. `nil` = neběžela, neplatí pro hlavu PR, nebo se k němu
    /// nevyjádřila — pro odznak je to jedno, kreslit se nemá.
    func recheck(of finding: Finding) -> RecheckStatus? {
        rechecks[Policy.key(of: finding)]
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
    /// - Parameters:
    ///   - dismissals: celá mapa ze záznamu; každá skupina si z ní vezme jen to své.
    ///   - rechecks: totéž pro stavy z kontroly nálezů (#150).
    static func groups(
        of findings: [Finding],
        dismissals: [FindingKey: FindingDismissal] = [:],
        rechecks: [FindingKey: RecheckStatus] = [:]
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

        guard !dismissals.isEmpty || !rechecks.isEmpty else { return groups }
        // Jde se po **nálezech ve skupině** a mapy se jen dotazují, ne filtrují: filtr přes
        // celou mapu s lineárním hledáním uvnitř je O(skupiny × odmítnutí × nálezy) a tohle
        // běží při každém překreslení diffu. Klíč se skládá **jednou na nález** pro obě mapy.
        return groups.map { group in
            var group = group
            var mine: [FindingKey: FindingDismissal] = [:]
            var myRechecks: [FindingKey: RecheckStatus] = [:]
            for finding in group.findings {
                let key = Policy.key(of: finding)
                if let dismissal = dismissals[key] { mine[key] = dismissal }
                if let status = rechecks[key] { myRechecks[key] = status }
            }
            group.dismissals = mine
            group.rechecks = myRechecks
            return group
        }
    }

    /// Místo v kódu. Jen jako klíč slučování — ven se nedostane.
    private struct Location: Hashable {
        let file: String
        let line: Int
    }
}
