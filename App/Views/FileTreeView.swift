import SwiftUI

/// Strom souborů diffu pro skok na soubor.
///
/// Strom, ne plochý seznam cest: u PR přes víc adresářů zaberou společné prefixy většinu
/// šířky a hledá se v tom očima špatně.
///
/// Vykresluje se ručně, ne přes `OutlineGroup`: ten odsazuje jen uvnitř `List`u, a bez
/// odsazení není z řádků poznat, co je pod čím.
struct FileTreeView: View {
    let files: [FileDiff]
    let jump: (FileDiff) -> Void

    /// Sbalené složky. Výchozí je **rozbaleno** — seznam slouží ke skoku na soubor, takže
    /// soubory mají být vidět.
    @State private var collapsed: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(FileTreeNode.tree(of: files)) { node in
                    FileTreeBranch(node: node, depth: 0, collapsed: $collapsed, jump: jump)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
        .frame(width: 420, height: 320)
    }
}

/// Jedna větev stromu — řádek a pod ním potomci, když je rozbalená.
private struct FileTreeBranch: View {
    let node: FileTreeNode
    let depth: Int
    @Binding var collapsed: Set<String>
    let jump: (FileDiff) -> Void

    /// O kolik se odsazuje každá úroveň. Šířka šipky a ikony, ať řádky drží sloupec.
    private static let indent = 18.0

    var body: some View {
        row
        if let children = node.children, !collapsed.contains(node.id) {
            ForEach(children) { child in
                FileTreeBranch(node: child, depth: depth + 1, collapsed: $collapsed, jump: jump)
            }
        }
    }

    @ViewBuilder private var row: some View {
        if let file = node.file {
            Button { jump(file) } label: { content(file: file) }
                .buttonStyle(.plain)
        } else {
            Button { toggle() } label: { content(file: nil) }
                .buttonStyle(.plain)
        }
    }

    private func toggle() {
        if collapsed.contains(node.id) { collapsed.remove(node.id) } else { collapsed.insert(node.id) }
    }

    private func content(file: FileDiff?) -> some View {
        HStack(spacing: 6) {
            chevron
            Image(systemName: file == nil ? "folder" : symbol(of: file))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(verbatim: node.name)
                .font(.callout)
                .foregroundStyle(file == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.head)
            if let badge = file.flatMap(badge(of:)) {
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .background(.quaternary, in: .capsule)
            }
            Spacer(minLength: 8)
            Text(verbatim: "+\(node.additions) −\(node.deletions)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .padding(.leading, Double(depth) * Self.indent)
        .contentShape(.rect)
    }

    /// Soubor šipku nemá, ale místo po ní ano — jinak by se jméno nesrovnalo se jmény
    /// složek na stejné úrovni.
    @ViewBuilder private var chevron: some View {
        if node.children != nil {
            Image(systemName: collapsed.contains(node.id) ? "chevron.right" : "chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 10)
        } else {
            Color.clear.frame(width: 10, height: 1)
        }
    }

    private func symbol(of file: FileDiff?) -> String {
        guard let file else { return "doc" }
        if file.isBinary { return "doc.badge.gearshape" }
        switch file.change {
        case .added: return "plus.square"
        case .deleted: return "minus.square"
        case .renamed: return "arrow.triangle.turn.up.right.diamond"
        case .modified: return "doc.text"
        }
    }

    private func badge(of file: FileDiff) -> String? {
        if file.isBinary { return "binární" }
        switch file.change {
        case .added: return "nový"
        case .deleted: return "smazaný"
        case .renamed: return "přejmenovaný"
        case .modified: return nil
        }
    }
}
