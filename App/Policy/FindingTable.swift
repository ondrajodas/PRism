import Foundation

/// Sloupec tabulky nálezů, podle kterého se dá řadit (#242).
///
/// Sloupec s akcemi mezi nimi **není**: `Převzít` a `⋯` nejsou hodnota, takže by řazení podle nich
/// nic neznamenalo.
enum FindingTableColumn: Hashable, Sendable, CaseIterable {
    case severity
    case summary
    case location
    /// Reviewer a jeho kategorie — jeden sloupec, dva řádky, jak ho má návrh.
    case reviewer
}

/// Podle čeho je tabulka setříděná. `nil` (tedy žádná volba) znamená pořadí z `Policy.sorted`.
struct FindingTableSort: Hashable, Sendable {
    var column: FindingTableColumn
    /// Vzestupně = od nejmenšího. U závažnosti tedy **od nejmírnějšího**, takže výchozí pohled
    /// (nejvážnější nahoře) je `severity` sestupně — a kliknutí na hlavičku ho jen otočí.
    var isAscending: Bool

    /// Volba po kliknutí na hlavičku sloupce.
    ///
    /// První kliknutí řadí tak, jak se ten sloupec **čte** — závažnost od nejvážnějšího, text od
    /// „a“. Druhé kliknutí otočí. Rozhoduje o tom `Policy`, ne view: je to pravidlo, ne kreslení.
    static func toggled(_ column: FindingTableColumn, from current: FindingTableSort?) -> FindingTableSort {
        guard let current, current.column == column else {
            return FindingTableSort(column: column, isAscending: column != .severity)
        }
        return FindingTableSort(column: column, isAscending: !current.isAscending)
    }
}

/// Šířky sloupců tabulky nálezů — **spočítané, ne vyjednané** (#220).
///
/// `frame(maxWidth: .infinity)` v každé buňce každého řádku je přesně ten vzor, kvůli kterému se
/// okno na velkém PR zaseklo na 20 minut. Tabulka proto dostane šířku odshora a rozdělí si ji
/// jednou.
struct FindingTableLayout: Equatable, Sendable {
    let severity: Double
    let summary: Double
    let location: Double
    /// `nil` = sloupec se nevešel a **odpadl**. Je to jediný sloupec, jehož obsah je i v bublině
    /// u kódu a v chipech reviewerů nad diffem, takže se dá obětovat, aniž by se něco ztratilo.
    let reviewer: Double?
    let actions: Double

    /// Proužek závažnosti na hraně řádku (`.frow .bar`).
    static let bar = 4.0
    static let spacing = 11.0
    static let inset = 16.0
}

extension Policy {
    /// Od téhle šířky obsahu se vejde i sloupec `reviewer · kategorie`.
    ///
    /// Číslo je z rozpočtu, ne z citu: pod ním by shrnutí zbylo méně než `minimumSummary`, a to je
    /// šířka, ve které se dlouhá věta láme po dvou slovech. Tabulka je uvnitř tabu, takže obsahová
    /// šířka = okno bez railu a bez panelu vpravo — v nejmenším okně (700) tedy sloupec odpadá
    /// vždycky, a to je správně.
    static let findingTableReviewerBreakpoint = 900.0
    /// Nejmenší šířka, ve které je shrnutí ještě věta, ne svislý sloupec slov.
    static let findingTableMinimumSummary = 280.0

    /// Rozdělení šířky mezi sloupce tabulky nálezů.
    static func findingTableLayout(availableWidth: Double) -> FindingTableLayout {
        let showsReviewer = availableWidth >= findingTableReviewerBreakpoint
        let severity = 92.0
        let location = 186.0
        let reviewer = 132.0
        let actions = 112.0

        let columns = showsReviewer ? 6.0 : 5.0
        var fixed = FindingTableLayout.bar + severity + location + actions
        fixed += showsReviewer ? reviewer : 0
        fixed += FindingTableLayout.spacing * (columns - 1) + FindingTableLayout.inset * 2

        return FindingTableLayout(
            severity: severity,
            // Podlaha schválně: v okně, ve kterém i po odpadnutí sloupce nezbývá místo, je lepší
            // nečitelně úzké shrnutí než nulová šířka, ve které by z tabulky zmizel text.
            summary: max(availableWidth - fixed, 120),
            location: location,
            reviewer: showsReviewer ? reviewer : nil,
            actions: actions
        )
    }

