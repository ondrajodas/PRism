import Foundation
import Testing

@testable import PRism

/// Rozsah řádků u rozdělaného komentáře (#110). Čisté funkce, nic se nemockuje.
///
/// Pravidla jsou GitHubova a **změřená** proti sandboxu (viz `docs/github-review-api.md`, bod 8):
/// oba konce musí ležet v nějakém hunku, ale nemusí být ve stejném; pořadí se hlídá jen na téže
/// straně. Odsud vychází i to, proč se konce řadí podle **pořadí v diffu**, ne podle čísel.
@Suite("Policy — rozsah komentáře")
struct DraftRangeTests {
    // MARK: - Pomocníci

    /// Soubor se **dvěma** hunky: nové řádky 5–7 a 20–22. Mezi nimi je mezera, která v diffu
    /// vůbec není — přesně to, co GitHub u rozsahu dovolí přeskočit.
    private func file() throws -> FileDiff {
        let diff = DiffParser.parse("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -5,3 +5,3 @@
             první kontext
            -staré páté
            +nové páté
             druhý kontext
            @@ -20,3 +20,3 @@
             třetí kontext
            -staré dvacáté
            +nové dvacáté
             čtvrtý kontext
            """)
        return try #require(diff.files.first)
    }

    private func anchor(_ line: Int, _ side: DiffSide = .right) -> DraftAnchor {
        DraftAnchor(line: line, side: side)
    }

    private func endpoint(_ line: Int, _ side: DiffSide = .right) -> DraftAnchor.Endpoint {
        DraftAnchor.Endpoint(line: line, side: side)
    }

    private func comment(_ anchor: DraftAnchor, path: String = "Cart.php") -> ReviewDraftComment {
        ReviewDraftComment(path: path, anchor: anchor, body: "tenhle blok", origin: .own)
    }

    // MARK: - Skládání rozsahu

    @Test("Dva konce na jedné straně dají rozsah")
    func buildsARangeOnOneSide() throws {
        let range = try #require(Policy.commentRange(from: endpoint(5), to: endpoint(7), in: try file()))

        #expect(range.start == DraftAnchor.Endpoint(line: 5, side: .right))
        #expect(range.line == 7)
        #expect(range.side == .right)
    }

    /// Kliknout se dá i odzadu — ⇧ klik nad prvním komentářem je legitimní gesto. Rozhoduje
    /// pořadí v diffu, ne pořadí kliknutí: na jedné straně by `start_line > line` skončilo
    /// `422 Start position could not be resolved` (změřeno #110).
    @Test("Konce se seřadí podle pořadí v diffu, ne podle kliknutí")
    func sortsTheEndpointsByDiffOrder() throws {
        let range = try #require(Policy.commentRange(from: endpoint(7), to: endpoint(5), in: try file()))

        #expect(range.start?.line == 5)
        #expect(range.line == 7)
    }

    /// Rozsah délky 1 by GitHub přijal, ale byla by to druhá podoba jednořádkového komentáře —
    /// a v payloadu by přibyla dvě pole, která u #62 a #67 neprošla, protože tam nebyla.
    @Test("Oba konce na jednom řádku dají jednořádkový komentář")
    func collapsesARangeOfOneLine() throws {
        let range = try #require(Policy.commentRange(from: endpoint(6), to: endpoint(6), in: try file()))

        #expect(range.start == nil)
        #expect(range.line == 6)
        #expect(!range.isRange)
    }

    /// Kontextový řádek unese obě strany (#98), takže se na jeden řádek dá kliknout vlevo
    /// i vpravo. Rozsah z toho být nemá — je to jeden řádek.
    @Test("Dvě strany téhož řádku nedají rozsah")
    func collapsesBothSidesOfOneLine() throws {
        let range = try #require(Policy.commentRange(from: endpoint(5, .left), to: endpoint(5), in: try file()))

        #expect(range.start == nil)
        #expect(range.line == 5)
    }

    /// **Změřeno u #110:** rozsah smí přeskočit mezeru mezi hunky, protože GitHub kontroluje
    /// každý konec zvlášť. Tažení přes mezeru je legitimní gesto, takže se nesmí zakazovat.
    @Test("Rozsah smí přeskočit mezeru mezi hunky")
    func spansTheGapBetweenHunks() throws {
        let range = try #require(Policy.commentRange(from: endpoint(5), to: endpoint(22), in: try file()))

        #expect(range.start?.line == 5)
        #expect(range.line == 22)
    }

    /// Konce se řadí podle **pořadí v diffu**, takže rozsah přes obě strany klidně vyjde
    /// s klesajícími čísly — GitHub napříč stranami nekontroluje nic (změřeno #110).
    @Test("Rozsah přes obě strany drží pořadí diffu, i když čísla klesají")
    func keepsDiffOrderAcrossSides() throws {
        let file = try file()
        // Odebraný řádek 6 (starý) stojí v diffu **před** přidaným 6 (nový). Rozsah tedy
        // začíná vlevo a končí vpravo, i kdyby se čísla rovnala nebo klesala.
        let range = try #require(Policy.commentRange(from: endpoint(6, .left), to: endpoint(20), in: file))

        #expect(range.start == DraftAnchor.Endpoint(line: 6, side: .left))
        #expect(range.side == .right)
        #expect(range.line == 20)
    }

    @Test("Konec mimo diff rozsah nedá")
    func refusesAnEndpointOutsideTheDiff() throws {
        #expect(Policy.commentRange(from: endpoint(5), to: endpoint(99), in: try file()) == nil)
        #expect(Policy.commentRange(from: endpoint(99), to: endpoint(5), in: try file()) == nil)
    }

    // MARK: - Pokryté řádky

    @Test("Rozsah pokrývá oba konce i řádky mezi nimi")
    func coversTheWholeRange() throws {
        let file = try file()
        let range = try #require(Policy.commentRange(from: endpoint(5), to: endpoint(7), in: file))

        let lines = Policy.rangeLines(of: comment(range), in: file)

        #expect(lines.count == 4, "5, odebraný 6, přidaný 6 a 7")
        #expect(lines.contains { $0.newNumber == 5 })
        #expect(lines.contains { $0.newNumber == 7 })
        #expect(lines.contains { $0.kind == .removed })
    }

    @Test("Jednořádkový komentář nepokrývá nic")
    func coversNothingForASingleLine() throws {
        #expect(Policy.rangeLines(of: comment(anchor(6)), in: try file()).isEmpty)
    }

    /// Mezera mezi hunky v diffu není, takže se ani nemá co zvýraznit — pokrytí je po
    /// **kreslených** řádcích, ne po číslech souboru.
    @Test("Rozsah přes mezeru pokrývá jen to, co je v diffu")
    func coversOnlyRenderedLines() throws {
        let file = try file()
        let range = try #require(Policy.commentRange(from: endpoint(7), to: endpoint(20), in: file))

        let lines = Policy.rangeLines(of: comment(range), in: file)

        #expect(lines.count == 2, "7 a 20 — mezi nimi v diffu nic není")
    }

    @Test("Rozsahy se sbírají přes všechny komentáře souboru")
    func collectsRangesOfEveryComment() throws {
        let file = try file()
        let first = try #require(Policy.commentRange(from: endpoint(5), to: endpoint(6), in: file))
        let second = try #require(Policy.commentRange(from: endpoint(20), to: endpoint(22), in: file))

        let cells = Policy.commentRangeCells(
            of: [comment(first), comment(second), comment(anchor(7)), comment(anchor(5), path: "Jinde.php")],
            in: file
        )

        #expect(cells.contains(endpoint(5)))
        #expect(cells.contains(endpoint(22)))
        #expect(!cells.contains(endpoint(7)), "jednořádkový komentář rozsah nemá")
    }

    // MARK: - Pokrytí po stranách

    /// **Nahlášené při zkoušení #110:** ve split pohledu se zvýrazňoval levý i pravý sloupec.
    /// Kontextový řádek stojí na obou stranách jako tatáž hodnota, takže pokrytí po **řádcích**
    /// bralo obě buňky — rozsah tažený vpravo ale do levého sloupce nepatří.
    @Test("Rozsah na jedné straně pokrývá jen svůj sloupec")
    func coversOnlyItsOwnSide() throws {
        let file = try file()
        let range = try #require(Policy.commentRange(from: endpoint(5), to: endpoint(7), in: file))

        let cells = Policy.rangeCells(of: range, in: file)

        #expect(cells.contains(endpoint(5)))
        #expect(cells.contains(endpoint(7)))
        #expect(!cells.contains(endpoint(5, .left)), "levý sloupec do rozsahu vpravo nepatří")
        #expect(!cells.contains(endpoint(7, .left)))
    }

    /// Rozsah přes obě strany do obou sloupců patří doopravdy, takže se zvýrazní oba.
    @Test("Rozsah přes obě strany pokrývá oba sloupce")
    func coversBothSidesOfAMixedRange() throws {
        let file = try file()
        let range = try #require(Policy.commentRange(from: endpoint(6, .left), to: endpoint(7), in: file))

        let cells = Policy.rangeCells(of: range, in: file)

        #expect(cells.contains(endpoint(6, .left)))
        #expect(cells.contains(endpoint(7)))
    }

    // MARK: - Text místa

    @Test("Jednořádkový komentář se píše jako číslo")
    func writesASingleLine() {
        #expect(Policy.location(of: comment(anchor(26))) == "Cart.php:26")
        #expect(Policy.location(of: comment(anchor(26, .left))) == "Cart.php:26 (starý)")
    }

    @Test("Rozsah se píše s pomlčkou")
    func writesARange() {
        let range = DraftAnchor(line: 31, side: .right, start: DraftAnchor.Endpoint(line: 26, side: .right))
        let old = DraftAnchor(line: 31, side: .left, start: DraftAnchor.Endpoint(line: 26, side: .left))

        #expect(Policy.location(of: comment(range)) == "Cart.php:26–31")
        #expect(Policy.location(of: comment(old)) == "Cart.php:26–31 (staré)")
    }

    /// U rozsahu přes obě strany musí být strany u **obou** čísel: `6–5` by vypadalo jako chyba.
    @Test("Rozsah přes obě strany píše strany u obou čísel")
    func writesAMixedRange() {
        let mixed = DraftAnchor(line: 5, side: .right, start: DraftAnchor.Endpoint(line: 6, side: .left))

        #expect(Policy.location(of: comment(mixed)) == "Cart.php:6 (starý)–5 (nový)")
    }

    /// Bublina u kódu už ví, ve kterém souboru je, takže cestu neopakuje.
    @Test("Text pro bublinu je bez cesty")
    func writesLinesWithoutThePath() {
        let range = DraftAnchor(line: 31, side: .right, start: DraftAnchor.Endpoint(line: 26, side: .right))

        #expect(Policy.lines(of: comment(range)) == "26–31")
        #expect(Policy.lines(of: comment(anchor(26))) == "26")
    }

    // MARK: - Víc komentářů na jednom místě

    /// Panel hlásí, kolik míst má víc komentářů, protože z každého vznikne samostatné vlákno.
    /// Rozsah je součást místa: `26` a `20–26` míří jinam, i když končí stejně.
    @Test("Stejný rozsah se počítá jako jedno místo, jiný rozsah ne")
    func countsRangesAsPartOfThePlace() {
        let range = DraftAnchor(line: 26, side: .right, start: DraftAnchor.Endpoint(line: 20, side: .right))
        let pr = PRIdentifier("cli/cli#42")!

        func draft(_ comments: [ReviewDraftComment]) -> ReviewDraft {
            ReviewDraft(pullRequest: pr, headSha: "abc123", comments: comments)
        }

        #expect(Policy.linesWithSeveralComments(in: draft([comment(range), comment(range)])) == 1)
        #expect(Policy.linesWithSeveralComments(in: draft([comment(range), comment(anchor(26))])) == 0)
    }
}
