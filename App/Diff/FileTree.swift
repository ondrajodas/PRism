import Foundation

/// Uzel stromu souborů — složka, nebo soubor v ní.
///
/// Slouží k navigaci: plochý seznam cest se u PR přes víc adresářů čte špatně, protože
/// společné prefixy zaberou většinu šířky a oko si je musí odfiltrovat samo.
struct FileTreeNode: Identifiable, Hashable, Sendable {
    /// Celá cesta k uzlu. Jméno samo o sobě identitu nedá — `a/x.swift` a `b/x.swift`
    /// jsou dva různé soubory.
    let id: String
    /// Co je na řádku. U slitých složek je to celý slitý úsek (`App/Views/Diff`).
    let name: String
    /// `nil` u složky.
    let file: FileDiff?
    /// `nil` u souboru — `OutlineGroup` podle toho pozná list.
    let children: [FileTreeNode]?

    var additions: Int {
        file?.additions ?? (children ?? []).reduce(0) { $0 + $1.additions }
    }

    var deletions: Int {
        file?.deletions ?? (children ?? []).reduce(0) { $0 + $1.deletions }
    }

    /// Strom nad soubory diffu.
    ///
    /// **Pořadí kopíruje diff**, nesetřiďuje se znovu: `git` cesty řadí sám, takže druhé
    /// pravidlo řazení by nic nepřidalo a jen by se mohlo s diffem rozejít. Uvnitř složky
    /// jdou podsložky před soubory.
    static func tree(of files: [FileDiff]) -> [FileTreeNode] {
        nodes(from: files.map { (components: $0.displayPath.split(separator: "/").map(String.init), file: $0) },
              at: "")
    }

    private typealias Entry = (components: [String], file: FileDiff)

    private static func nodes(from entries: [Entry], at prefix: String) -> [FileTreeNode] {
        var result: [FileTreeNode] = []
        var directories: [String] = []
        var grouped: [String: [Entry]] = [:]

        for entry in entries {
            guard let head = entry.components.first else { continue }
            guard entry.components.count > 1 else {
                result.append(FileTreeNode(id: path(prefix, head), name: head, file: entry.file, children: nil))
                continue
            }
            if grouped[head] == nil { directories.append(head) }
            grouped[head, default: []].append((Array(entry.components.dropFirst()), entry.file))
        }

        // Složky napřed: v seznamu se pak dá sjet očima po struktuře, ne po souborech.
        return directories.map { directory in
            collapsed(directory: directory, entries: grouped[directory] ?? [], at: prefix)
        } + result
    }

    /// Složka s jediným potomkem se slévá do jednoho řádku (`App/Views/Diff`). Bez toho
    /// ubere hluboká cesta víc místa, než strom přidá.
    private static func collapsed(directory: String, entries: [Entry], at prefix: String) -> FileTreeNode {
        let here = path(prefix, directory)
        let children = nodes(from: entries, at: here)

        if children.count == 1, let only = children.first, only.file == nil {
            return FileTreeNode(
                id: only.id,
                name: "\(directory)/\(only.name)",
                file: nil,
                children: only.children
            )
        }
        return FileTreeNode(id: here, name: directory, file: nil, children: children)
    }

    private static func path(_ prefix: String, _ name: String) -> String {
        prefix.isEmpty ? name : "\(prefix)/\(name)"
    }
}
