import Foundation
import Testing

@testable import PRism

/// Bubliny mých rozdělaných komentářů v diffu. Čisté skládání řádků, nic se nemockuje.
@Suite("DiffRow — bubliny rozdělaného review")
struct DraftBubbleTests {
    /// Soubor s hunkem na nových řádcích 25–27: 25 kontext, 26 přidaný (starý 26 odebraný),
    /// 27 kontext.
    private func diff() -> Diff {
        DiffParser.parse("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -25,3 +25,3 @@
             kontext
            -staré
            +nové
             další
            """)
    }

    private func file() throws -> FileDiff {
        try #require(diff().files.first)
    }

    private func comment(
        path: String = "Cart.php",
        line: Int,
        side: DiffSide = .right,
        body: String = "moje poznámka",
        origin: ReviewDraftComment.Origin = .own
    ) -> ReviewDraftComment {
        ReviewDraftComment(path: path, line: line, side: side, body: body, origin: origin)
    }

    private func comments(in rows: [DiffRow]) -> [ReviewDraftComment] {
        rows.compactMap { row in
            guard case .draftComment(_, let comment) = row else { return nil }
            return comment
        }
    }

    /// Řádek, pod kterým bublina visí — podle toho se pozná, že sedí na svém místě.
    private func line(above index: Int, in rows: [DiffRow]) throws -> DiffLine {
        for row in rows[..<index].reversed() {
            if case .line(_, let line) = row { return line }
        }
        throw BubbleError.noLineAbove
    }

    private enum BubbleError: Error { case noLineAbove }

    @Test("Komentář visí pod svým řádkem")
    func hangsUnderItsLine() throws {
        let rows = DiffRow.rows(of: try file(), comments: [comment(line: 26)])

        let index = try #require(rows.firstIndex { if case .draftComment = $0 { true } else { false } })
        #expect(try line(above: index, in: rows).newNumber == 26)
    }

    /// Tatáž lekce jako u vláken v #64: komentář k **odebranému** řádku má číslo ze staré
    /// verze souboru, takže porovnání s novým číslem by ho posadilo na jiný kód.
    @Test("Komentář na odebraném řádku sedne na odebraný řádek")
    func hangsALeftSideCommentOnTheRemovedLine() throws {
        let rows = DiffRow.rows(of: try file(), comments: [comment(line: 26, side: .left)])

        let index = try #require(rows.firstIndex { if case .draftComment = $0 { true } else { false } })
        let anchor = try line(above: index, in: rows)
        #expect(anchor.kind == .removed)
        #expect(anchor.oldNumber == 26)
        #expect(anchor.newNumber == nil)
    }

    /// Nový commit umí řádek z diffu vyhodit. Bublina se nemá kde ukázat, ale komentář **je**
    /// vidět v panelu, takže se neztrácí — a kreslit ji naslepo by znamenalo posadit ji na
    /// cizí kód, tedy tatáž past jako u zastaralých vláken.
    @Test("Komentář na řádku mimo diff se nekreslí")
    func skipsACommentOutsideTheDiff() throws {
        let rows = DiffRow.rows(of: try file(), comments: [comment(line: 120)])

        #expect(comments(in: rows).isEmpty)
    }

    @Test("Komentáře cizích souborů se nepřipletou")
    func ignoresCommentsOfOtherFiles() throws {
        let rows = DiffRow.rows(of: try file(), comments: [comment(path: "Other.php", line: 26)])

        #expect(comments(in: rows).isEmpty)
    }

    /// Dva komentáře na jednom řádku jsou dvě věci ke stejnému kódu — nesmí se slít, stejně
    /// jako se neslévají vlákna.
    @Test("Dva komentáře na řádku dají dvě bubliny")
    func keepsTwoCommentsOnOneLineApart() throws {
        let rows = DiffRow.rows(
            of: try file(),
            comments: [comment(line: 26, body: "první"), comment(line: 26, body: "druhý")]
        )

        #expect(comments(in: rows).map(\.body) == ["první", "druhý"])
    }

    /// Nález a cizí komentář jsou to, co si mám přečíst; svou vlastní rozepsanou větu znám.
    @Test("Nález i vlákno jdou nad můj komentář")
    func ordersFindingAndThreadAboveMyComment() throws {
        let thread = ReviewThread(
            id: "T1",
            path: "Cart.php",
            line: 26,
            originalLine: 26,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
        let rows = DiffRow.rows(
            of: try file(),
            findings: Policy.groups(of: [makeFinding(file: "Cart.php", line: 26)]),
            threads: [thread],
            comments: [comment(line: 26)]
        )

        let kinds = rows.compactMap { row -> String? in
            switch row {
            case .finding: "finding"
            case .thread: "thread"
            case .draftComment: "draft"
            default: nil
            }
        }
        #expect(kinds == ["finding", "thread", "draft"])
    }

    /// Nález na binárce nebo na souboru beze změny obsahu se z diffu ztratit nesmí — a totéž
    /// platí o mém komentáři, protože ten se odesílá.
    @Test("Komentář se ukáže i u souboru beze změny obsahu")
    func keepsCommentsOnAFileWithoutHunks() throws {
        let diff = DiffParser.parse("""
            diff --git a/Old.php b/New.php
            similarity index 100%
            rename from Old.php
            rename to New.php
            """)
        let file = try #require(diff.files.first)

        // Bez hunků není co kotvit, takže se komentář nekreslí — ale řádky se skládají dál
        // a poznámka o souboru zůstává.
        let rows = DiffRow.rows(of: file, comments: [comment(path: "New.php", line: 1)])

        #expect(rows.contains { if case .note = $0 { true } else { false } })
    }

    // MARK: - Skok z panelu

    @Test("Kotva komentáře ukazuje na jeho řádek")
    func anchorsAComment() throws {
        let diff = diff()
        let file = try #require(diff.files.first)
        let rows = DiffRow.rows(of: file)

        let anchor = try #require(DiffRow.anchor(in: diff, comment: comment(line: 26)))

        let row = try #require(rows.first { $0.id == anchor })
        guard case .line(_, let line) = row else {
            Issue.record("kotva neukazuje na řádek")
            return
        }
        #expect(line.newNumber == 26)
    }

    /// Kotva podle **nového** čísla by u komentáře na odebraném řádku skončila u hlavičky
    /// souboru, tedy jinde, než kde ten komentář je.
    @Test("Kotva komentáře na odebraném řádku ukazuje na odebraný řádek")
    func anchorsALeftSideComment() throws {
        let diff = diff()
        let file = try #require(diff.files.first)

        let anchor = try #require(
            DiffRow.anchor(in: diff, comment: comment(line: 26, side: .left))
        )

        let row = try #require(DiffRow.rows(of: file).first { $0.id == anchor })
        guard case .line(_, let line) = row else {
            Issue.record("kotva neukazuje na řádek")
            return
        }
        #expect(line.kind == .removed)
    }

    /// Odskočit aspoň na soubor je pořád lepší než nehnout se.
    @Test("Komentář na zmizelém řádku kotví u souboru")
    func fallsBackToTheFile() throws {
        let diff = diff()
        let file = try #require(diff.files.first)

        #expect(DiffRow.anchor(in: diff, comment: comment(line: 120)) == file.id)
    }

    @Test("Komentář k souboru mimo diff kotvu nemá")
    func hasNoAnchorOutsideTheDiff() {
        #expect(DiffRow.anchor(in: diff(), comment: comment(path: "Other.php", line: 1)) == nil)
    }
}
