import Foundation
import Testing

@testable import PRism

/// Párování řádků pro pohled **vedle sebe**. Čisté skládání řádků, nic se nemockuje.
///
/// To hlavní není, jak dvojice vypadají, ale **že se z nich poskládají přesně původní
/// řádky** — žádný se neztratí ani nezdvojí. Stejný druh záruky jako u `SyntaxHighlighteru`,
/// kde spojení run musí dát původní řádek: pohled je způsob zobrazení, takže nesmí měnit
/// obsah diffu.
@Suite("DiffRow — dvojice vedle sebe")
struct DiffPairTests {
    // MARK: - Pomocníci

    private func file(_ diff: String) throws -> FileDiff {
        try #require(DiffParser.parse(diff).files.first)
    }

    /// Soubor, ve kterém se přepisuje blok: dva odebrané řádky a dva přidané mezi kontextem.
    private func rewritten() throws -> FileDiff {
        try file("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -10,4 +10,4 @@
             před
            -staré A
            -staré B
            +nové A
            +nové B
             za
            """)
    }

    private func pairs(in rows: [DiffRow]) -> [(left: DiffLine?, right: DiffLine?)] {
        rows.compactMap { row in
            guard case .pair(_, let left, let right) = row else { return nil }
            return (left, right)
        }
    }

    private func text(_ line: DiffLine?) -> String? { line?.text }

    /// Kolikrát se který řádek v seznamu objevil. Porovnáním počtů se pozná ztráta
    /// i zdvojení, na které samotné porovnání pořadí nestačí.
    private func counts(_ lines: [DiffLine]) -> [DiffLine: Int] {
        lines.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    // MARK: - Párování

    @Test("Stejně dlouhé bloky se spárují po řádcích")
    func pairsBlocksOfEqualLength() throws {
        let rows = DiffRow.rows(of: try rewritten(), layout: .split)

        let changed = pairs(in: rows).filter { $0.left?.kind == .removed || $0.right?.kind == .added }
        #expect(changed.map { text($0.left) } == ["staré A", "staré B"])
        #expect(changed.map { text($0.right) } == ["nové A", "nové B"])
    }

    @Test("Přebytek odebraných dostane prázdnou pravou stranu")
    func leavesTheRightSideEmptyForExtraRemovedLines() throws {
        let file = try file("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -10,4 +10,2 @@
             před
            -staré A
            -staré B
            -staré C
            +nové A
            """)

        let changed = pairs(in: DiffRow.rows(of: file, layout: .split))
            .filter { $0.left?.kind == .removed || $0.right?.kind == .added }
        #expect(changed.map { text($0.left) } == ["staré A", "staré B", "staré C"])
        #expect(changed.map { text($0.right) } == ["nové A", nil, nil])
    }

    @Test("Přebytek přidaných dostane prázdnou levou stranu")
    func leavesTheLeftSideEmptyForExtraAddedLines() throws {
        let file = try file("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -10,2 +10,4 @@
             před
            -staré A
            +nové A
            +nové B
            +nové C
            """)

        let changed = pairs(in: DiffRow.rows(of: file, layout: .split))
            .filter { $0.left?.kind == .removed || $0.right?.kind == .added }
        #expect(changed.map { text($0.left) } == ["staré A", nil, nil])
        #expect(changed.map { text($0.right) } == ["nové A", "nové B", "nové C"])
    }

    @Test("Samostatný blok odebraných stojí jen vlevo")
    func putsARemovedOnlyBlockOnTheLeft() throws {
        let file = try file("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -10,3 +10,1 @@
             před
            -staré A
            -staré B
            """)

        let changed = pairs(in: DiffRow.rows(of: file, layout: .split)).filter { $0.left?.kind == .removed }
        #expect(changed.map { text($0.left) } == ["staré A", "staré B"])
        #expect(changed.allSatisfy { $0.right == nil })
    }

