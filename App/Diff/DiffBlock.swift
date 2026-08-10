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
    /// **Nejvíc řádků v jednom bloku** (#223). Blok je nejmenší jednotka, kterou umí `LazyVStack`
    /// přeskočit, takže nerozdělený soubor znamená, že se nepřeskočí nikdy — rozloží se text, který
    /// není vidět.
    ///
    /// Číslo je z měření, ne z odhadu. Cena vykreslení bloku je **lineární v jeho délce**
    /// (~0,085 ms na řádek): 20 řádků 2,6 ms, 60 → 7 ms, 200 → 24 ms, 600 → 69 ms, 2400 → 201 ms.
    /// Šedesát je proto zhruba obrazovka kódu a se dvěma viditelnými bloky se vejde do rozpočtu na
    /// snímek (16,7 ms); dvěstě už ne.
    ///
    /// Rozdělení **nešetří celkovou práci** — celý soubor vykreslený po blocích stojí stejně jako
    /// v jednom (měřeno 150–280 ms bez zjevného trendu). Šetří ji jedině tou leností.
    ///
    /// **Co to bere:** výběr táhnutím přes víc než šedesát řádků. Je to vědomá cena — celý hunk se
    /// dá zkopírovat z kontextového menu (`Kopírovat hunk`) a vybrat v sheetu s textem, takže na
    /// tahu myší nezávisí.
    static let maxLines = 60

    /// Řádky bloku v pořadí, jak jsou v souboru. Čísla řádků a znaky změny se kreslí **mimo text**
    /// (`DiffTextView`), aby se nekopírovaly — blok drží jen ty řádky.
    let lines: [DiffLine]
    /// Identity řádků, které se do bloku slily.
    ///
    /// Blok se v seznamu kreslí pod `id` toho **prvního**, takže na ostatní se skočit nedá —
    /// `scrollTo` na jejich `id` tiše neudělá nic. Tenhle seznam je to, čím se cíl skoku přeloží
    /// na blok, který ho pokrývá (`DiffRow.blockIDs(in:)`). Bez něj mířil skok na nález uprostřed
    /// úseku do prázdna, což bylo od #157 vidět jako „klik nedělá nic“.
    var ids: [String] = []
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

    /// Identity slitých dvojic — viz `DiffBlock.ids`.
    var ids: [String] = []

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
            result.append(.block(
                first.id,
                DiffBlock(lines: pending.map(\.line), ids: pending.map(\.id))
            ))
            pending = []
        }

        for row in rows {
            if case .line(let id, let line) = row {
                pending.append((id, line))
                // Strop se kontroluje **po přidání**, takže blok má nejvýš `maxLines` řádků a další
                // řádek začne nový. Identita zůstává stabilní: nese ji první řádek úseku.
                if pending.count == DiffBlock.maxLines { flush() }
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
                DiffPairBlock(
                    left: pending.map(\.left),
                    right: pending.map(\.right),
                    ids: pending.map(\.id)
                )
            ))
            pending = []
        }

        for row in rows {
            if case .pair(let id, let left, let right) = row {
                pending.append((id, left, right))
                // Tentýž strop jako u bloků pod sebou (#223) — dvojice nese dvě strany, takže
                // nerozdělená je dokonce dvakrát tolik textu k rozložení.
                if pending.count == DiffBlock.maxLines { flush() }
            } else {
                flush()
                result.append(row)
            }
        }
        flush()
        return result
    }
}

extension DiffRow {
    /// Překlad `id` řádku na `id` bloku, který ho pokrývá.
    ///
    /// Skok na nález i na komentář míří na **řádek**, ale v seznamu je od #157 blok — a ten nese
    /// `id` jen toho prvního. Bez překladu `scrollTo` tiše nic neudělá, což je ta nejhorší podoba
    /// chyby: nic se nestane a není z čeho poznat proč.
    ///
    /// Řádky, které se do bloku neslily (hlavičky, bubliny, expandery), se mapují samy na sebe,
    /// takže výsledek pokrývá **všechno**, na co se dá skočit.
    static func blockIDs(in rows: [DiffRow]) -> [String: String] {
        var index: [String: String] = [:]
        for row in rows {
            switch row {
            case .block(let id, let block):
                for lineID in block.ids { index[lineID] = id }
            case .pairBlock(let id, let block):
                for lineID in block.ids { index[lineID] = id }
            default:
                index[row.id] = row.id
            }
        }
        return index
    }
}
