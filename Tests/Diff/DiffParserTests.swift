import Foundation
import Testing

@testable import PRism

/// Parser se testuje proti **skutečným** výstupům `gh pr diff` z veřejných repozitářů —
/// tvar unified diffu nikdo nespecifikoval, takže vymyšlený vstup by ověřoval jen to, co
/// jsem si sám vymyslel. Syntetické vstupy zůstávají na to, co se z reálného PR nedá
/// sehnat: rozbité řádky a okrajové tvary hlaviček.
@Suite("DiffParser")
struct DiffParserTests {

    // MARK: - Skutečné diffy

    @Test("Běžný diff se přečte celý — žádný řádek nezůstane nerozpoznaný")
    func parsesOrdinaryDiff() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))

        #expect(diff.files.count == 8)
        #expect(diff.unrecognizedLines == 0)
        #expect(diff.additions == 297)
        #expect(diff.deletions == 22)
    }

    @Test("Hunk nese rozsahy i nadpis sekce")
    func readsHunkHeader() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))

        let hunk = try #require(diff.files.first?.hunks.first)
        #expect(hunk.oldStart == 171)
        #expect(hunk.oldCount == 8)
        #expect(hunk.newStart == 171)
        #expect(hunk.newCount == 14)
        #expect(hunk.heading == "Tohle nejsou zjednodušení první verze. Než něco z toho porušíš, zastav s")
    }

    /// Čísla řádků jsou to jediné, kvůli čemu se hunk parsuje — bublina nálezu se v #19
    /// zavěsí právě na ně.
    @Test("Odebraný řádek má jen staré číslo, přidaný jen nové, kontext obě")
    func numbersLines() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
        let lines = try #require(diff.files.first?.hunks.first?.lines)

        #expect(lines.count == 16)
        #expect(lines[0] == DiffLine(kind: .context, oldNumber: 171, newNumber: 171, text: ""))

        let removed = try #require(lines.first { $0.kind == .removed })
        #expect(removed.oldNumber == 174)
        #expect(removed.newNumber == nil)
        #expect(removed.text.hasPrefix("2. **Reviewer je read-only.** `--allowedTools`"))

        let added = try #require(lines.first { $0.kind == .added })
        #expect(added.oldNumber == nil)
        #expect(added.newNumber == 174)

        // První kontext za blokem změn: dva odebrané a osm přidaných řádků posunuly
        // každé počítadlo o svoje, takže se čísla rozešla.
        let afterChange = lines[13]
        #expect(afterChange.kind == .context)
        #expect(afterChange.oldNumber == 176)
        #expect(afterChange.newNumber == 182)
    }

    @Test("Nový soubor nemá starou cestu")
    func readsAddedFile() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))

        let added = try #require(diff.files.first { $0.change == .added })
        #expect(added.oldPath == nil)
        #expect(added.newPath == "Tests/Fixtures/stream-json/review-clean.jsonl")
        #expect(added.displayPath == "Tests/Fixtures/stream-json/review-clean.jsonl")
    }

    @Test("Smazaný soubor nemá novou cestu a všechny řádky jsou odebrané")
    func readsDeletedFile() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-deleted.diff"))

        #expect(diff.unrecognizedLines == 0)
        let file = try #require(diff.files.first)
        #expect(file.change == .deleted)
        #expect(file.oldPath == ".github/workflows/triage-discussion-label.yml")
        #expect(file.newPath == nil)
        #expect(file.displayPath == ".github/workflows/triage-discussion-label.yml")
        #expect(file.deletions == 23)
        #expect(file.additions == 0)

        let lines = try #require(file.hunks.first?.lines)
        #expect(lines.allSatisfy { $0.kind == .removed })
        #expect(lines.map(\.oldNumber) == Array(1...23))
        #expect(lines.allSatisfy { $0.newNumber == nil })
    }

    @Test("Přejmenování nese obě cesty")
    func readsRenames() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-rename.diff"))

        #expect(diff.unrecognizedLines == 0)
        #expect(diff.files.count == 11)
        let renamed = diff.files.filter { $0.change == .renamed }
        #expect(renamed.count == 5)

        let app = try #require(renamed.first { $0.newPath == "App/PRismApp.swift" })
        #expect(app.oldPath == "App/PRReviewApp.swift")
        #expect(!app.hunks.isEmpty)
    }

    /// Přejmenování se `similarity index 100%` nemá `---`/`+++` ani hunky — cesty jsou
    /// jen v `rename from`/`rename to`.
    @Test("Přejmenování beze změny obsahu má cesty a žádné hunky")
    func readsRenameWithoutContentChange() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-rename.diff"))

        let file = try #require(diff.files.first { $0.oldPath == "pr-review.entitlements" })
        #expect(file.change == .renamed)
        #expect(file.newPath == "PRism.entitlements")
        #expect(file.hunks.isEmpty)
        #expect(!file.isBinary)
    }

    @Test("Binární soubor se pozná a nemá hunky")
    func readsBinaryFiles() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-binary.diff"))

        #expect(diff.unrecognizedLines == 0)
        #expect(diff.files.count == 49)

        let binary = diff.files.filter(\.isBinary)
        #expect(binary.count == 44)
        #expect(binary.allSatisfy { $0.hunks.isEmpty })
        #expect(binary.allSatisfy { $0.change == .added })

        let image = try #require(binary.first)
        #expect(image.newPath == "docs/primer/components/images/Detail-gh-issue-view.png")
        #expect(image.oldPath == nil)
    }

    @Test("Textové soubory se z diffu s binárkami přečtou normálně")
    func readsTextFilesNextToBinaries() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-binary.diff"))

        let text = diff.files.filter { !$0.isBinary }
        #expect(text.count == 5)
        #expect(text.allSatisfy { !$0.hunks.isEmpty })
        #expect(diff.additions == 596)
        #expect(diff.deletions == 2)
    }

    // MARK: - Rozbité a okrajové vstupy

    @Test("Prázdný vstup není chyba ani ztráta")
    func parsesEmptyInput() {
        let diff = DiffParser.parse("")

        #expect(diff.files.isEmpty)
        #expect(diff.unrecognizedLines == 0)
        #expect(diff.isEmpty)
    }

    /// Tohle je důvod, proč parser drží stav a nerozhoduje podle prvního znaku: odebraný
    /// řádek začínající `---` vypadá přesně jako hlavička souboru.
    @Test("Odebraný řádek začínající --- není hlavička souboru")
    func doesNotMistakeContentForHeader() throws {
        let diff = DiffParser.parse("""
        diff --git a/x.md b/x.md
        index 1111111..2222222 100644
        --- a/x.md
        +++ b/x.md
        @@ -1,2 +1,2 @@
        --- a/starý odkaz
        +++ b/nový odkaz
        """)

        #expect(diff.files.count == 1)
        let file = try #require(diff.files.first)
        #expect(file.oldPath == "x.md")
        #expect(file.newPath == "x.md")
        let lines = try #require(file.hunks.first?.lines)
        #expect(lines.count == 2)
        #expect(lines.first == DiffLine(kind: .removed, oldNumber: 1, newNumber: nil, text: "-- a/starý odkaz"))
        #expect(lines.last == DiffLine(kind: .added, oldNumber: nil, newNumber: 1, text: "++ b/nový odkaz"))
    }

    @Test("Řádek, kterému parser nerozumí, se počítá — nezmizí")
    func countsUnrecognizedLines() {
        let diff = DiffParser.parse("""
        tohle sem nepatří
        diff --git a/x.md b/x.md
        --- a/x.md
        +++ b/x.md
        @@ -1,1 +1,1 @@
         kontext
        """)

        #expect(diff.unrecognizedLines == 1)
        #expect(diff.files.count == 1)
        #expect(diff.files.first?.hunks.first?.lines.count == 1)
    }

    @Test("Chybějící konec řádku se zaznamená a čísla neposune")
    func readsNoNewlineMarker() throws {
        let diff = DiffParser.parse("""
        diff --git a/x.md b/x.md
        --- a/x.md
        +++ b/x.md
        @@ -1,2 +1,2 @@
         první
        -druhý
        \\ No newline at end of file
        +druhý řádek
        \\ No newline at end of file
        """)

        let lines = try #require(diff.files.first?.hunks.first?.lines)
        #expect(diff.unrecognizedLines == 0)
        #expect(lines.map(\.kind) == [.context, .removed, .meta, .added, .meta])
        #expect(lines[2].oldNumber == nil)
        #expect(lines[2].newNumber == nil)
        #expect(lines[3].newNumber == 2)
    }

    @Test("Hunk bez počtu řádků znamená jeden řádek")
    func readsHunkWithoutCounts() throws {
        let diff = DiffParser.parse("""
        diff --git a/x.md b/x.md
        --- a/x.md
        +++ b/x.md
        @@ -7 +9 @@
        -starý
        +nový
        """)

        let hunk = try #require(diff.files.first?.hunks.first)
        #expect(hunk.oldStart == 7)
        #expect(hunk.oldCount == 1)
        #expect(hunk.newStart == 9)
        #expect(hunk.newCount == 1)
        #expect(hunk.lines.first?.oldNumber == 7)
        #expect(hunk.lines.last?.newNumber == 9)
    }

    /// `gh` posílá kontextový řádek vždycky s mezerou, ale cokoli, co po cestě ořeže
    /// koncové mezery, z prázdného kontextu udělá prázdný řádek. Spočítat ho jako
    /// nerozpoznaný by znamenalo hlásit rozbitý diff kvůli prázdnému řádku v souboru.
    @Test("Prázdný řádek uvnitř hunku je prázdný kontext")
    func readsEmptyContextLine() throws {
        let diff = DiffParser.parse("""
        diff --git a/x.md b/x.md
        --- a/x.md
        +++ b/x.md
        @@ -1,3 +1,3 @@
         první

         třetí
        """)

        let lines = try #require(diff.files.first?.hunks.first?.lines)
        #expect(diff.unrecognizedLines == 0)
        #expect(lines.map(\.kind) == [.context, .context, .context])
        #expect(lines[1].text == "")
        #expect(lines[2].oldNumber == 3)
    }

    @Test("Soubor beze změny obsahu, jen s právy, se v diffu neztratí")
    func readsModeOnlyChange() throws {
        let diff = DiffParser.parse("""
        diff --git a/bin/run.sh b/bin/run.sh
        old mode 100644
        new mode 100755
        """)

        #expect(diff.unrecognizedLines == 0)
        let file = try #require(diff.files.first)
        #expect(file.change == .modified)
        #expect(file.displayPath == "bin/run.sh")
        #expect(file.hunks.isEmpty)
    }
}
