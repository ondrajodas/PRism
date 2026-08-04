import Foundation
import Testing

@testable import PRism

/// Bubliny a kotvy v pohledu **vedle sebe**. Všechno, co diff umí pod sebou, musí umět
/// i vedle sebe — nález, který se ve split pohledu nemá kde ukázat, vypadá jako čistý PR.
@Suite("Split pohled — bubliny a kotvy")
struct SplitBubbleTests {
    // MARK: - Pomocníci

    /// Hunk s novými řádky 25–27: 25 kontext, 26 přepsaný (`-staré` / `+nové`), 27 kontext.
    private func diff(path: String = "Cart.php") -> Diff {
        DiffParser.parse("""
            diff --git a/\(path) b/\(path)
            --- a/\(path)
            +++ b/\(path)
            @@ -25,3 +25,3 @@
             kontext
            -staré
            +nové
             další
            """)
    }

    private func file(path: String = "Cart.php") throws -> FileDiff {
        try #require(diff(path: path).files.first)
    }

    private func finding(_ path: String?, _ line: Int?, reviewer: String = "code-review") -> Finding {
        Finding(
            reported: ReportedFinding(
                file: path,
                line: line,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: nil,
                summary: "nález na \(path ?? "?"):\(line.map(String.init) ?? "?")",
                failureScenario: "co se stane"
            ),
            reviewer: reviewer,
            headSha: "abc123"
        )
    }

