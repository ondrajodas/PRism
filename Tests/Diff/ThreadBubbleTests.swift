import Foundation
import Testing

@testable import PRism

/// Vlákna zavěšená pod řádky diffu — stejná infrastruktura jako u nálezů.
@Suite("Bubliny vláken")
struct ThreadBubbleTests {
    private func comment(id: String = "c1", author: String = "kolega") -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: "co to tady dělá",
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            url: URL(string: "https://github.com/o/r/pull/1#discussion_\(id)")!
        )
    }

    private func thread(
        id: String = "t1",
        path: String = "Cart.php",
        line: Int? = 27,
        resolved: Bool = false,
        side: DiffSide? = .right,
        comments: [ThreadComment]? = nil,
        total: Int? = nil
    ) -> ReviewThread {
        let items = comments ?? [comment()]
        return ReviewThread(
            id: id,
            path: path,
            line: line,
            originalLine: line,
            side: side,
            isResolved: resolved,
            isOutdated: line == nil,
            comments: ConversationPage(
                items: items,
                total: total ?? items.count,
                hasNextPage: false
            )
        )
    }

    /// Hunk s novými řádky 25–27 (26 je přidaný, 25 a 27 kontext).
    private func file(path: String = "Cart.php") throws -> FileDiff {
        let diff = DiffParser.parse("""
            diff --git a/\(path) b/\(path)
            --- a/\(path)
            +++ b/\(path)
            @@ -25,3 +25,3 @@
             kontext
            -staré
            +nové
             další
            """)
        return try #require(diff.files.first)
    }

    private func threadRows(_ rows: [DiffRow]) -> [ReviewThread] {
        rows.compactMap { row in
            guard case .thread(_, let thread) = row else { return nil }
            return thread
        }
    }

    @Test("Bublina vlákna visí pod svým řádkem")
    func hangsUnderItsLine() throws {
        let rows = DiffRow.rows(of: try file(), threads: [thread(line: 27)])

        let index = try #require(rows.firstIndex { row in
            guard case .thread = row else { return false }
            return true
        })
        // Nad bublinou musí být řádek 27, ne cokoli jiného.
        guard case .line(_, let previous) = rows[index - 1] else {
            Issue.record("nad bublinou není řádek")
            return
        }
        #expect(previous.newNumber == 27)
    }

    /// Zastaralé vlákno se do diffu **nedostane** — na rozdíl od nálezu, který mimo diff
    /// visí u hlavičky souboru. Jeho číslo platilo pro starý head.
    @Test("Zastaralé vlákno v diffu není vůbec")
    func neverRendersAnOutdatedThread() throws {
        let rows = DiffRow.rows(of: try file(), threads: [thread(line: nil)])

        #expect(threadRows(rows).isEmpty)
    }

    @Test("Vlákno na řádku mimo hunky se nekreslí")
    func skipsAThreadOutsideHunks() throws {
        let rows = DiffRow.rows(of: try file(), threads: [thread(line: 900)])

        #expect(threadRows(rows).isEmpty)
    }

    @Test("Vlákna cizího souboru se nepřipletou")
    func ignoresThreadsOfOtherFiles() throws {
        let rows = DiffRow.rows(of: try file(), threads: [thread(path: "Jinde.php", line: 27)])

        #expect(threadRows(rows).isEmpty)
    }

    /// Dvě vlákna na jednom řádku jsou **dvě** bubliny — každé je vlastní konverzace
    /// s vlastním stavem vyřešení, takže se slévat nesmí (na rozdíl od nálezů).
    @Test("Dvě vlákna na jednom řádku dají dvě bubliny")
    func keepsTwoThreadsOnOneLineApart() throws {
        let rows = DiffRow.rows(of: try file(), threads: [
            thread(id: "a", line: 27),
            thread(id: "b", line: 27, resolved: true),
        ])

        let threads = threadRows(rows)
        #expect(threads.count == 2)
        #expect(threads.map(\.id) == ["a", "b"])
    }

    @Test("Každá bublina vlákna má vlastní identitu")
    func givesEveryBubbleItsOwnIdentity() throws {
        let rows = DiffRow.rows(of: try file(), threads: [
            thread(id: "a", line: 27),
            thread(id: "b", line: 27),
        ])

        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    /// Identita nese `id` z GitHubu, ne pořadí — po obnovení konverzace se pořadí může
    /// změnit a stav rozbalení by přeskočil na jiné vlákno.
    @Test("Identita bubliny nese id vlákna")
    func carriesTheThreadIdentity() throws {
        let rows = DiffRow.rows(of: try file(), threads: [thread(id: "PRRC_abc", line: 27)])
        let bubble = try #require(rows.first { row in
            guard case .thread = row else { return false }
            return true
        })

        #expect(bubble.id.contains("PRRC_abc"))
    }

    /// Nález je to, kvůli čemu je okno otevřené; konverzace je kontext k němu.
    @Test("Na jednom řádku jde nález nad vlákno")
    func putsFindingsAboveThreads() throws {
        let finding = Finding(
            reported: ReportedFinding(
                file: "Cart.php",
                line: 27,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: nil,
                summary: "tady to spadne",
                failureScenario: nil
            ),
            reviewer: "code-review",
            headSha: "abc"
        )
        let rows = DiffRow.rows(
            of: try file(),
            findings: Policy.groups(of: [finding]),
            threads: [thread(line: 27)]
        )

        let findingIndex = try #require(rows.firstIndex { row in
            guard case .finding = row else { return false }
            return true
        })
        let threadIndex = try #require(rows.firstIndex { row in
            guard case .thread = row else { return false }
            return true
        })
        #expect(findingIndex < threadIndex)
    }

    /// Vlákno na binárce se nemá kde ukázat, ale nesmí položit vykreslení.
    @Test("Binárka s vláknem projde bez pádu")
    func survivesAThreadOnABinaryFile() {
        let diff = DiffParser.parse("""
            diff --git a/logo.png b/logo.png
            Binary files a/logo.png and b/logo.png differ
            """)
        guard let file = diff.files.first else { return }

        let rows = DiffRow.rows(of: file, threads: [thread(path: "logo.png", line: 1)])

        #expect(threadRows(rows).isEmpty)
        #expect(!rows.isEmpty)
    }

    @Test("Bez vláken se řádky nemění")
    func changesNothingWithoutThreads() throws {
        let plain = DiffRow.rows(of: try file())
        let withEmpty = DiffRow.rows(of: try file(), threads: [])

        #expect(plain.map(\.id) == withEmpty.map(\.id))
    }

    // MARK: - Strana diffu

    /// Vlákno na **odebraném** řádku má číslo ze staré verze souboru. Kdyby se porovnávalo
    /// s novým (jak to dělal první návrh), sedlo by na jiný kód — a nikdo by to nepoznal.
    /// Přesně kvůli tomu je `side` v modelu.
    @Test("Vlákno na levé straně se kotví podle starého čísla")
    func anchorsALeftThreadByTheOldNumber() throws {
        let rows = DiffRow.rows(of: try file(), threads: [thread(line: 26, side: .left)])

        let index = try #require(rows.firstIndex { row in
            guard case .thread = row else { return false }
            return true
        })
        guard case .line(_, let previous) = rows[index - 1] else {
            Issue.record("nad bublinou není řádek")
            return
        }
        // Starý řádek 26 je ten odebraný — nový 26 je „nové“, tedy jiný kód.
        #expect(previous.oldNumber == 26)
        #expect(previous.newNumber == nil)
    }

    /// Totéž číslo na obou stranách znamená jiný řádek. Bez `side` by obojí skončilo na
    /// stejném místě.
    @Test("Stejné číslo na levé a pravé straně dá jiné umístění")
    func placesLeftAndRightDifferently() throws {
        let left = DiffRow.rows(of: try file(), threads: [thread(line: 26, side: .left)])
        let right = DiffRow.rows(of: try file(), threads: [thread(line: 26, side: .right)])

        func lineAboveBubble(_ rows: [DiffRow]) -> DiffLine? {
            guard let index = rows.firstIndex(where: { row in
                if case .thread = row { true } else { false }
            }), case .line(_, let line) = rows[index - 1] else { return nil }
            return line
        }

        #expect(lineAboveBubble(left)?.text != lineAboveBubble(right)?.text)
        #expect(lineAboveBubble(right)?.newNumber == 26)
    }

    /// Chybějící `side` se bere jako `right` — je to výchozí strana GitHubu.
    @Test("Vlákno bez strany se kotví jako pravé")
    func treatsAMissingSideAsRight() throws {
        let rows = DiffRow.rows(of: try file(), threads: [thread(line: 26, side: nil)])

        #expect(threadRows(rows).count == 1)
    }

    // MARK: - Zkrácení

    @Test("Useknuté vlákno hlásí, kolik chybí")
    func reportsMissingComments() throws {
        let rows = DiffRow.rows(
            of: try file(),
            threads: [thread(line: 27, comments: [comment()], total: 5)]
        )
        let bubble = try #require(threadRows(rows).first)

        #expect(bubble.comments.isTruncated)
        #expect(bubble.comments.missing == 4)
    }
}
