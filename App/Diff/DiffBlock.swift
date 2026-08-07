import Foundation

/// Souvislý úsek řádků diffu, který se kreslí jako **jeden text** (#157).
///
/// Vzniklo proto, že ve SwiftUI je každý `Text` vlastní selekce, takže v diffu skládaném po řádcích
/// by šlo vybrat jen jeden řádek. Výběr přes řádky umí **jedno** textové zobrazení — `NSTextView` —
/// takže se souvislé řádky slučují do bloku a ten se kreslí jím.
///
/// **Blok končí tam, kde do diffu něco vstoupí**: hlavička hunku, rozbalovací řádek, bublina
/// nálezu, cizí vlákno, můj rozdělaný komentář. Selekce tedy jde přes celý úsek kódu mezi dvěma
/// takovými věcmi — u většiny řádků je to celý hunk, protože bubliny visí jen u některých.
struct DiffBlock: Hashable, Sendable {
    /// Řádky bloku v pořadí, jak jsou v souboru. Čísla řádků a znaky změny se kreslí **mimo text**
    /// (`DiffTextView`), aby se nekopírovaly — blok drží jen ty řádky.
    let lines: [DiffLine]
}

/// Totéž pro pohled **vedle sebe**: dva bloky, které si odpovídají řádek po řádku.
///
/// Sloupce musí zůstat **zarovnané**, jinak přestane platit, že vlevo a vpravo je tentýž řádek
/// souboru. Proto se v tomhle bloku **nezalamuje** a dlouhý řádek se posouvá vodorovně: se
/// zalamováním by jeden sloupec narostl o vizuální řádek a druhý ne. V pohledu pod sebou je to
/// obráceně — tam žádný protějšek není, takže se zalamuje jako dosud.
struct DiffPairBlock: Hashable, Sendable {
    /// Levá strana po řádcích; `nil` = na téhle straně dvojice řádek není.
    let left: [DiffLine?]
    let right: [DiffLine?]

    /// Kolik řádků dvojice má. Obě strany mají po sloučení **stejnou délku** (viz `blockedPairs`),
    /// takže je to jen pojmenování toho, co drží zarovnání sloupců.
    var count: Int { max(left.count, right.count) }
}

extension DiffRow {
    /// Slije po sobě jdoucí řádky do bloků. Ostatní řádky (hlavičky, bubliny, expandery) zůstanou,
    /// jak byly — jsou to právě ony, co blok ukončuje.
    ///
    /// Volá se **až při vykreslení** (`DiffView`), ne z `rows(of:)`: `DiffRow` je model, ze kterého
    /// se ptá i kotva skoku na nález a výběr vláken, a ty mluví o řádcích. Sloučení je o tom, jak
    /// se to kreslí.
    ///
    /// Identita bloku nese `id` **prvního** řádku, takže je stabilní: dokud se před ním nic
    /// nezmění, blok si drží identitu i po přidání komentáře za ním.
    static func blocked(_ rows: [DiffRow]) -> [DiffRow] {
        var result: [DiffRow] = []
        var pending: [(id: String, line: DiffLine)] = []

        func flush() {
            guard let first = pending.first else { return }
            result.append(.block(first.id, DiffBlock(lines: pending.map(\.line))))
            pending = []
        }

        for row in rows {
            if case .line(let id, let line) = row {
                pending.append((id, line))
            } else {
                flush()
                result.append(row)
            }
        }
        flush()
        return result
    }

    /// Totéž pro dvojice v pohledu vedle sebe (#157).
    static func blockedPairs(_ rows: [DiffRow]) -> [DiffRow] {
        var result: [DiffRow] = []
        var pending: [(id: String, left: DiffLine?, right: DiffLine?)] = []

        func flush() {
            guard let first = pending.first else { return }
            result.append(.pairBlock(
                first.id,
                DiffPairBlock(left: pending.map(\.left), right: pending.map(\.right))
            ))
            pending = []
        }

        for row in rows {
            if case .pair(let id, let left, let right) = row {
                pending.append((id, left, right))
            } else {
                flush()
                result.append(row)
            }
        }
        flush()
        return result
    }
}