    @Test("Samostatný blok přidaných stojí jen vpravo")
    func putsAnAddedOnlyBlockOnTheRight() throws {
        let file = try file("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -10,1 +10,3 @@
             před
            +nové A
            +nové B
            """)

        let changed = pairs(in: DiffRow.rows(of: file, layout: .split)).filter { $0.right?.kind == .added }
        #expect(changed.map { text($0.right) } == ["nové A", "nové B"])
        #expect(changed.allSatisfy { $0.left == nil })
    }

    /// Kontextový řádek je **jeden** řádek souboru se dvěma čísly, takže na obou stranách
    /// stojí tatáž hodnota — z rovnosti se to pozná dál v kódu (`sourceLines`), a proto se
    /// u něj vlákno ani nález nezdvojí.
    @Test("Kontextový řádek stojí na obou stranách jako jedna hodnota")
    func putsAContextLineOnBothSides() throws {
        let rows = DiffRow.rows(of: try rewritten(), layout: .split)

        let context = try #require(pairs(in: rows).first { $0.left?.kind == .context })
        #expect(context.left == context.right)
        #expect(context.left?.oldNumber == 10)
        #expect(context.left?.newNumber == 10)
    }

    /// Poznámka `git`u není obsah souboru, takže nemá stranu — dělit ji na poloviny nemá
    /// co znamenat.
    @Test("Meta řádek jde přes celou šířku")
    func keepsAMetaLineFullWidth() throws {
        let file = try file("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -10,2 +10,2 @@
             před
            -staré
            \\ No newline at end of file
            +nové
            """)

        let rows = DiffRow.rows(of: file, layout: .split)

        let meta = rows.compactMap { row -> DiffLine? in
            guard case .line(_, let line) = row, line.kind == .meta else { return nil }
            return line
        }
        #expect(meta.count == 1)
        // A protože poznámka blok uzavře, odebraný řádek zůstane sám vlevo a přidaný sám
        // vpravo — spárovat je přes poznámku by znamenalo tvrdit, že spolu souvisí.
        let changed = pairs(in: rows).filter { $0.left?.kind == .removed || $0.right?.kind == .added }
        #expect(changed.map { text($0.left) } == ["staré", nil])
        #expect(changed.map { text($0.right) } == [nil, "nové"])
    }

