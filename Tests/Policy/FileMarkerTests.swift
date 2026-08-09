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
}
