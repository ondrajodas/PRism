import Foundation

/// Co nese pruh na pravé hraně řádku a hrana karty v okraji (#503).
///
/// Je to **tatáž škála jako u bubliny pod řádkem a u karty v panelu** (`FindingBubbleView.accent`,
/// `FindingCardView.accent`, řádek fronty #172) — jen vyjádřená hodnotou, aby o barvě rozhodovalo
/// jedno místo v kresbě (`DiffMarginSeverity.stripe`) a `Policy` zůstala bez `SwiftUI`.
enum DiffMarginSeverity: Hashable, Sendable {
    /// Aspoň jeden platný nález skupiny blokuje merge.
    case blocking
    /// Platný nález, který merge nedrží.
    case finding
    /// Ze skupiny nezbyl platný nález — odmítl jsem je všechny (#113). **Karta nemizí**, jen
    /// ztichne: schovaný nález se nedá přečíst a nedá se odlišit od neexistujícího.
    case dismissed
}

/// Jedna karta v okraji vpravo (#503).
///
/// **Vzniká z dat, ne z geometrie**: o tom, jestli karta existuje, rozhoduje `Policy` nad diffem
/// (soubor je rozbalený a jeho řádek se doopravdy kreslí), kdežto geometrie říká jen **kde** stojí.
/// Kdyby o existenci karty rozhodovalo hlášení z bloku, zmizela by karta u řádku, jehož blok je
/// zrovna mimo nasazený pás (#469) — tedy pokaždé, když se odscrolluje.
struct DiffMarginCard: Identifiable, Hashable, Sendable {
    /// Klíč, na kterém se karta a pruh u řádku potkají: `<cesta souboru>|<řádek>`.
    ///
    /// Skládá se **z cesty, kterou zná blok kódu** (`FileDiff.displayPath`), ne z té, pod kterou
    /// nález přišel: reviewer umí přejmenovaný soubor nahlásit pod starou cestou, takže by se ty
    /// dvě strany jinak nepotkaly.
    let id: String
    let group: FindingGroup
    let path: String
    /// Číslo řádku v **nové** verzi souboru — na to se nález kotví (`DiffRow.withBubbles`).
    let line: Int
    let severity: DiffMarginSeverity
}

/// Značka u jednoho řádku bloku kódu (#503): pruh na pravé hraně a klíč, pod kterým blok hlásí,
/// kde ten řádek leží.
struct DiffMarginMark: Hashable, Sendable {
    let id: String
    let severity: DiffMarginSeverity
}

/// Soubor diffu tak, jak ho okraj potřebuje znát.
///
/// Tři hodnoty, ne closury: `Policy` je čistá funkce a testuje se výčtem, takže si stav
/// (rozbalený kontext, sbalený soubor) skládá volající — je to tentýž vzorec jako u
/// `Policy.commentRangeCells(of:in:)`.
struct DiffMarginSource: Sendable {
    let file: FileDiff
    /// Odkryté úseky mimo hunky. **Prázdné, dokud se obsah souboru nenačte** — tatáž úvaha jako
    /// v `DiffRow.rows(of:…)`, jinak by se karta kotvila na řádek, který se nekreslí.
    let revealed: RevealedLines
    let isFolded: Bool
}

/// Které postranní sloupce diffu jsou rozložené (#188, rozšířeno #503).
struct DiffSideColumns: Hashable, Sendable {
    let tree: Bool
    let panel: Bool
}

extension Policy {
    /// Karty do okraje vpravo (#503) — v pořadí obsahu, tedy po souborech a v nich po řádcích.
    ///
    /// Karta vznikne jedině tam, kde má **co k čemu zarovnat**: soubor je rozbalený a jeho řádek
    /// se v diffu doopravdy kreslí (hunk, nebo odkrytý kontext). Nález bez řádku, nález na řádku,
    /// který v diffu není, i nález ve sbaleném souboru proto v okraji **nejsou** — zůstávají tam,
    /// kde jsou dneska: jako bublina u hlavičky souboru (`DiffRow.finding(anchored: false)`),
    /// respektive jako počet v hlavičce sbaleného souboru. Bez toho pravidla by se karta buď
    /// neměla kde postavit, nebo by tvrdila polohu řádku, který nikdo nekreslí.
    ///
    /// Nálezy se do skupin slévají **tou samou funkcí jako bubliny** (`DiffRow.groups(of:from:)`),
    /// takže se okraj a diff nemohou rozejít v tom, kolik nálezů na jednom řádku je.
    static func marginCards(
        of groups: [FindingGroup],
        in sources: [DiffMarginSource],
        categories: Set<String> = defaultBlockingCategories
    ) -> [DiffMarginCard] {
        var cards: [DiffMarginCard] = []
        for source in sources where !source.isFolded {
            let file = source.file
            var mine: [DiffMarginCard] = []
            for group in DiffRow.groups(of: file, from: groups) {
                guard let line = group.line,
                      DiffRow.renders(line: line, of: file, revealed: source.revealed)
                else { continue }
                mine.append(DiffMarginCard(
                    id: marginKey(path: file.displayPath, line: line),
                    group: group,
                    path: file.displayPath,
                    line: line,
                    severity: marginSeverity(of: group, categories: categories)
                ))
            }
            // Uvnitř souboru podle řádku: `DiffRow.groups` vrací skupiny ze slovníku, takže pořadí
            // nemá — a v okraji je pořadí to, podle čeho se karty odstrkují.
            cards += mine.sorted { $0.line < $1.line }
        }
        return cards
    }