    private func thread(id: String = "t1", line: Int?, side: DiffSide? = .right) -> ReviewThread {
        let comment = ThreadComment(
            id: "c1",
            author: "kolega",
            body: "co to tady dělá",
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            url: URL(string: "https://github.com/o/r/pull/1#discussion_c1")!
        )
        return ReviewThread(
            id: id,
            path: "Cart.php",
            line: line,
            originalLine: line,
            side: side,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: [comment], total: 1, hasNextPage: false)
        )
    }

    /// Řádky, které nese dvojice (nebo řádek) nad bublinou — podle nich se pozná, že bublina
    /// visí na svém místě.
    private func linesAboveBubble(in rows: [DiffRow]) throws -> [DiffLine] {
        let index = try #require(rows.firstIndex { row in
            switch row {
            case .finding, .thread, .draftComments: true
            default: false
            }
        })
        for row in rows[..<index].reversed() where !row.sourceLines.isEmpty {
            return row.sourceLines
        }
        throw SplitBubbleError.noLinesAboveTheBubble
    }

    private enum SplitBubbleError: Error { case noLinesAboveTheBubble }

    // MARK: - Nálezy

    @Test("Bublina nálezu visí pod dvojicí, ve které ten řádek je")
    func hangsTheFindingUnderItsPair() throws {
        let rows = DiffRow.rows(
            of: try file(),
            layout: .split,
            findings: Policy.groups(of: [finding("Cart.php", 26)])
        )

        let lines = try linesAboveBubble(in: rows)
        // Dvojice nese starý i nový řádek; bublina se váže na ten nový.
        #expect(lines.compactMap(\.newNumber) == [26])
        #expect(lines.map(\.text) == ["staré", "nové"])
    }

    /// Reviewer čte celý pracovní strom, ne jen diff, takže nález mimo diff je běžný —
    /// a schovat ho by znamenalo, že si ho nikdo nepřečte. Ve split pohledu to platí stejně.
    @Test("Nález mimo diff zůstane u hlavičky souboru i vedle sebe")
    func keepsAFindingOutsideTheDiff() throws {
        let rows = DiffRow.rows(
            of: try file(),
            layout: .split,
            findings: Policy.groups(of: [finding("Cart.php", 900)])
        )

        let unanchored = rows.compactMap { row -> FindingGroup? in
            guard case .finding(_, let group, let anchored) = row, !anchored else { return nil }
            return group
        }
        #expect(unanchored.count == 1)
    }

    // MARK: - Vlákna

    /// Vlákno na odebraném řádku má číslo ze **staré** verze souboru, tedy z levé strany
    /// dvojice. Porovnávat jen pravou by ho ztratilo.
    @Test("Vlákno na odebraném řádku sedne na svou dvojici")
    func matchesAThreadOnTheRemovedSide() throws {
        let rows = DiffRow.rows(of: try file(), layout: .split, threads: [thread(line: 26, side: .left)])

        let threads = rows.compactMap { row -> ReviewThread? in
            guard case .thread(_, let thread) = row else { return nil }
            return thread
        }
        #expect(threads.count == 1)
        #expect(try linesAboveBubble(in: rows).map(\.text) == ["staré", "nové"])
    }

    /// Kontextový řádek stojí na obou stranách jako **tatáž hodnota**, takže se porovnává
    /// jednou — jinak by u něj vzniklo dvakrát totéž vlákno.
    @Test("Vlákno na kontextovém řádku nevznikne dvakrát")
    func doesNotDuplicateAThreadOnAContextLine() throws {
        let rows = DiffRow.rows(of: try file(), layout: .split, threads: [thread(line: 27)])

        let threads = rows.filter { if case .thread = $0 { true } else { false } }
        #expect(threads.count == 1)
    }

    @Test("Rozdělaný komentář na kontextovém řádku nevznikne dvakrát")
    func doesNotDuplicateACommentOnAContextLine() throws {
        let comment = ReviewDraftComment(path: "Cart.php", anchor: DraftAnchor(line: 27, side: .right), body: "moje", origin: .own)

        let rows = DiffRow.rows(of: try file(), layout: .split, comments: [comment])

        let drawn = rows.flatMap { row in
            guard case .draftComments(_, let left, let right) = row else { return [ReviewDraftComment]() }
            return left + right
        }
        #expect(drawn.count == 1)
    }

    /// Komentáře k oběma stranám téhož řádku musí být v **jednom** řádku modelu, jinak je view
    /// nemá jak postavit vedle sebe — dva samostatné řádky líného seznamu se překrýt nedají.
    @Test("Komentáře k oběma stranám jsou v jednom řádku, rozdělené po stranách")
    func putsCommentsOfBothSidesInOneRow() throws {
        let comments = [
            ReviewDraftComment(path: "Cart.php", anchor: DraftAnchor(line: 26, side: .left), body: "vlevo", origin: .own),
            ReviewDraftComment(path: "Cart.php", anchor: DraftAnchor(line: 26, side: .right), body: "vpravo", origin: .own),
        ]

        let rows = DiffRow.rows(of: try file(), layout: .split, comments: comments)

        let commentRows = rows.compactMap { row -> (left: [ReviewDraftComment], right: [ReviewDraftComment])? in
            guard case .draftComments(_, let left, let right) = row else { return nil }
            return (left, right)
        }
        #expect(commentRows.count == 1)
        #expect(commentRows.first?.left.map(\.body) == ["vlevo"])
        #expect(commentRows.first?.right.map(\.body) == ["vpravo"])
    }

    /// Dva komentáře na téže straně se neslévají do jedné bubliny — jsou to dvě věci ke stejnému
    /// kódu — ale bydlí ve stejné polovině, tedy pod sebou v jednom sloupci.
    @Test("Dva komentáře na jedné straně zůstanou v jednom sloupci")
    func stacksTwoCommentsOnTheSameSide() throws {
        let comments = [
            ReviewDraftComment(path: "Cart.php", anchor: DraftAnchor(line: 26, side: .right), body: "první", origin: .own),
            ReviewDraftComment(path: "Cart.php", anchor: DraftAnchor(line: 26, side: .right), body: "druhý", origin: .own),
        ]

        let rows = DiffRow.rows(of: try file(), layout: .split, comments: comments)

        let commentRows = rows.compactMap { row -> (left: [ReviewDraftComment], right: [ReviewDraftComment])? in
            guard case .draftComments(_, let left, let right) = row else { return nil }
            return (left, right)
        }
        #expect(commentRows.count == 1)
        #expect(commentRows.first?.left.isEmpty == true)
        #expect(commentRows.first?.right.map(\.body) == ["první", "druhý"])
    }

    /// Identita řádku s komentáři vychází z **místa**, ne z komentáře: kdyby ji dával první
    /// komentář, vyjmutí levého by ji změnila a editor toho druhého by přišel o rozepsaný text.
    @Test("Identita řádku s komentáři se vyjmutím jednoho z nich nezmění")
    func keepsTheRowIdentityWhenACommentGoesAway() throws {
        let left = ReviewDraftComment(path: "Cart.php", anchor: DraftAnchor(line: 26, side: .left), body: "vlevo", origin: .own)
        let right = ReviewDraftComment(path: "Cart.php", anchor: DraftAnchor(line: 26, side: .right), body: "vpravo", origin: .own)

        func identity(_ comments: [ReviewDraftComment]) throws -> String {
            let rows = DiffRow.rows(of: try file(), layout: .split, comments: comments)
            return try #require(rows.first { if case .draftComments = $0 { true } else { false } }).id
        }

        #expect(try identity([left, right]) == (try identity([right])))
    }

    // MARK: - Kotvy

    /// Nálezy se hledají podle **nového** čísla řádku a to je vždycky vpravo, takže
    /// `anchor(in:file:line:)` platí v obou pohledech beze změny. Kdyby to přestalo platit,
    /// skok z tabulky nálezů by ve split pohledu mířil na id, které v seznamu není.
    @Test("Kotva nálezu míří ve split pohledu na dvojici s tím řádkem")
    func anchorsAFindingOnItsPair() throws {
        let diff = diff()
        let file = try file()

        let anchor = try #require(DiffRow.anchor(in: diff, file: "Cart.php", line: 26))

        let row = try #require(DiffRow.rows(of: file, layout: .split).first { $0.id == anchor })
        #expect(row.sourceLines.compactMap(\.newNumber) == [26])
    }

    @Test("Kotva nálezu platí i po rozbalení kontextu")
    func anchorsARevealedLine() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
        let file = try #require(diff.files.first { $0.displayPath == "CLAUDE.md" })
        var revealed = RevealedLines()
        revealed.reveal(100...110)

        let anchor = try #require(DiffRow.anchor(in: diff, file: "CLAUDE.md", line: 105, revealed: revealed))

        let rows = DiffRow.rows(
            of: file,
            layout: .split,
            revealed: revealed,
            content: (1...600).map { "řádek \($0)" }
        )
        let row = try #require(rows.first { $0.id == anchor })
        #expect(row.sourceLines.compactMap(\.newNumber) == [105])
    }

    /// Komentář k **odebranému** řádku je jediné místo, kde se kotva mezi pohledy liší:
    /// dvojice se hlásí pravým řádkem, takže id z hunku a pozice by v seznamu nebylo.
    @Test("Kotva komentáře na odebraném řádku míří na dvojici")
    func anchorsACommentOnTheRemovedSide() throws {
        let diff = diff()
        let comment = ReviewDraftComment(path: "Cart.php", anchor: DraftAnchor(line: 26, side: .left), body: "moje", origin: .own)

        let anchor = try #require(DiffRow.anchor(in: diff, comment: comment, layout: .split))

        let rows = DiffRow.rows(of: try file(), layout: .split)
        let row = try #require(rows.first { $0.id == anchor })
        #expect(row.sourceLines.map(\.text) == ["staré", "nové"])
    }

    @Test("Kotva komentáře na přidaném řádku je v obou pohledech stejná")
    func anchorsACommentTheSameWayInBothLayouts() throws {
        let diff = diff()
        let comment = ReviewDraftComment(path: "Cart.php", anchor: DraftAnchor(line: 26, side: .right), body: "moje", origin: .own)

        #expect(
            DiffRow.anchor(in: diff, comment: comment, layout: .split)
                == DiffRow.anchor(in: diff, comment: comment)
        )
    }

    @Test("Komentář v souboru, který v diffu není, nikam neukazuje ani vedle sebe")
    func hasNoAnchorOutsideTheDiff() throws {
        let comment = ReviewDraftComment(path: "Jinde.php", anchor: DraftAnchor(line: 26, side: .right), body: "moje", origin: .own)

        #expect(DiffRow.anchor(in: diff(), comment: comment, layout: .split) == nil)
    }
}
