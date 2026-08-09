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
}
