import Foundation
import Testing

@testable import PRism

/// Kam v diffu patří bublina nálezu.
@Suite("DiffRow — bubliny nálezů")
struct DiffBubbleTests {
    private func claudeFile() throws -> FileDiff {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
        return try #require(diff.files.first { $0.displayPath == "CLAUDE.md" })
    }

    private func finding(_ file: String?, _ line: Int?, reviewer: String = "code-review") -> Finding {
        Finding(
            reported: ReportedFinding(
                file: file,
                line: line,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: nil,
                summary: "nález na \(file ?? "?"):\(line.map(String.init) ?? "?")",
                failureScenario: "co se stane"
            ),
            reviewer: reviewer,
            headSha: "abc123"
        )
    }

    private func bubbles(_ rows: [DiffRow]) -> [FindingGroup] {
        rows.compactMap { row in
            guard case .finding(_, let group, _) = row else { return nil }
            return group
        }
    }

    /// Bubliny nálezů, které v diffu nemají svůj řádek.
    private func unanchored(_ rows: [DiffRow]) -> [FindingGroup] {
        rows.compactMap { row in
            guard case .finding(_, let group, let anchored) = row, !anchored else { return nil }
            return group
        }
    }

    /// Index řádku, za kterým bublina visí — na tom stojí celé „u kódu, kterého se týká“.
    private func positionOfBubble(in rows: [DiffRow]) -> Int? {
        rows.firstIndex { if case .finding = $0 { true } else { false } }
    }

    @Test("Bublina visí hned pod svým řádkem")
    func putsTheBubbleUnderItsLine() throws {
        let groups = Policy.groups(of: [finding("CLAUDE.md", 174)])

        let rows = DiffRow.rows(of: try claudeFile(), findings: groups)

        let position = try #require(positionOfBubble(in: rows))
        guard case .line(_, let above) = rows[position - 1] else {
            Issue.record("Nad bublinou má být řádek, kterého se týká")
            return
        }
        #expect(above.newNumber == 174)
        #expect(bubbles(rows).count == 1)
    }

    /// Reviewer čte celý pracovní strom, takže hlásí i řádky, které v diffu nejsou.
    /// Schovat takový nález znamená, že ho nikdo neuvidí — visí proto u hlavičky souboru.
    @Test("Nález na řádek mimo diff visí u souboru, ne nikde")
    func keepsAFindingOutsideTheDiffVisible() throws {
        let rows = DiffRow.rows(of: try claudeFile(), findings: Policy.groups(of: [finding("CLAUDE.md", 99999)]))

        #expect(unanchored(rows).count == 1)
        // Před prvním řádkem souboru, ať se na něj narazí hned.
        guard case .finding = rows.first else {
            Issue.record("Nezakotvená bublina patří na začátek souboru, přišlo \(rows.first as Any)")
            return
        }
    }

    @Test("Nález bez řádku visí u souboru")
    func keepsAFindingWithoutALineVisible() throws {
        let rows = DiffRow.rows(of: try claudeFile(), findings: Policy.groups(of: [finding("CLAUDE.md", nil)]))

        #expect(unanchored(rows).count == 1)
    }

    /// Bez pořadí by nezakotvené bubliny poskakovaly mezi překresleními, protože slovník
    /// pořadí nemá.
    @Test("Nezakotvené bubliny jdou po číslech řádků")
    func ordersUnanchoredBubblesByLine() throws {
        let groups = Policy.groups(of: [
            finding("CLAUDE.md", 9000),
            finding("CLAUDE.md", nil),
            finding("CLAUDE.md", 8000),
        ])

        let rows = DiffRow.rows(of: try claudeFile(), findings: groups)

        #expect(unanchored(rows).map(\.line) == [nil, 8000, 9000])
    }

