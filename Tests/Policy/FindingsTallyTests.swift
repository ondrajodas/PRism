import Foundation
import Testing

@testable import PRism

/// Součty nad nálezy a odznak na záložce `Nálezy` (#242).
///
/// Nejcennější je tady ten poslední test: hlídá, že **odznak, tabulka a bubliny v diffu počítají
/// totéž**. Rozejdou se potichu — každé z těch tří míst si počet umí spočítat samo a nikdo si
/// nevšimne, že odznak tvrdí pět a v tabulce jsou čtyři řádky.
@Suite("Policy — součty nálezů")
struct FindingsTallyTests {
    @Test("Prázdný seznam nedá odznak — nula by tvrdila, že se počítalo a vyšlo prázdno")
    func emptyHasNoBadge() {
        let tally = Policy.tally(of: [])

        #expect(tally.isEmpty)
        #expect(Policy.findingsBadge(of: tally) == nil)
    }

    @Test("Blokující nález obarví odznak, ale počet zůstane celkový")
    func blockingBadge() {
        let findings = [
            makeFinding(file: "a.php", line: 1, category: "correctness"),
            makeFinding(file: "b.php", line: 2, category: "style"),
        ]

        let tally = Policy.tally(of: findings)

        #expect(tally == FindingsTally(total: 2, blocking: 1, dismissed: 0))
        #expect(Policy.findingsBadge(of: tally) == .blocking(2))
    }

    @Test("Bez blokujícího je odznak tichý")
    func neutralBadge() {
        let tally = Policy.tally(of: [makeFinding(file: "a.php", line: 1, category: "style")])

        #expect(Policy.findingsBadge(of: tally) == .count(1))
    }

    /// Odmítnutý blokující nález **neblokuje** — PR na něm právě proto nestojí. Kdyby se počítal,
    /// zůstal by odznak červený i po vyřízení všech nálezů.
    @Test("Odmítnutý blokující nález odznak neobarví, ale z počtu nezmizí")
    func dismissedDoesNotBlock() {
        let blocking = makeFinding(file: "a.php", line: 1, category: "correctness")
        let findings = [blocking, makeFinding(file: "b.php", line: 2, category: "style")]

        let tally = Policy.tally(of: findings, dismissals: makeDismissals([blocking]))

        #expect(tally == FindingsTally(total: 2, blocking: 0, dismissed: 1))
        #expect(Policy.findingsBadge(of: tally) == .count(2))
    }

    /// Tři místa, jeden počet. Shoda dvou reviewerů je **jeden řádek tabulky a dvě položky
    /// v bublině**, takže se to musí porovnávat po nálezech, ne po řádcích — a právě proto to
    /// tenhle test dělá výslovně.
    @Test("Odznak, tabulka a bubliny počítají tytéž nálezy")
    func badgeMatchesTableAndBubbles() {
        let findings = [
            makeFinding(file: "a.php", line: 10, category: "correctness", reviewer: "php-review"),
            // Shoda na tomtéž místě — v tabulce jeden řádek, v bublině dvě položky.
            makeFinding(file: "a.php", line: 10, category: "correctness", reviewer: "security"),
            makeFinding(file: "b.php", line: 2, category: "style", reviewer: "php-review"),
            makeFinding(file: nil, line: nil, category: "test-coverage", reviewer: "tests"),
        ]
        let dismissals = makeDismissals([findings[2]])

        let tally = Policy.tally(of: findings, dismissals: dismissals)
        let rows = FindingTableRow.rows(of: findings, sort: nil, dismissals: dismissals)
        let bubbles = Policy.groups(of: findings, dismissals: dismissals)

        #expect(tally.total == 4)
        #expect(rows.count == 3)
        #expect(rows.reduce(0) { $0 + $1.findings.count } == tally.total)
        #expect(bubbles.reduce(0) { $0 + $1.findings.count } == tally.total)
        // A odznak nese právě tohle číslo, ne počet řádků.
        #expect(Policy.findingsBadge(of: tally) == .blocking(4))
    }

    /// Řazení ani filtr nesmí počet měnit — jinak by odznak po kliknutí na hlavičku sloupce
    /// ukázal něco jiného než před ním.
    @Test("Setřídění nemění, kolik řádků a nálezů z nich vyjde", arguments: [
        FindingTableSort(column: .severity, isAscending: true),
        FindingTableSort(column: .summary, isAscending: false),
        FindingTableSort(column: .location, isAscending: true),
        FindingTableSort(column: .reviewer, isAscending: false),
    ])
    func sortingKeepsCounts(sort: FindingTableSort) {
        let findings = [
            makeFinding(file: "a.php", line: 10, summary: "první", reviewer: "php-review"),
            makeFinding(file: "a.php", line: 10, summary: "druhý", reviewer: "security"),
            makeFinding(file: "b.php", line: 2, category: "style", summary: "třetí"),
            makeFinding(file: nil, line: nil, category: "docs", summary: "čtvrtý"),
        ]

        let rows = FindingTableRow.rows(of: findings, sort: sort)

        #expect(rows.count == 3)
        #expect(rows.reduce(0) { $0 + $1.findings.count } == findings.count)
    }
}