    /// Nálezy setříděné podle sloupce, na který se kliklo.
    ///
    /// **Odmítnuté zůstávají naspod, ať se klikne na cokoli** (#113): jsou to nálezy, kterým
    /// nevěřím, takže nemají konkurovat platným ani v cizím řazení. Řadí se proto dvě skupiny zvlášť
    /// a slepí se za sebe — obrácení směru je tím taky nemíchá dohromady.
    static func sorted(
        _ findings: [Finding],
        by sort: FindingTableSort?,
        categories: Set<String> = defaultBlockingCategories,
        dismissals: [FindingKey: FindingDismissal] = [:]
    ) -> [Finding] {
        guard let sort else {
            return sorted(findings, categories: categories, dismissals: dismissals)
        }
        let active = findings.filter { dismissals[key(of: $0)] == nil }
        let dismissed = findings.filter { dismissals[key(of: $0)] != nil }
        return ordered(active, by: sort, categories: categories)
            + ordered(dismissed, by: sort, categories: categories)
    }

    private static func ordered(
        _ findings: [Finding],
        by sort: FindingTableSort,
        categories: Set<String>
    ) -> [Finding] {
        let ascending: [Finding] = switch sort.column {
        // Závažnost si nevymýšlí druhou škálu: vzestupně je **obrácené** `Policy.sorted`, takže
        // sestupně vyjde přesně výchozí pořadí. Dvě různá pravidla pro „co je vážnější“ by
        // znamenala, že tabulka a bubliny mluví každá o něčem jiném.
        case .severity: sorted(findings, categories: categories).reversed()
        case .summary: findings.sorted { compare($0.summary, $1.summary, or: location(of: $0), location(of: $1)) }
        case .location: findings.sorted { locationKey(of: $0) < locationKey(of: $1) }
        case .reviewer: findings.sorted { reviewerKey(of: $0) < reviewerKey(of: $1) }
        }
        return sort.isAscending ? ascending : ascending.reversed()
    }

    /// Texty se porovnávají **podle jazyka** (`localizedStandardCompare`), ne bajtově: je to
    /// řazení, které někdo čte, takže `Čte` má patřit za `Cache`, a `řádek 9` před `řádek 10`.
    /// Poslední slovo má obyčejné `<`, aby bylo pořadí **úplné** — bez něj by dvě shrnutí lišící se
    /// jen velikostí písmen přeskakovala mezi překresleními.
    private static func compare(_ left: String, _ right: String, or leftTie: String, _ rightTie: String) -> Bool {
        switch left.localizedStandardCompare(right) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: leftTie == rightTie ? left < right : leftTie < rightTie
        }
    }

    /// Klíč pro sloupec `místo`. Nálezy bez místa v kódu jdou **dozadu** — tatáž úvaha jako
    /// v `Policy.sorted`, kde patří pod bubliny, ne mezi ně.
    private static func locationKey(of finding: Finding) -> LocationKey {
        LocationKey(
            missing: finding.file == nil,
            file: finding.file ?? "",
            line: finding.line ?? Int.max,
            summary: finding.summary
        )
    }

    private static func reviewerKey(of finding: Finding) -> ReviewerKey {
        ReviewerKey(
            reviewer: finding.reviewer,
            category: finding.category.map(normalized(category:)) ?? "",
            summary: finding.summary
        )
    }

    private static func location(of finding: Finding) -> String {
        guard let file = finding.file else { return "" }
        guard let line = finding.line else { return file }
        return "\(file):\(line)"
    }

    private struct LocationKey: Comparable {
        let missing: Bool
        let file: String
        let line: Int
        let summary: String

        static func < (left: LocationKey, right: LocationKey) -> Bool {
            if left.missing != right.missing { return !left.missing }
            if left.file != right.file { return left.file < right.file }
            if left.line != right.line { return left.line < right.line }
            return left.summary < right.summary
        }
    }

    private struct ReviewerKey: Comparable {
        let reviewer: String
        let category: String
        let summary: String

        static func < (left: ReviewerKey, right: ReviewerKey) -> Bool {
            if left.reviewer != right.reviewer { return left.reviewer < right.reviewer }
            if left.category != right.category { return left.category < right.category }
            return left.summary < right.summary
        }
    }
}
