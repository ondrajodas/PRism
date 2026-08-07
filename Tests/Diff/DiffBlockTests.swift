import Foundation
import Testing

@testable import PRism

/// Slučování řádků diffu do bloků (#157) — na tom stojí selekce přes víc řádků.
///
/// Blok se skládá **až po zavěšení bublin**, takže se testuje přes `DiffRow.rows(of:)`, ne jen
/// nad umělým seznamem: to hlavní tvrzení je, že blok **končí** tam, kde do diffu něco vstoupí.
@Suite("Bloky řádků")
struct DiffBlockTests {
    private func file(path: String = "Cart.php") throws -> FileDiff {
        let diff = DiffParser.parse([
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -25,4 +25,5 @@",
            " kontext",
            "-staré",
            "+nové",
            "+navíc",
            " další",
        ].joined(separator: "\n"))
        return try #require(diff.files.first)
    }

    private func blocks(_ rows: [DiffRow]) -> [DiffBlock] {
        rows.compactMap { row in
            guard case .block(_, let block) = row else { return nil }
            return block
        }
    }

    private func thread(line: Int) -> ReviewThread {
        ReviewThread(
            id: "t\(line)",
            path: "Cart.php",
            line: line,
            originalLine: line,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    @Test("Řádky bez bublin dají jeden blok")
    func mergesEverythingWithoutBubbles() throws {
        let rows = DiffRow.blocked(DiffRow.rows(of: try file()))

        let blocks = blocks(rows)
        #expect(blocks.count == 1)
        #expect(blocks[0].lines.count == 5)
        // A žádný samostatný `.line` v seznamu nezůstal — jinak by se kreslil dvakrát.
        #expect(!rows.contains { if case .line = $0 { true } else { false } })
    }

    /// **To hlavní.** Bublina blok rozdělí, takže selekce jde přes úsek mezi bublinami — a řádky
    /// se nekreslí přes ni.
    @Test("Bublina blok rozdělí")
    func splitsOnABubble() throws {
        let rows = DiffRow.blocked(DiffRow.rows(of: try file(), threads: [thread(line: 26)]))

        let blocks = blocks(rows)
        #expect(blocks.count == 2)
        // Vlákno na novém řádku 26 sedí na `+nové`, tedy na **třetím** řádku hunku (kontext 25,
        // odebraný 26, přidaný 26) — takže první blok má tři řádky a druhý ten zbylý.
        #expect(blocks[0].lines.count == 3)
        #expect(blocks[1].lines.count == 2)
        // Bublina stojí mezi nimi, ne na konci.
        let index = try #require(rows.firstIndex { if case .thread = $0 { true } else { false } })
        #expect(index > 0 && index < rows.count - 1)
    }

    /// Hlavička hunku i rozbalovací řádek zůstanou **samostatné**, protože blok ukončují. U souboru,
    /// jehož hunk nezačíná na prvním řádku, jde navíc před hlavičkou ještě expander na mezeru —
    /// první verze testu čekala hlavičku hned a spadla.
    @Test("Hlavička hunku a expander jsou mimo blok")
    func keepsHeadersOutsideBlocks() throws {
        let rows = DiffRow.blocked(DiffRow.rows(of: try file()))

        let kinds = rows.map { row -> String in
            switch row {
            case .hunk: "hunk"
            case .expander: "expander"
            case .block: "block"
            default: "jiné"
            }
        }
        #expect(kinds.contains("hunk"))
        #expect(kinds.contains("block"))
        // Blok nikdy nestojí před hlavičkou svého hunku.
        let hunkIndex = try #require(kinds.firstIndex(of: "hunk"))
        let blockIndex = try #require(kinds.firstIndex(of: "block"))
        #expect(hunkIndex < blockIndex)
    }

    /// Ve split pohledu se slévají **dvojice** (`blockedPairs`), ne jednotlivé řádky: sloupce si
    /// musí odpovídat řádek po řádku, jinak přestane platit, že vlevo a vpravo je tentýž řádek.
    @Test("Split pohled dá dvojité bloky")
    func mergesPairsInSplitLayout() throws {
        let rows = DiffRow.blockedPairs(DiffRow.rows(of: try file(), layout: .split))

        let pairs: [DiffPairBlock] = rows.compactMap { row in
            guard case .pairBlock(_, let block) = row else { return nil }
            return block
        }
        #expect(pairs.count == 1)
        // Obě strany mají **stejný počet** řádků — na tom zarovnání stojí.
        #expect(pairs[0].left.count == pairs[0].right.count)
        // Prázdná protistrana je `nil`, ne vynechaný řádek: odebraný řádek vpravo neexistuje.
        #expect(pairs[0].left.contains { $0 == nil } || pairs[0].right.contains { $0 == nil })
        // A žádná samostatná dvojice v seznamu nezůstala.
        #expect(!rows.contains { if case .pair = $0 { true } else { false } })
    }

    /// Bublina rozdělí i dvojité bloky — jinak by se kreslila přes kód.
    @Test("Bublina rozdělí i dvojitý blok")
    func splitsPairBlocksOnABubble() throws {
        let rows = DiffRow.blockedPairs(DiffRow.rows(of: try file(), layout: .split, threads: [thread(line: 26)]))

        let pairs = rows.filter { if case .pairBlock = $0 { true } else { false } }
        #expect(pairs.count == 2)
    }

    /// Řádky pohledu pod sebou se do dvojitých bloků **nesmí** dostat a naopak — každý pohled má
    /// vlastní slučování a záměna by dala prázdný diff.
    @Test("Slučování se mezi pohledy nepletou")
    func keepsTheTwoLayoutsApart() throws {
        let unified = DiffRow.rows(of: try file())
        let split = DiffRow.rows(of: try file(), layout: .split)

        #expect(blocks(DiffRow.blockedPairs(unified)).isEmpty)
        #expect(DiffRow.blocked(split).contains { if case .pair = $0 { true } else { false } })
    }

    /// Identita bloku nese `id` prvního řádku, takže je stabilní a nekříží se s ostatními řádky.
    @Test("Bloky mají vlastní a stabilní identitu")
    func hasStableIdentity() throws {
        let rows = DiffRow.blocked(DiffRow.rows(of: try file(), threads: [thread(line: 26)]))

        #expect(Set(rows.map(\.id)).count == rows.count)
        let again = DiffRow.blocked(DiffRow.rows(of: try file(), threads: [thread(line: 26)]))
        #expect(rows.map(\.id) == again.map(\.id))
    }

    @Test("Prázdný seznam řádků nedá prázdný blok")
    func makesNoEmptyBlock() {
        #expect(DiffRow.blocked([]).isEmpty)
    }
}