    /// Nálezy bez řádku se schválně neslučují, takže jich k jednomu souboru může být víc.
    /// Se stejným `id` by je `ForEach` nerozeznal a vykreslil by je špatně.
    @Test("Každá bublina má vlastní identitu")
    func givesEveryBubbleItsOwnIdentity() throws {
        let groups = Policy.groups(of: [
            finding("CLAUDE.md", nil, reviewer: "code-review"),
            finding("CLAUDE.md", nil, reviewer: "security"),
            finding("CLAUDE.md", 8000),
            finding("CLAUDE.md", 9000),
        ])

        let rows = DiffRow.rows(of: try claudeFile(), findings: groups)

        #expect(unanchored(rows).count == 4)
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    /// Jakmile se řádek dotáhne rozbalením kontextu (#47), bublina se k němu přesune sama.
    @Test("Po rozbalení kontextu bublina sedne ke svému řádku")
    func anchorsTheBubbleOnceItsLineIsRevealed() throws {
        var revealed = RevealedLines()
        revealed.reveal(100...110)
        let groups = Policy.groups(of: [finding("CLAUDE.md", 105)])

        let hidden = DiffRow.rows(of: try claudeFile(), findings: groups)
        let shown = DiffRow.rows(
            of: try claudeFile(),
            revealed: revealed,
            content: (1...600).map { "řádek \($0)" },
            findings: groups
        )

        #expect(unanchored(hidden).count == 1)
        #expect(unanchored(shown).isEmpty)
        #expect(bubbles(shown).count == 1)
    }

    @Test("Nález z jiného souboru se sem nepřiplete")
    func keepsFindingsOfOtherFilesOut() throws {
        let rows = DiffRow.rows(of: try claudeFile(), findings: Policy.groups(of: [finding("README.md", 174)]))

        #expect(bubbles(rows).isEmpty)
    }

    @Test("Dva reviewery na jednom řádku dají jednu bublinu")
    func mergesReviewersIntoOneBubble() throws {
        let groups = Policy.groups(of: [
            finding("CLAUDE.md", 174, reviewer: "code-review"),
            finding("CLAUDE.md", 174, reviewer: "security"),
        ])

        let rows = DiffRow.rows(of: try claudeFile(), findings: groups)

        #expect(bubbles(rows).count == 1)
        #expect(bubbles(rows).first?.agreement == 2)
        // Texty se neslučují — v bublině jsou oba pod sebou.
        #expect(bubbles(rows).first?.findings.count == 2)
    }

    /// Rozbalený kontext (#47) je taky kód, který je vidět — nález na něm bublinu dostane.
    @Test("Nález na rozbaleném řádku bublinu dostane")
    func putsABubbleOnARevealedLine() throws {
        var revealed = RevealedLines()
        revealed.reveal(100...110)
        let content = (1...600).map { "řádek \($0)" }

        let rows = DiffRow.rows(
            of: try claudeFile(),
            revealed: revealed,
            content: content,
            findings: Policy.groups(of: [finding("CLAUDE.md", 105)])
        )

        let position = try #require(positionOfBubble(in: rows))
        guard case .line(_, let above) = rows[position - 1] else {
            Issue.record("Nad bublinou má být rozbalený řádek")
            return
        }
        #expect(above.newNumber == 105)
        #expect(above.text == "řádek 105")
    }

    @Test("Nález pod starou cestou přejmenovaného souboru bublinu dostane")
    func findsARenamedFileByItsOldPath() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-rename.diff"))
        let file = try #require(diff.files.first { $0.newPath == "App/PRismApp.swift" })
        let line = try #require(file.hunks.first?.lines.first { $0.newNumber != nil }?.newNumber)

        let rows = DiffRow.rows(of: file, findings: Policy.groups(of: [finding("App/PRReviewApp.swift", line)]))

        #expect(bubbles(rows).count == 1)
    }

    @Test("Bez nálezů se nic nemění")
    func changesNothingWithoutFindings() throws {
        let file = try claudeFile()

        #expect(DiffRow.rows(of: file).count == DiffRow.rows(of: file, findings: []).count)
    }
}
