import Foundation
import Testing

@testable import PRism

/// Komentovatelnost řádku a zastarání draftu — čisté funkce, nic se nemockuje.
@Suite("Policy — draft")
struct DraftPolicyTests {
    private let pr = PRIdentifier("cli/cli#42")!

    /// Soubor s hunkem na nových řádcích 25–27: 25 kontext, 26 přidaný (starý 26 odebraný),
    /// 27 kontext. Před hunkem i za ním jsou řádky, které v diffu **nejsou**.
    private func file() throws -> FileDiff {
        let diff = DiffParser.parse("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -25,3 +25,3 @@
             kontext
            -staré
            +nové
             další
            """)
        return try #require(diff.files.first)
    }

    private func line(_ kind: DiffLine.Kind, old: Int?, new: Int?, text: String) -> DiffLine {
        DiffLine(kind: kind, oldNumber: old, newNumber: new, text: text)
    }

    // MARK: - Komentovatelnost

    @Test("Přidaný řádek se komentuje na pravé straně")
    func commentsAnAddedLineOnTheRight() throws {
        let file = try file()
        let added = try #require(file.hunks.first?.lines.first { $0.kind == .added })

        #expect(Policy.commentableSide(of: added, in: file) == .right)
    }

    /// Ověřeno na živém API u #62: komentář na kontextovém řádku hunku projde.
    @Test("Kontextový řádek hunku se komentuje na pravé straně")
    func commentsAContextLineOnTheRight() throws {
        let file = try file()
        let context = try #require(file.hunks.first?.lines.first { $0.kind == .context })

        #expect(Policy.commentableSide(of: context, in: file) == .right)
    }

    /// Odebraný řádek v novém souboru neexistuje a jeho číslo je ze starého — bez `left` by
    /// komentář odešel na jiný řádek.
    @Test("Odebraný řádek se komentuje na levé straně")
    func commentsARemovedLineOnTheLeft() throws {
        let file = try file()
        let removed = try #require(file.hunks.first?.lines.first { $0.kind == .removed })

        #expect(Policy.commentableSide(of: removed, in: file) == .left)
        #expect(removed.newNumber == nil)
    }

    /// `\ No newline at end of file` není obsah souboru.
    @Test("Meta řádek se komentovat nedá")
    func refusesAMetaLine() throws {
        let file = try file()
        let meta = line(.meta, old: nil, new: nil, text: "\\ No newline at end of file")

        #expect(Policy.commentableSide(of: meta, in: file) == nil)
        #expect(!Policy.isCommentable(meta, in: file))
    }

    /// GitHub takový komentář odmítne (`422 Line could not be resolved`) a **s ním celé
    /// review** — ověřeno u #62. Nesmí se to tedy nabídnout.
    @Test("Řádek mimo hunky se komentovat nedá")
    func refusesALineOutsideHunks() throws {
        let file = try file()
        let outside = line(.context, old: 5, new: 5, text: "výplň mimo hunk")

        #expect(Policy.commentableSide(of: outside, in: file) == nil)
    }

    /// **Rozbalený kontext (#47) komentovat nejde** — jsou to řádky dotažené ze souboru,
    /// které v diffu nejsou. `DiffRow` je skládá jako obyčejný kontext s oběma čísly, takže
    /// se to musí poznat příslušností k hunku, ne z `DiffLine` samotného.
    @Test("Rozbalený kontext se komentovat nedá")
    func refusesRevealedContext() throws {
        let file = try file()
        let content = (1...40).map { "// řádek \($0)" }
        var revealed = RevealedLines()
        revealed.reveal(20...24)

        let rows = DiffRow.rows(of: file, revealed: revealed, content: content)
        let revealedLines = rows.compactMap { row -> DiffLine? in
            guard case .line(_, let line) = row else { return nil }
            // Řádky hunku mají čísla 25–27; cokoli nižšího přišlo z rozbalení.
            guard let number = line.newNumber, number < 25 else { return nil }
            return line
        }

        #expect(!revealedLines.isEmpty, "rozbalení nedodalo žádný řádek")
        for line in revealedLines {
            #expect(
                Policy.commentableSide(of: line, in: file) == nil,
                "rozbalený řádek \(line.newNumber ?? -1) se nabízí ke komentáři"
            )
        }
    }

    /// Řádky hunku komentovatelné **zůstanou**, i když je kolem nich rozbalený kontext.
    ///
    /// Rozbalení se tu musí opravdu udělat, ne jen zmínit v názvu: bez `DiffRow.rows`
    /// s `revealed`/`content` by test prošel, i kdyby rozbalení hunkové řádky rozbilo.
    @Test("Rozbalení nezkazí komentovatelnost řádků hunku")
    func keepsHunkLinesCommentableAfterRevealing() throws {
        let file = try file()
        let content = (1...40).map { "// řádek \($0)" }
        var revealed = RevealedLines()
        revealed.reveal(20...24)

        let rows = DiffRow.rows(of: file, revealed: revealed, content: content)
        let hunkLines = rows.compactMap { row -> DiffLine? in
            guard case .line(_, let line) = row else { return nil }
            // Řádky hunku jsou 25–27 na nové straně, plus odebraný, který nové číslo nemá.
            guard line.kind != .meta else { return nil }
            guard line.newNumber.map({ $0 >= 25 }) ?? true else { return nil }
            return line
        }

        #expect(hunkLines.count == 4, "hunk má tři nové řádky a jeden odebraný")
        for line in hunkLines {
            #expect(
                Policy.isCommentable(line, in: file),
                "řádek hunku (\(line.kind)) po rozbalení přestal být komentovatelný"
            )
        }
    }

    @Test("Soubor bez hunků nemá co komentovat")
    func refusesEverythingWithoutHunks() {
        let diff = DiffParser.parse("""
            diff --git a/logo.png b/logo.png
            Binary files a/logo.png and b/logo.png differ
            """)
        guard let binary = diff.files.first else { return }

        #expect(Policy.commentableSide(
            of: line(.added, old: nil, new: 1, text: "cokoli"),
            in: binary
        ) == nil)
    }

    // MARK: - Zastarání

    @Test("Draft proti hlavě PR zastaralý není")
    func isFreshAgainstTheHead() {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", body: "tělo")

        #expect(!Policy.isStale(draft, head: "abc"))
    }

    @Test("Nový commit draft označí za zastaralý")
    func goesStaleOnANewCommit() {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", body: "tělo")

        #expect(Policy.isStale(draft, head: "def"))
    }

    // MARK: - Odesílatelnost

    @Test("Draft s verdiktem a obsahem se odeslat dá")
    func isSendableWithAVerdict() {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", body: "tělo", verdict: .approve)

        #expect(Policy.isSendable(draft, head: "abc"))
    }

    /// `event` je v API povinný a hádat ho za člověka znamená odeslat něco jiného, než chtěl.
    @Test("Bez vybraného verdiktu se odeslat nedá")
    func isNotSendableWithoutAVerdict() {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", body: "tělo", verdict: nil)

        #expect(!Policy.isSendable(draft, head: "abc"))
    }

    @Test("Úplně prázdný draft se odeslat nedá")
    func isNotSendableWhenEmpty() {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc")

        #expect(draft.isEmpty)
        #expect(!Policy.isSendable(draft, head: "abc"))
    }

    /// Schválení **bez prózy a bez komentářů je plnohodnotné review** — v datech z #63 to
    /// byla čtvrtina vzorku. Kdyby ho `isEmpty` bralo jako prázdné, nešlo by PR odklepnout
    /// bez toho, aby k tomu člověk něco napsal.
    @Test("Samotný verdikt bez prózy se odeslat dá")
    func isSendableWithNothingButAVerdict() {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", verdict: .approve)

        #expect(!draft.isEmpty)
        #expect(Policy.isSendable(draft, head: "abc"))
    }

    /// Nový commit draft **nemaže**, jen blokuje odeslání.
    @Test("Zastaralý draft se odeslat nedá, ale zůstává")
    func isNotSendableWhenStale() {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", body: "tělo", verdict: .approve)

        #expect(!Policy.isSendable(draft, head: "def"))
        #expect(!draft.isEmpty)
    }

    // MARK: - Prázdnost

    @Test("Draft je prázdný jen bez těla, verdiktu i komentářů")
    func recognisesAnEmptyDraft() {
        #expect(ReviewDraft(pullRequest: pr, headSha: "abc").isEmpty)
        #expect(!ReviewDraft(pullRequest: pr, headSha: "abc", body: "tělo").isEmpty)
        #expect(!ReviewDraft(pullRequest: pr, headSha: "abc", verdict: .comment).isEmpty)
        #expect(!ReviewDraft(
            pullRequest: pr,
            headSha: "abc",
            comments: [
                ReviewDraftComment(path: "a.php", line: 1, side: .right, body: "x", origin: .own),
            ]
        ).isEmpty)
    }
}
