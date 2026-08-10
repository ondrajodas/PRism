import Foundation
import Testing

@testable import PRism

/// Značky u souborů ve stromu (#197).
///
/// Co se dá pokazit potichu: **nechat blokující přebít obyčejným nálezem**. Značka by pak
/// u souboru záležela na pořadí, ve kterém nálezy dorazily — a soubor, kvůli kterému se PR
/// nemerguje, by ve stromu vypadal jako každý jiný.
@Suite("Značky souborů ve stromu")
struct FileMarkerTests {
    private func finding(_ file: String?, category: String? = "style") -> Finding {
        makeFinding(file: file, category: category)
    }

    @Test("Soubor s běžným nálezem dostane obyčejnou značku")
    func marksAPlainFinding() {
        #expect(Policy.fileMarkers(of: [finding("src/A.php")]) == ["src/A.php": .findings])
    }

    @Test("Blokující kategorie dá blokující značku")
    func marksABlockingFinding() {
        #expect(
            Policy.fileMarkers(of: [finding("src/A.php", category: "correctness")])
                == ["src/A.php": .blocking]
        )
    }

    /// **Nejcennější test téhle sady** — a v obou pořadích, protože právě pořadím se to dá
    /// pokazit tak, že si toho nikdo nevšimne.
    @Test("Blokující přebije obyčejný bez ohledu na pořadí")
    func blockingWins() {
        let plain = finding("src/A.php")
        let blocking = finding("src/A.php", category: "correctness")

        #expect(Policy.fileMarkers(of: [plain, blocking]) == ["src/A.php": .blocking])
        #expect(Policy.fileMarkers(of: [blocking, plain]) == ["src/A.php": .blocking])
    }

    /// Nález bez cesty patří celému PR, ne souboru — ve stromu nemá kam.
    @Test("Nález bez souboru se do stromu nedostane")
    func ignoresFindingsWithoutAFile() {
        #expect(Policy.fileMarkers(of: [finding(nil)]).isEmpty)
    }

    @Test("Značky se počítají po souborech")
    func marksEachFileSeparately() {
        let markers = Policy.fileMarkers(of: [
            finding("src/A.php", category: "correctness"),
            finding("src/B.php"),
        ])

        #expect(markers == ["src/A.php": .blocking, "src/B.php": .findings])
    }

    /// Blokující sada se dá přenastavit, takže se musí brát ta předaná — jinak by strom tvrdil
    /// něco jiného než řádek fronty u repa s vlastním nastavením.
    @Test("Blokující kategorie se berou z parametru")
    func honoursTheCategories() {
        let markers = Policy.fileMarkers(
            of: [finding("src/A.php", category: "correctness")],
            categories: []
        )

        #expect(markers == ["src/A.php": .findings])
    }

    @Test("Bez nálezů nejsou žádné značky")
    func handlesNoFindings() {
        #expect(Policy.fileMarkers(of: []).isEmpty)
    }

    // MARK: - Co je v souboru k vyřízení (kapsle v hlavičce, #219)

    private func group(
        _ file: String,
        line: Int,
        categories: [String?],
        dismissed: Bool = false
    ) -> FindingGroup {
        let findings = categories.map { makeFinding(file: file, line: line, category: $0) }
        return FindingGroup(
            file: file,
            line: line,
            findings: findings,
            dismissals: dismissed
                ? Dictionary(
                    uniqueKeysWithValues: findings.map {
                        (Policy.key(of: $0), FindingDismissal(reason: .invalid, dismissedAt: .distantPast))
                    }
                )
                : [:]
        )
    }

    /// **Počítá se po místech, ne po nálezech.** Tři reviewery, kteří se shodli na témž řádku,
    /// jsou jedna věc k rozhodnutí — kapsle `3 blokují` nad jedním místem by lhala o tom, kolik
    /// práce v souboru je.
    @Test("Shoda reviewerů na jednom místě se počítá jednou")
    func countsPlacesNotFindings() {
        let counts = Policy.fileFindings(
            in: [group("src/A.php", line: 1, categories: ["correctness", "correctness", "correctness"])]
        )

        #expect(counts == (blocking: 1, total: 1))
    }

    @Test("Blokující a obyčejná místa se počítají zvlášť")
    func separatesBlockingFromPlain() {
        let counts = Policy.fileFindings(
            in: [
                group("src/A.php", line: 1, categories: ["correctness"]),
                group("src/A.php", line: 2, categories: ["style"]),
                group("src/A.php", line: 3, categories: ["style"]),
            ]
        )

        #expect(counts == (blocking: 1, total: 3))
    }

    /// Místo, ve kterém blokuje aspoň jeden nález, je blokující celé — stejné pravidlo jako
    /// u značky ve stromu.
    @Test("Jeden blokující nález udělá z místa blokující")
    func oneBlockingFindingIsEnough() {
        let counts = Policy.fileFindings(
            in: [group("src/A.php", line: 1, categories: ["style", "correctness"])]
        )

        #expect(counts == (blocking: 1, total: 1))
    }

    /// **Nejcennější test téhle dvojice**: odmítnutý nález (#113) není práce k vyřízení, takže
    /// se kapsle nesmí ukázat vůbec — jinak by u sbaleného souboru svítila červeně nad něčím,
    /// co jsem už posoudil.
    @Test("Odmítnuté nálezy se nepočítají")
    func ignoresDismissed() {
        let counts = Policy.fileFindings(
            in: [group("src/A.php", line: 1, categories: ["correctness"], dismissed: true)]
        )

        #expect(counts == (blocking: 0, total: 0))
    }

    @Test("Blokující kategorie se berou z parametru i tady")
    func fileFindingsHonoursTheCategories() {
        let groups = [group("src/A.php", line: 1, categories: ["correctness"])]

        #expect(Policy.fileFindings(in: groups, categories: []) == (blocking: 0, total: 1))
    }
}
