import Foundation
import Testing

@testable import PRism

/// Strom souborů pro navigaci v diffu.
@Suite("FileTree")
struct FileTreeTests {
    /// Počty řádků se sem **nepředávají** (#219): strom je nezobrazuje a `FileTreeNode` je od
    /// #219 ani nesčítá, takže parametry, které by šly nastavit, by tvrdily opak.
    private func file(_ path: String) -> FileDiff {
        FileDiff(
            oldPath: path,
            newPath: path,
            change: .modified,
            isBinary: false,
            hunks: [
                DiffHunk(
                    oldStart: 1,
                    oldCount: 1,
                    newStart: 1,
                    newCount: 1,
                    heading: "",
                    lines: [DiffLine(kind: .added, oldNumber: nil, newNumber: 1, text: "+")]
                )
            ]
        )
    }

    private func names(_ nodes: [FileTreeNode]) -> [String] {
        nodes.map(\.name)
    }

    @Test("Soubor v kořeni nemá nad sebou složku")
    func keepsARootFileAtTheTop() {
        let tree = FileTreeNode.tree(of: [file("README.md")])

        #expect(names(tree) == ["README.md"])
        #expect(tree.first?.children == nil)
    }

    /// Bez slévání by hluboká cesta ubrala víc místa, než strom přidá.
    @Test("Složky s jediným potomkem se slijí do jednoho řádku")
    func collapsesSingleChildDirectories() {
        let tree = FileTreeNode.tree(of: [file("App/Views/Diff/Row.swift"), file("App/Views/Diff/Line.swift")])

        #expect(names(tree) == ["App/Views/Diff"])
        #expect(names(tree.first?.children ?? []) == ["Row.swift", "Line.swift"])
    }

    @Test("Větvení se neslévá")
    func keepsABranchingDirectoryApart() {
        let tree = FileTreeNode.tree(of: [file("App/Views/Row.swift"), file("App/Main.swift")])

        #expect(names(tree) == ["App"])
        let children = tree.first?.children ?? []
        // Složky napřed, soubory za nimi.
        #expect(names(children) == ["Views", "Main.swift"])
    }

    @Test("Pořadí souborů kopíruje diff")
    func keepsTheOrderOfTheDiff() {
        let tree = FileTreeNode.tree(of: [file("z.md"), file("a.md")])

        #expect(names(tree) == ["z.md", "a.md"])
    }

    // Test „složka sčítá, co je pod ní“ tu byl do #219. Sečtené počty kreslil jedině popover
    // `Přejít na soubor`; s ním odešly z modelu, takže by tenhle test hlídal vlastnost, kterou
    // nikdo nečte.

    @Test("Uzel souboru nese svůj soubor, složka ne")
    func carriesTheFileOnLeavesOnly() throws {
        let tree = FileTreeNode.tree(of: [file("App/a.swift")])

        let directory = try #require(tree.first)
        #expect(directory.file == nil)
        #expect(directory.children?.first?.file?.displayPath == "App/a.swift")
    }

    @Test("Identity uzlů se nekříží")
    func givesEveryNodeItsOwnIdentity() {
        let tree = FileTreeNode.tree(of: [file("a/x.swift"), file("b/x.swift")])
        let identifiers = tree.flatMap { [$0.id] + ($0.children ?? []).map(\.id) }

        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test("Prázdný diff dá prázdný strom")
    func returnsNothingForAnEmptyDiff() {
        #expect(FileTreeNode.tree(of: []).isEmpty)
    }
}
