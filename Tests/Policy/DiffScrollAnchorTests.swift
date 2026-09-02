import Foundation
import Testing

@testable import PRism

/// Kotva scrollu jako **soubor a řádek** (#527).
///
/// Nejcennější tvrzení sady je to, že se **nikdy nevrátí řádek nad horní hranou**: kotva má
/// ukazovat na kód, který byl vidět, a řádek nad hranou vypadá stejně platně jako ten správný —
/// po restartu by se výřez posadil o kus výš a nikdo by nepoznal, že je to chyba a ne
/// zaokrouhlení.
@Suite("Policy — kotva scrollu v diffu (#527)")
struct DiffScrollAnchorTests {
    private func row(_ line: Int, _ from: Double, _ to: Double) -> DiffScrollRow {
        DiffScrollRow(extent: from...to, line: line)
    }

    // MARK: - Který řádek drží hranu

    @Test("Řádek, který hranu protíná, vyhrává")
    func theCoveringRowWins() {
        let rows = [row(10, 0, 20), row(11, 20, 40), row(12, 40, 60)]

        #expect(Policy.line(at: 25, in: rows) == 11)
        #expect(Policy.line(at: 45, in: rows) == 12)
        // Na hranici vyhrává **ten dolní**: horní hrana výřezu na `20` znamená, že řádek 10 je
        // celý nad ní a vidět je 11.
        #expect(Policy.line(at: 20, in: rows) == 11)
    }

    @Test("Když hranu neprotíná nic, bere se první řádek pod ní")
    func theRowBelowIsTheFallback() {
        // Díra mezi 20 a 40 je normální stav: mezi bloky jsou hlavičky, expandery a bubliny,
        // a ty číslo řádku nenesou.
        let rows = [row(10, 0, 20), row(30, 40, 60), row(31, 60, 80)]

        #expect(Policy.line(at: 25, in: rows) == 30)
        // Nad prvním řádkem (hlavička souboru) taky: kotva má ukázat na první vidět řádek.
        #expect(Policy.line(at: -100, in: rows) == 10)
    }

    /// **Nikdy řádek nad hranou.** Když jsou bloky pod výřezem odpojené (jsou mimo pás, #469),
    /// je správná odpověď „nevím“ — soubor sám je pořád pojmenovaný, takže se přistane na jeho
    /// hlavičce. Vrátit poslední přeměřený řádek by znamenalo skok o kus výš.
    @Test("Pod posledním přeměřeným řádkem se nevrací nic")
    func nothingIsGuessedFromAbove() {
        let rows = [row(10, 0, 20), row(11, 20, 40)]

        #expect(Policy.line(at: 200, in: rows) == nil)
        #expect(Policy.line(at: 41, in: rows) == nil)
    }

    @Test("Bez přeměřených řádků se nevrací nic")
    func noRowsMeanNoLine() {
        #expect(Policy.line(at: 0, in: []) == nil)
    }

    @Test("Pořadí v poli nerozhoduje — krabice ploch je slovník")
    func theOrderOfRowsDoesNotMatter() {
        let ordered = [row(10, 0, 20), row(11, 20, 40), row(12, 40, 60)]

        #expect(Policy.line(at: 25, in: ordered.reversed()) == 11)
        #expect(Policy.line(at: 25, in: ordered.shuffled()) == 11)
    }

    // MARK: - Soubor a řádek dohromady

    private let files = ["a.swift", "b.swift", "c.swift"]
    private let extents: [ClosedRange<Double>] = [0...100, 100...200, 200...300]

    private func anchor(at top: Double, rows: [String: [DiffScrollRow]] = [:]) -> DiffScrollAnchor? {
        Policy.diffScrollAnchor(
            top: top,
            files: files,
            extents: extents,
            rows: { file, _ in rows[file] ?? [] }
        )
    }

    @Test("Soubor se bere z rozsahů, řádek z jeho ploch")
    func theFileComesFromExtents() {
        let rows = ["b.swift": [row(40, 100, 120), row(41, 120, 140)]]

        #expect(anchor(at: 130, rows: rows) == DiffScrollAnchor(file: "b.swift", line: 41))
        #expect(anchor(at: 100, rows: rows) == DiffScrollAnchor(file: "b.swift", line: 40))
    }

    /// **Soubor bez řádku je platná odpověď**, ne chyba: přistane se na jeho hlavičce, což je
    /// pořád blíž než začátek diffu. Nastane to u binárky, u přejmenování beze změny obsahu
    /// a u souboru, jehož bloky jsou zrovna odpojené.
    @Test("Soubor bez přeměřených řádků vydá kotvu bez čísla")
    func aFileWithoutRowsStillAnchors() {
        #expect(anchor(at: 250) == DiffScrollAnchor(file: "c.swift", line: nil))
    }

    /// Řádky se hledají **jen v rozsahu toho souboru**, který hranu drží — jinak by kotva
    /// spárovala soubor s číslem řádku z toho následujícího a skok by přistál mimo.
    @Test("Řádek se nebere z cizího souboru")
    func rowsAreScopedToTheFile() {
        // `rows` odpovídá jen na `a.swift`; hranu drží `b.swift`, takže číslo nemá odkud vzít.
        let rows = ["a.swift": [row(1, 0, 20)]]

        #expect(anchor(at: 150, rows: rows) == DiffScrollAnchor(file: "b.swift", line: nil))
    }

    /// `DiffFileExtents.ordered(of:)` vrací **prázdno**, dokud chybí jediný rozsah — díra
    /// uprostřed by znamenala, že se u horní hrany drží soubor, který je jinde.
    @Test("Dokud se rozsahy nezměří, není kotva")
    func unmeasuredExtentsGiveNothing() {
        #expect(
            Policy.diffScrollAnchor(top: 50, files: files, extents: [], rows: { _, _ in [] }) == nil
        )
        // A nesourodá délka polí taky ne — je to programátorská chyba, ne stav, o kterém by se
        // mělo hádat.
        #expect(
            Policy.diffScrollAnchor(top: 50, files: files, extents: [0...100], rows: { _, _ in [] })
                == nil
        )
    }

    @Test("Nad prvním souborem se kotva nedělá")
    func aboveTheFirstFileThereIsNoAnchor() {
        #expect(anchor(at: -10) == nil)
    }

    @Test("Prázdný diff kotvu nemá")
    func anEmptyDiffHasNoAnchor() {
        #expect(
            Policy.diffScrollAnchor(top: 0, files: [], extents: [], rows: { _, _ in [] }) == nil
        )
    }
}
