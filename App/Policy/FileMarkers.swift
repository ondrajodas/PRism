import Foundation

/// Značka u souboru ve stromu (#197) — jestli v něm něco je a jak je to vážné.
enum FileMarker: Hashable, Sendable {
    /// Je v něm aspoň jeden blokující nález.
    case blocking
    /// Nálezy má, ale žádný neblokuje.
    case findings
}

extension Policy {
    /// Které soubory nesou nález a jak vážný (#197).
    ///
    /// Mapa z **cesty**, ne z indexu: strom si soubory přerovnává do složek, takže index řádku
    /// o souboru nic neříká. Nálezy bez cesty se vynechávají — patří celému PR, ne souboru,
    /// a v panelu mají vlastní místo.
    ///
    /// **Odmítnuté nálezy odfiltruje volající** (`FindingGroup.activeFindings`) — odsud se to
    /// poznat nedá, `Finding` o odmítnutí nic neví. Kdo sem pošle nefiltrovaný seznam, dostane
    /// značku i u souboru, jehož jediný nález jsem zamítl (#113).
    static func fileMarkers(
        of findings: [Finding],
        categories: Set<String> = defaultBlockingCategories
    ) -> [String: FileMarker] {
        var markers: [String: FileMarker] = [:]
        for finding in findings {
            guard let file = finding.file else { continue }
            // Blokující přebíjí obyčejný a **nedá se přebít zpátky**: soubor se dvěma nálezy,
            // z nichž jeden blokuje, je blokující bez ohledu na to, v jakém pořadí dorazily.
            if isBlocking(finding, categories: categories) {
                markers[file] = .blocking
            } else if markers[file] == nil {
                markers[file] = .findings
            }
        }
        return markers
    }

    /// Co je v souboru k vyřízení — pro kapsli v hlavičce souboru v diffu (#219).
    ///
    /// Počítá se po **skupinách**, ne po nálezech: skupina je jedno místo v kódu, a tři reviewery,
    /// kteří se shodli na témž řádku, jsou jedna věc k rozhodnutí, ne tři. Odmítnuté se vynechají
    /// (#113) — kapsle je zkratka „kde je co vyřídit“, takže nález, který jsem posoudil a zamítl,
    /// v ní nemá co dělat.
    ///
    /// Vrací **čísla, ne text**: jak se to napíše, je věc hlavičky. Obojí nule = v souboru není
    /// co vyřídit a kapsle se nekreslí.
    static func fileFindings(
        in groups: [FindingGroup],
        categories: Set<String> = defaultBlockingCategories
    ) -> (blocking: Int, total: Int) {
        var blocking = 0
        var total = 0
        for group in groups {
            let active = group.activeFindings
            guard !active.isEmpty else { continue }
            total += 1
            if active.contains(where: { isBlocking($0, categories: categories) }) { blocking += 1 }
        }
        return (blocking, total)
    }
}