    /// `+` po `-` je přepsání téhož místa, ale `-` po `+` už je další skupina.
    @Test("Odebrané řádky po přidaných začínají nový blok")
    func doesNotPairRemovedLinesWithEarlierAddedLines() throws {
        let file = try file("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -10,2 +10,2 @@
            +nové
            -staré
            """)

        let changed = pairs(in: DiffRow.rows(of: file, layout: .split))
        #expect(changed.map { text($0.left) } == [nil, "staré"])
        #expect(changed.map { text($0.right) } == ["nové", nil])
    }

    @Test("Nový soubor stojí celý vpravo")
    func putsANewFileOnTheRight() throws {
        let file = try file("""
            diff --git a/New.php b/New.php
            new file mode 100644
            --- /dev/null
            +++ b/New.php
            @@ -0,0 +1,2 @@
            +první
            +druhý
            """)

        let changed = pairs(in: DiffRow.rows(of: file, layout: .split))
        #expect(changed.allSatisfy { $0.left == nil })
        #expect(changed.map { text($0.right) } == ["první", "druhý"])
    }

    @Test("Smazaný soubor stojí celý vlevo")
    func putsADeletedFileOnTheLeft() throws {
        let file = try file(try Fixture.text("gh/pr-diff-deleted.diff"))

        let changed = pairs(in: DiffRow.rows(of: file, layout: .split))
        #expect(!changed.isEmpty)
        #expect(changed.allSatisfy { $0.right == nil })
        #expect(changed.allSatisfy { $0.left?.kind == .removed })
    }

    @Test("Hlavička hunku a rozbalovací řádek zůstávají přes celou šířku")
    func keepsHeadersAndExpandersFullWidth() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
        let file = try #require(diff.files.first { $0.displayPath == "CLAUDE.md" })

        let unified = DiffRow.rows(of: file)
        let split = DiffRow.rows(of: file, layout: .split)

        func kinds(_ rows: [DiffRow]) -> [String] {
            rows.compactMap { row in
                switch row {
                case .hunk: "hunk"
                case .expander: "expander"
                default: nil
                }
            }
        }
        #expect(kinds(split) == kinds(unified))
        #expect(!kinds(split).isEmpty)
    }

    // MARK: - Invariant: nic se neztratí ani nezdvojí

    @Test("Z dvojic se poskládají přesně původní řádky", arguments: [
        "gh/pr-diff-ordinary.diff",
        "gh/pr-diff-rename.diff",
        "gh/pr-diff-deleted.diff",
        "gh/pr-diff-binary.diff",
    ])
    func keepsEveryLineExactlyOnce(fixture: String) throws {
        for file in DiffParser.parse(try Fixture.text(fixture)).files {
            let unified = DiffRow.rows(of: file).flatMap(\.sourceLines)
            let split = DiffRow.rows(of: file, layout: .split).flatMap(\.sourceLines)

            #expect(counts(split) == counts(unified), "soubor \(file.displayPath)")
        }
    }

    /// Počty samy o sobě nehlídají pořadí, a to je druhá polovina toho, že se diff nezmění:
    /// levá strana musí jít ve pořadí staré verze souboru, pravá ve pořadí nové.
    @Test("Pořadí na každé straně kopíruje původní diff", arguments: [
        "gh/pr-diff-ordinary.diff",
        "gh/pr-diff-rename.diff",
        "gh/pr-diff-deleted.diff",
        "gh/pr-diff-binary.diff",
    ])
    func keepsTheOrderOnEachSide(fixture: String) throws {
        for file in DiffParser.parse(try Fixture.text(fixture)).files {
            let unified = DiffRow.rows(of: file).flatMap(\.sourceLines)
            let split = pairs(in: DiffRow.rows(of: file, layout: .split))

            #expect(
                split.compactMap(\.left) == unified.filter { $0.kind == .removed || $0.kind == .context },
                "levá strana v \(file.displayPath)"
            )
            #expect(
                split.compactMap(\.right) == unified.filter { $0.kind == .added || $0.kind == .context },
                "pravá strana v \(file.displayPath)"
            )
        }
    }

    // MARK: - Identita

    /// Kotvy z nálezů se hledají podle `newNumber`, a ten je vždycky vpravo — proto je
    /// identita dvojice identita **pravého** řádku. Levá se použije, jen když pravá není.
    @Test("Identita dvojice je identita pravého řádku")
    func takesItsIdentityFromTheRightSide() throws {
        let file = try rewritten()
        let unified = DiffRow.rows(of: file)
        let split = DiffRow.rows(of: file, layout: .split)

        func id(ofLineWith text: String, in rows: [DiffRow]) throws -> String {
            try #require(rows.first { $0.sourceLines.contains { $0.text == text } }).id
        }
        #expect(try id(ofLineWith: "nové A", in: split) == (try id(ofLineWith: "nové A", in: unified)))
        // Levý řádek dvojice svoje původní id **ztrácí** — dvojice se hlásí tím pravým.
        #expect(try id(ofLineWith: "staré A", in: split) == (try id(ofLineWith: "nové A", in: unified)))
    }

    @Test("Dvojice bez pravé strany se hlásí levým řádkem")
    func fallsBackToTheLeftIdentity() throws {
        let file = try file("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -10,2 +10,1 @@
             před
            -staré
            """)

        let unified = DiffRow.rows(of: file)
        let split = DiffRow.rows(of: file, layout: .split)

        func id(ofLineWith text: String, in rows: [DiffRow]) throws -> String {
            try #require(rows.first { $0.sourceLines.contains { $0.text == text } }).id
        }
        #expect(try id(ofLineWith: "staré", in: split) == (try id(ofLineWith: "staré", in: unified)))
    }
}
