import Foundation
import Testing

@testable import PRism

/// Řazení tabulky nálezů podle sloupců a rozdělení šířky mezi ně (#242).
@Suite("Policy — tabulka nálezů")
struct FindingTableTests {
    // MARK: - Volba řazení

    @Test("První kliknutí řadí tak, jak se sloupec čte")
    func firstClick() {
        // Závažnost od nejvážnějšího, tedy sestupně — a to je zároveň výchozí pořadí.
        #expect(FindingTableSort.toggled(.severity, from: nil)
            == FindingTableSort(column: .severity, isAscending: false))
        // Text od „a“.
        #expect(FindingTableSort.toggled(.summary, from: nil)
            == FindingTableSort(column: .summary, isAscending: true))
    }

    @Test("Druhé kliknutí na tentýž sloupec otočí směr")
    func secondClick() {
        let first = FindingTableSort.toggled(.location, from: nil)
        let second = FindingTableSort.toggled(.location, from: first)

        #expect(second == FindingTableSort(column: .location, isAscending: false))
    }

    @Test("Kliknutí na jiný sloupec začíná znovu jeho výchozím směrem")
    func otherColumn() {
        let descending = FindingTableSort(column: .summary, isAscending: false)

        #expect(FindingTableSort.toggled(.severity, from: descending)
            == FindingTableSort(column: .severity, isAscending: false))
    }

    // MARK: - Řazení

    @Test("Bez volby platí pořadí z Policy.sorted, tedy podle závažnosti")
    func defaultOrder() {
        let findings = [
            makeFinding(file: "b.php", line: 2, category: "style", summary: "stylistický"),
            makeFinding(file: "a.php", line: 1, category: "correctness", summary: "blokující"),
        ]

        let ordered = Policy.sorted(findings, by: nil)

        #expect(ordered.map(\.summary) == ["blokující", "stylistický"])
    }

    @Test("Závažnost sestupně dá totéž jako výchozí pořadí — druhá škála z toho nevzniká")
    func severityDescendingMatchesDefault() {
        let findings = [
            makeFinding(file: "b.php", line: 2, category: "style", summary: "stylistický"),
            makeFinding(file: "a.php", line: 1, category: "correctness", summary: "blokující"),
            makeFinding(file: "c.php", line: 3, category: "security", summary: "bezpečnostní"),
        ]

        let sorted = Policy.sorted(findings, by: FindingTableSort(column: .severity, isAscending: false))

        #expect(sorted.map(\.summary) == Policy.sorted(findings).map(\.summary))
    }

    @Test("Shrnutí se řadí abecedně a otočením se obrátí")
    func summaryOrder() {
        let findings = [
            makeFinding(file: "a.php", line: 1, summary: "cizí"),
            makeFinding(file: "b.php", line: 2, summary: "ale"),
            makeFinding(file: "c.php", line: 3, summary: "být"),
        ]

        let ascending = Policy.sorted(findings, by: FindingTableSort(column: .summary, isAscending: true))
        let descending = Policy.sorted(findings, by: FindingTableSort(column: .summary, isAscending: false))

        #expect(ascending.map(\.summary) == ["ale", "být", "cizí"])
        #expect(descending.map(\.summary) == ["cizí", "být", "ale"])
    }

    @Test("Místo se řadí podle souboru a čísla řádku, nálezy bez místa jdou dozadu")
    func locationOrder() {
        let findings = [
            makeFinding(file: nil, line: nil, summary: "bez místa"),
            makeFinding(file: "b.php", line: 5, summary: "béčko"),
            makeFinding(file: "a.php", line: 20, summary: "áčko 20"),
            makeFinding(file: "a.php", line: 3, summary: "áčko 3"),
        ]

        let sorted = Policy.sorted(findings, by: FindingTableSort(column: .location, isAscending: true))

        #expect(sorted.map(\.summary) == ["áčko 3", "áčko 20", "béčko", "bez místa"])
    }

    @Test("Reviewer se řadí podle jména, pak podle kategorie")
    func reviewerOrder() {
        let findings = [
            makeFinding(file: "a.php", line: 1, category: "style", summary: "zebra style", reviewer: "zebra"),
            makeFinding(file: "b.php", line: 2, category: "security", summary: "alfa security", reviewer: "alfa"),
            makeFinding(file: "c.php", line: 3, category: "correctness", summary: "alfa correctness", reviewer: "alfa"),
        ]

        let sorted = Policy.sorted(findings, by: FindingTableSort(column: .reviewer, isAscending: true))

        #expect(sorted.map(\.summary) == ["alfa correctness", "alfa security", "zebra style"])
    }

    /// Odmítnuté nálezy patří naspod, **ať se klikne na cokoli** — nález, kterému nevěřím, nemá
    /// konkurovat platným ani v cizím řazení. Bez tohohle by je otočení směru vytáhlo nahoru.
    @Test("Odmítnuté zůstávají naspod v obou směrech", arguments: [true, false])
    func dismissedStayLast(ascending: Bool) {
        let dismissed = makeFinding(file: "a.php", line: 1, summary: "aaa odmítnutý")
        let findings = [
            dismissed,
            makeFinding(file: "b.php", line: 2, summary: "bbb platný"),
            makeFinding(file: "c.php", line: 3, summary: "ccc platný"),
        ]

        let sorted = Policy.sorted(
            findings,
            by: FindingTableSort(column: .summary, isAscending: ascending),
            dismissals: makeDismissals([dismissed])
        )

        #expect(sorted.last?.summary == "aaa odmítnutý")
    }

    // MARK: - Šířky sloupců

    @Test("V širokém okně se vejdou všechny sloupce")
    func wideLayout() {
        let layout = Policy.findingTableLayout(availableWidth: 1200)

        #expect(layout.reviewer != nil)
        #expect(layout.summary >= Policy.findingTableMinimumSummary)
    }

    /// Sloupec `reviewer · kategorie` je jediný, jehož obsah je i v bublině u kódu a v chipech
    /// reviewerů nad diffem — proto odpadá první.
    @Test("V úzkém okně odpadne sloupec reviewera, ne shrnutí")
    func narrowLayout() {
        let layout = Policy.findingTableLayout(availableWidth: 700)

        #expect(layout.reviewer == nil)
        #expect(layout.location > 0)
        #expect(layout.summary > 0)
    }

    @Test("Sloupce se vejdou do dané šířky, ne mimo ni")
    func fitsWidth() {
        for width in [700.0, 900, 1100, 1400] {
            let layout = Policy.findingTableLayout(availableWidth: width)
            let columns = [layout.severity, layout.summary, layout.location, layout.reviewer, layout.actions]
                .compactMap { $0 }
            let total = columns.reduce(FindingTableLayout.bar, +)
                + FindingTableLayout.spacing * Double(columns.count)
                + FindingTableLayout.inset * 2

            #expect(total <= width + 0.5, "šířka \(width) přetekla na \(total)")
        }
    }

    /// Nulová šířka nastane, než `GeometryReader` cokoli změří. Sloupec o nulové šířce by z tabulky
    /// vymazal text — proto podlaha.
    @Test("Nesmyslná šířka nedá nulové shrnutí")
    func zeroWidth() {
        #expect(Policy.findingTableLayout(availableWidth: 0).summary > 0)
    }
}