    /// Klíč karty. Jedno místo pro obě strany — okraj i blok kódu.
    static func marginKey(path: String, line: Int) -> String { "\(path)|\(line)" }

    /// Značky pro jeden soubor, klíčované **novým** číslem řádku: blok kódu o kartách nic neví,
    /// zná jen řádky, takže se překlad musí odehrát tady.
    static func marginMarks(of cards: [DiffMarginCard], in path: String) -> [Int: DiffMarginMark] {
        var marks: [Int: DiffMarginMark] = [:]
        for card in cards where card.path == path {
            marks[card.line] = DiffMarginMark(id: card.id, severity: card.severity)
        }
        return marks
    }

    /// Kde karty v okraji doopravdy stojí — **zarovnané k řádku, a když se potkají, odstrčené**.
    ///
    /// Karta chce stát na horní hraně svého řádku. Když by se přitom trefila do té nad sebou,
    /// odstrčí se pod ni; spojnice se tím zalomí do `L` a to je právě to, co ze zarovnání zbude
    /// (kresbu řeší `DiffMarginView`). Odstrkuje se **jen dolů**: nahoru by karta minula řádek,
    /// který už je vidět, a čte se vždycky odshora.
    ///
    /// - Parameters:
    ///   - desired: kde by karta stát chtěla. `nil` = polohu jejího řádku ještě žádný blok
    ///     neohlásil (první rozvržení, nebo blok, který se nikdy nekreslil). Karta pak jde **za
    ///     předchozí**, protože „nevím kde“ je pořád lepší odpověď než „na nule“ — zmizet nesmí.
    ///   - heights: změřené výšky karet ve stejném pořadí. Chybějící výška se bere jako nula,
    ///     tedy bez odstrčení: karta, kterou nikdo nezměřil, o sousedech nic netvrdí.
    ///   - gap: mezera mezi odstrčenými kartami (návrh má 8).
    static func marginTops(desired: [Double?], heights: [Double], gap: Double) -> [Double] {
        var tops: [Double] = []
        tops.reserveCapacity(desired.count)
        // Obsah začíná na nule, takže výš než tam se karta dostat nemá — jinak by vyjela nad diff.
        var floor = 0.0
        for (index, wanted) in desired.enumerated() {
            let top = max(wanted ?? floor, floor)
            tops.append(top)
            floor = top + (heights.indices.contains(index) ? heights[index] : 0) + gap
        }
        return tops
    }

    /// Které postranní sloupce jsou rozložené (#188, rozšířeno #503).
    ///
    /// **Pohled vedle sebe složí oba** — řádek se v něm dělí na dvě strany, takže na 14" nezbude
    /// ani sto znaků (#188).
    ///
    /// **A okraj s kartami složí panel vpravo**, protože v tom stavu jsou vpravo dvě třistabodové
    /// kolony o téže věci: karta v okraji a týž nález jako řádek v panelu. Panel **nezmizí** —
    /// složený je proužek s počtem nálezů a značkou rozdělaného review, a `⌘2` ho vrátí až do
    /// další změny pohledu, přesně jako u #188. Je to **mezistav**: seznam nálezů v panelu ruší
    /// #504, a tím tahle podmínka odpadne.
    static func diffSideColumns(layout: DiffLayout, hasMargin: Bool) -> DiffSideColumns {
        let wide = layout != .split
        return DiffSideColumns(tree: wide, panel: wide && !hasMargin)
    }

    /// Barva hrany karty a pruhu u řádku. Odmítnutá skupina ztichne, blokující křičí — **tatáž
    /// úvaha jako `FindingBubbleView.accent`**, jen vyjádřená hodnotou.
    private static func marginSeverity(
        of group: FindingGroup,
        categories: Set<String>
    ) -> DiffMarginSeverity {
        let active = group.activeFindings
        guard !active.isEmpty else { return .dismissed }
        return active.contains { isBlocking($0, categories: categories) } ? .blocking : .finding
    }
}
