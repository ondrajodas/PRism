import Foundation
import Testing

@testable import PRism

/// Kam doopravdy vede kotva skoku na nález.
///
/// Vzniklo u #187, ale chyba je z #157: od slévání řádků do bloků nese blok `id` **jen toho
/// prvního**, takže `scrollTo` na řádek uprostřed úseku míří na id, které v seznamu není —
/// a tiše neudělá nic. Skok z panelu měl tutéž vadu; jen si jí nikdo nevšiml, protože nález
/// na prvním řádku bloku (hned za hlavičkou hunku) fungoval.
///
/// Tvrzení, které tenhle soubor hlídá: **kotva se po překladu musí trefit do něčeho, co je
/// v seznamu.**
@Suite("Skok na nález — cíl existuje v seznamu")
struct DiffJumpTargetTests {
    private func file(path: String = "Cart.php") throws -> FileDiff {
        let diff = DiffParser.parse([
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -25,6 +25,7 @@",
            " kontext",
            " druhý",
            "-staré",
            "+nové",
            "+navíc",
            " další",
            " poslední",
        ].joined(separator: "\n"))
        return try #require(diff.files.first)
    }

    private func diff(path: String = "Cart.php") throws -> Diff {
        DiffParser.parse([
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -25,6 +25,7 @@",
            " kontext",
            " druhý",
            "-staré",
            "+nové",
            "+navíc",
            " další",
            " poslední",
        ].joined(separator: "\n"))
    }

    /// Co je v seznamu doopravdy vidět — tedy id, na která `scrollTo` může trefit.
    private func visibleIDs(_ file: FileDiff, layout: DiffLayout) -> Set<String> {
        let rows = DiffRow.rows(of: file, layout: layout)
        let blocked = layout == .split ? DiffRow.blockedPairs(rows) : DiffRow.blocked(rows)
        return Set(blocked.map(\.id))
    }

    @Test("Kotva na řádek uprostřed bloku se přeloží na blok", arguments: [DiffLayout.unified, .split])
    func anAnchorInsideABlockResolvesToTheBlock(layout: DiffLayout) throws {
        let file = try file()
        let diff = try diff()
        let visible = visibleIDs(file, layout: layout)

        // Každý řádek nového souboru je legitimní cíl nálezu.
        for line in 25...30 {
            let anchor = try #require(DiffRow.anchor(in: diff, file: "Cart.php", line: line))
            let rows = DiffRow.rows(of: file, layout: layout)
            let blocked = layout == .split ? DiffRow.blockedPairs(rows) : DiffRow.blocked(rows)
            let resolved = DiffRow.blockIDs(in: blocked)[anchor] ?? anchor

            #expect(
                visible.contains(resolved),
                "řádek \(line) v pohledu \(layout) míří na \(resolved), a to v seznamu není"
            )
        }
    }

    /// Kotva se počítá nad **slitými** řádky, takže se u #446 musela ověřit i tam, kde slití
    /// není úplné: poznámka `git`u zůstane ve split pohledu samostatným `.line` (viz
    /// `DiffRenderedRowsTests`) a **rozděluje** kolem sebe bloky. Kdyby ji překlad nepokrýval,
    /// skok na řádek za ní by mířil na id, které v seznamu není.
    @Test("Kotva se trefí i v souboru s poznámkou gitu", arguments: [DiffLayout.unified, .split])
    func anAnchorSurvivesAGitNote(layout: DiffLayout) throws {
        let text = [
            "diff --git a/Cart.php b/Cart.php",
            "--- a/Cart.php",
            "+++ b/Cart.php",
            "@@ -25,4 +25,4 @@",
            " kontext",
            "-staré",
            "\\ No newline at end of file",
            "+nové",
            " další",
        ].joined(separator: "\n")
        let diff = DiffParser.parse(text)
        let file = try #require(diff.files.first)
        let visible = visibleIDs(file, layout: layout)
        let rows = DiffRow.rows(of: file, layout: layout)
        let index = DiffRow.blockIDs(in: layout == .split ? DiffRow.blockedPairs(rows) : DiffRow.blocked(rows))

        for line in 25...27 {
            let anchor = try #require(DiffRow.anchor(in: diff, file: "Cart.php", line: line))
            #expect(anchor != file.id, "řádek \(line) má být v diffu, ne u hlavičky souboru")
            #expect(
                visible.contains(index[anchor] ?? anchor),
                "řádek \(line) v pohledu \(layout) míří mimo seznam"
            )
        }
    }

    @Test("Bez překladu se kotva do seznamu netrefí")
    func withoutTheTranslationTheAnchorMisses() throws {
        // Tohle je ta chyba sama: kdyby se překlad zase ztratil, tenhle test zůstane zelený
        // a ten nad ním spadne — takže je z dvojice poznat, že se nezměnilo zadání, ale kód.
        let file = try file()
        let diff = try diff()
        let visible = visibleIDs(file, layout: .unified)
        let anchor = try #require(DiffRow.anchor(in: diff, file: "Cart.php", line: 27))

        #expect(!visible.contains(anchor))
    }

    @Test("Řádek mimo blok se mapuje sám na sebe")
    func aRowOutsideABlockMapsToItself() throws {
        // Hlavičky hunků, bubliny a expandery se neslévají — a překlad je nesmí zahodit,
        // jinak by přestal fungovat skok na soubor a na hlavičku.
        let file = try file()
        let rows = DiffRow.rows(of: file)
        let index = DiffRow.blockIDs(in: DiffRow.blocked(rows))

        for row in DiffRow.blocked(rows) where !isBlock(row) {
            #expect(index[row.id] == row.id)
        }
    }

    @Test("Blok si pamatuje všechny řádky, které do něj spadly")
    func aBlockRemembersEveryRowItSwallowed() throws {
        let file = try file()
        let rows = DiffRow.rows(of: file)
        let lineIDs = rows.compactMap { row -> String? in
            guard case .line(let id, _) = row else { return nil }
            return id
        }
        let index = DiffRow.blockIDs(in: DiffRow.blocked(rows))

        // Ani jeden řádek se nesmí ztratit — právě ztracený řádek je ten, na který skok nejde.
        for id in lineIDs { #expect(index[id] != nil) }
    }

    private func isBlock(_ row: DiffRow) -> Bool {
        switch row {
        case .block, .pairBlock: true
        default: false
        }
    }
}
