import Foundation
import Testing

@testable import PRism

/// Skryté úseky mezi hunky a jejich rozbalování.
@Suite("DiffRow — rozbalení kontextu")
struct DiffExpanderTests {
    private func claudeFile() throws -> FileDiff {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
        return try #require(diff.files.first { $0.displayPath == "CLAUDE.md" })
    }

    private func expanders(_ rows: [DiffRow]) -> [DiffExpander] {
        rows.compactMap { row in
            guard case .expander(_, let expander) = row else { return nil }
            return expander
        }
    }

    /// Malý diff, u kterého se dá vypsat i obsah souboru.
    private let smallDiff = """
        diff --git a/x.txt b/x.txt
        --- a/x.txt
        +++ b/x.txt
        @@ -3,1 +3,1 @@
        -třetí starý
        +třetí nový
        """
    private let smallContent = ["první", "druhý", "třetí nový", "čtvrtý", "pátý"]

    private func smallFile() throws -> FileDiff {
        try #require(DiffParser.parse(smallDiff).files.first)
    }

    // MARK: - Kde skryté úseky jsou

    @Test("Nad prvním hunkem je rozbalovací řádek")
    func offersExpansionAboveTheFirstHunk() throws {
        let rows = DiffRow.rows(of: try claudeFile())

        let first = try #require(expanders(rows).first)
        #expect(first.firstLine == 1)
        #expect(first.lastLine == 170)   // první hunk začíná na 171
        #expect(first.shift == 0)
    }

    /// Mezi hunky se stará a nová čísla rozejdou o to, co nadělal předchozí hunk — a bez
    /// toho posunu by rozbalený řádek ukazoval cizí staré číslo.
    @Test("Mezi hunky je rozbalovací řádek s posunem starých čísel")
    func offersExpansionBetweenHunksWithAShift() throws {
        let rows = DiffRow.rows(of: try claudeFile())

        let between = expanders(rows)[1]
        #expect(between.firstLine == 185)   // první hunk končí na 184
        #expect(between.lastLine == 542)    // druhý začíná na 543
        #expect(between.shift == 6)         // +14 řádků nových proti 8 starým
    }

    @Test("Za posledním hunkem je rozbalovací řádek s neznámým koncem")
    func offersExpansionAfterTheLastHunkWithoutKnowingTheEnd() throws {
        // Kde soubor končí, se z diffu vyčíst nedá — dozvíme se to teprve z jeho obsahu.
        let rows = DiffRow.rows(of: try claudeFile())
        let last = try #require(expanders(rows).last)

        #expect(last.lastLine == nil)
        #expect(last.hiddenCount == nil)
    }

    @Test("Konec souboru se doplní, jakmile je obsah načtený")
    func learnsTheEndOfTheFileFromItsContent() throws {
        let rows = DiffRow.rows(of: try smallFile(), content: smallContent)

        let last = try #require(expanders(rows).last)
        #expect(last.firstLine == 4)
        #expect(last.lastLine == 5)
        #expect(last.hiddenCount == 2)
    }

