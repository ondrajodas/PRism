import Foundation
import Testing

@testable import PRism

/// Skok z nálezu do diffu. Počítá se nad **rozbalenými řádky**, ne vedle nich — kdyby
/// číslování bylo na dvou místech, ukazoval by odkaz brzy vedle.
@Suite("DiffRow — skok na nález")
struct DiffRowTests {
    private func ordinaryDiff() throws -> Diff {
        DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
    }

    private func row(_ anchor: String, in file: FileDiff) throws -> DiffRow {
        try #require(DiffRow.rows(of: file).first { $0.id == anchor })
    }

    @Test("Nález na změněném řádku ukazuje přímo na ten řádek")
    func anchorsOnTheChangedLine() throws {
        let diff = try ordinaryDiff()
        let file = try #require(diff.files.first { $0.displayPath == "CLAUDE.md" })

        let anchor = try #require(DiffRow.anchor(in: diff, file: "CLAUDE.md", line: 174))

        guard case .line(_, let line) = try row(anchor, in: file) else {
            Issue.record("Kotva má ukazovat na řádek souboru")
            return
        }
        #expect(line.newNumber == 174)
        #expect(line.kind == .added)
    }

    @Test("Nález bez řádku ukazuje na soubor")
    func anchorsOnTheFileWithoutALine() throws {
        let diff = try ordinaryDiff()
        let file = try #require(diff.files.first { $0.displayPath == "CLAUDE.md" })

        #expect(DiffRow.anchor(in: diff, file: "CLAUDE.md", line: nil) == file.id)
    }

    /// Reviewer čte celý soubor, ne jen diff, takže umí nahlásit řádek, který se nezměnil.
    /// Odskočit aspoň na soubor je pořád lepší než nedělat nic.
    @Test("Nález na řádku mimo hunky spadne na soubor")
    func fallsBackToTheFileForALineOutsideTheHunks() throws {
        let diff = try ordinaryDiff()
        let file = try #require(diff.files.first { $0.displayPath == "CLAUDE.md" })

        #expect(DiffRow.anchor(in: diff, file: "CLAUDE.md", line: 99999) == file.id)
    }

    /// Nález mimo hunky si svůj kód dotáhne (#47), takže řádek **je** vykreslený — jako
    /// rozbalený kontext. Kotva na hlavičku souboru by pak přistála jinde, než kde nález je.
    @Test("Kotva na rozbaleném řádku ukazuje na ten řádek")
    func anchorsOnARevealedLine() throws {
        let diff = try ordinaryDiff()
        let file = try #require(diff.files.first { $0.displayPath == "CLAUDE.md" })
        var revealed = RevealedLines()
        revealed.reveal(100...110)

        let anchor = try #require(DiffRow.anchor(in: diff, file: "CLAUDE.md", line: 105, revealed: revealed))

        let rows = DiffRow.rows(of: file, revealed: revealed, content: (1...600).map { "řádek \($0)" })
        guard case .line(_, let line) = try #require(rows.first(where: { $0.id == anchor })) else {
            Issue.record("Kotva má ukazovat na řádek")
            return
        }
        #expect(line.newNumber == 105)
    }

    @Test("Nerozbalený řádek mimo hunky pořád spadne na soubor")
    func fallsBackToTheFileWhenTheLineIsNotRevealed() throws {
        let diff = try ordinaryDiff()
        let file = try #require(diff.files.first { $0.displayPath == "CLAUDE.md" })

        #expect(DiffRow.anchor(in: diff, file: "CLAUDE.md", line: 105) == file.id)
    }

    /// Soubor se hledá podle **obou** cest. Přejmenovaný soubor umí reviewer nahlásit pod
    /// tou starou a expanze se přitom klíčují novou — bez jednoho místa na překlad se ty
    /// dvě věci rozejdou.
    @Test("Soubor se najde podle nové i staré cesty")
    func findsAFileByEitherPath() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-rename.diff"))

        #expect(diff.file(at: "App/PRismApp.swift")?.newPath == "App/PRismApp.swift")
        #expect(diff.file(at: "App/PRReviewApp.swift")?.newPath == "App/PRismApp.swift")
        #expect(diff.file(at: "nikde/neni.swift") == nil)
    }

    @Test("Nález v souboru, který v diffu není, nikam neukazuje")
    func hasNoAnchorForAFileOutsideTheDiff() throws {
        #expect(DiffRow.anchor(in: try ordinaryDiff(), file: "App/Nikde.swift", line: 3) == nil)
    }

    @Test("Nález pod starou cestou přejmenovaného souboru se najde")
    func findsARenamedFileByItsOldPath() throws {
        // Reviewer dostane pracovní strom po přejmenování, ale nález se může vázat na
        // cestu, pod kterou soubor v diffu vystupuje jako starý.
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-rename.diff"))
        let file = try #require(diff.files.first { $0.oldPath == "pr-review.entitlements" })

        #expect(DiffRow.anchor(in: diff, file: "pr-review.entitlements", line: nil) == file.id)
    }
}