    @Test("Hunk od prvního řádku nemá nad sebou co rozbalovat")
    func offersNothingAboveAHunkThatStartsAtTheTop() throws {
        let file = try #require(DiffParser.parse("""
            diff --git a/x.txt b/x.txt
            --- a/x.txt
            +++ b/x.txt
            @@ -1,1 +1,1 @@
            -starý
            +nový
            """).files.first)

        #expect(expanders(DiffRow.rows(of: file)).allSatisfy { $0.firstLine > 1 })
    }

    @Test("Smazaný soubor rozbalovat nejde")
    func neverOffersExpansionForADeletedFile() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-deleted.diff"))
        let file = try #require(diff.files.first)

        // Nový obsah neexistuje, takže není co dotáhnout.
        #expect(expanders(DiffRow.rows(of: file)).isEmpty)
    }

    @Test("Binární soubor rozbalovat nejde")
    func neverOffersExpansionForABinaryFile() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-binary.diff"))
        // `first(where:)` je `rethrows` a makro `#require` si s tím uvnitř neporadí,
        // takže se hledá zvlášť.
        let binary = diff.files.first { $0.isBinary }
        let file = try #require(binary)

        #expect(expanders(DiffRow.rows(of: file)).isEmpty)
    }

    // MARK: - Rozbalené řádky

    @Test("Rozbalený řádek je kontext s oběma čísly")
    func showsRevealedLinesAsContext() throws {
        var revealed = RevealedLines()
        revealed.reveal(1...2)

        let rows = DiffRow.rows(of: try smallFile(), revealed: revealed, content: smallContent)

        guard case .line(_, let first) = rows[0], case .line(_, let second) = rows[1] else {
            Issue.record("Čekal jsem dva rozbalené řádky na začátku")
            return
        }
        #expect(first == DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "první"))
        #expect(second == DiffLine(kind: .context, oldNumber: 2, newNumber: 2, text: "druhý"))
    }

    @Test("Rozbalený úsek už rozbalovací řádek nemá")
    func dropsTheExpanderOnceTheGapIsRevealed() throws {
        var revealed = RevealedLines()
        revealed.reveal(1...2)

        let rows = DiffRow.rows(of: try smallFile(), revealed: revealed, content: smallContent)

        #expect(expanders(rows).allSatisfy { $0.firstLine > 2 })
    }

    @Test("Odkrytí uprostřed nechá rozbalovací řádky po obou stranách")
    func keepsExpandersOnBothSidesOfARevealedMiddle() throws {
        var revealed = RevealedLines()
        revealed.reveal(100...110)

        let rows = DiffRow.rows(
            of: try claudeFile(),
            revealed: revealed,
            content: (1...600).map { "řádek \($0)" }
        )

        let leading = expanders(rows).prefix(2)
        #expect(leading.map(\.firstLine) == [1, 111])
        #expect(leading.map(\.lastLine) == [99, 170])
    }

    /// Dokud obsah nedorazí, není co ukázat — a kdyby se úsek tvářil jako odkrytý,
    /// zmizel by rozbalovací řádek i se spinnerem a zůstalo by prázdno.
    @Test("Bez načteného obsahu zůstává úsek skrytý")
    func keepsTheGapHiddenUntilTheContentArrives() throws {
        var revealed = RevealedLines()
        revealed.reveal(1...170)

        let rows = DiffRow.rows(of: try claudeFile(), revealed: revealed, content: [])

        #expect(expanders(rows).first?.firstLine == 1)
        #expect(expanders(rows).first?.lastLine == 170)
    }

    // MARK: - Slití hunků

    private func hunkHeaders(_ rows: [DiffRow]) -> [String] {
        rows.compactMap { row in
            guard case .hunk(_, let hunk) = row else { return nil }
            return hunk.header
        }
    }

    /// Když se mezera rozbalí celá, jdou řádky nepřetržitě za sebou a hlavička uprostřed
    /// nemá co oddělovat — jen mate.
    @Test("Rozbalená mezera slije hunky a hlavička mezi nimi zmizí")
    func dropsTheHunkHeaderWhenTheGapAboveIsFullyRevealed() throws {
        var revealed = RevealedLines()
        revealed.reveal(185...542)   // celá mezera mezi prvním a druhým hunkem

        let rows = DiffRow.rows(
            of: try claudeFile(),
            revealed: revealed,
            content: (1...600).map { "řádek \($0)" }
        )

        #expect(!hunkHeaders(rows).contains("@@ -537,9 +543,9 @@"))
        #expect(hunkHeaders(rows).contains("@@ -171,8 +171,14 @@"))
    }

    @Test("Dokud je v mezeře co skrývat, hlavička zůstane")
    func keepsTheHunkHeaderWhileSomethingIsStillHidden() throws {
        var revealed = RevealedLines()
        revealed.reveal(185...541)   // o jeden řádek míň než celá mezera

        let rows = DiffRow.rows(
            of: try claudeFile(),
            revealed: revealed,
            content: (1...600).map { "řádek \($0)" }
        )

        #expect(hunkHeaders(rows).contains("@@ -537,9 +543,9 @@"))
    }

    @Test("Rozbalení až na začátek souboru sundá i hlavičku prvního hunku")
    func dropsTheFirstHunkHeaderWhenRevealedToTheTopOfTheFile() throws {
        var revealed = RevealedLines()
        revealed.reveal(1...170)

        let rows = DiffRow.rows(
            of: try claudeFile(),
            revealed: revealed,
            content: (1...600).map { "řádek \($0)" }
        )

        #expect(!hunkHeaders(rows).contains("@@ -171,8 +171,14 @@"))
    }

    /// Hunk, nad kterým žádná mezera nebyla, se s ničím neslil — hlavička je pořád
    /// jediné, z čeho se pozná, kde v souboru jsme.
    @Test("Hunk bez mezery nad sebou si hlavičku nechá")
    func keepsTheHeaderOfAHunkThatNeverHadAGapAboveIt() throws {
        let file = try #require(DiffParser.parse("""
            diff --git a/x.txt b/x.txt
            --- a/x.txt
            +++ b/x.txt
            @@ -1,1 +1,1 @@
            -starý
            +nový
            """).files.first)

        #expect(hunkHeaders(DiffRow.rows(of: file, content: ["nový"])) == ["@@ -1,1 +1,1 @@"])
    }

    /// Kotva pro skok z nálezu se počítá bez rozbalených řádků, ale platit musí i s nimi —
    /// jinak by odkaz po rozbalení ukázal jinam nebo nikam.
    @Test("Kotva na řádek platí i po rozbalení kontextu")
    func keepsTheAnchorValidAfterExpansion() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
        let file = try claudeFile()
        var revealed = RevealedLines()
        revealed.reveal(1...170)

        let anchor = try #require(DiffRow.anchor(in: diff, file: "CLAUDE.md", line: 174))
        let rows = DiffRow.rows(of: file, revealed: revealed, content: (1...600).map { "řádek \($0)" })

        #expect(rows.contains { $0.id == anchor })
    }
}
