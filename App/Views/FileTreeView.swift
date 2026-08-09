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
    /// Které soubory nesou nález (#197). Prázdné = nekreslí se žádná značka.
    var markers: [String: FileMarker] = [:]
    /// Úsporná sazba pro levý sloupec u diffu (#197).
    ///
    /// Ve sloupci 210 bodů širokém se **nevejde nic než jméno a značka**: počty `+/−` zaberou
    /// přes padesát bodů a slovní odznak (`nový`) další čtyřicet, takže na jméno zbyde `…S.md`.
    /// Návrh to tak taky kreslí — počty jsou u hlavičky souboru v diffu, kde je na ně místo.
    /// Popover (420 bodů) zůstává v plné sazbě.
    var isCompact = false
    let jump: (FileDiff) -> Void

    /// Sbalené složky. Výchozí je **rozbaleno** — seznam slouží ke skoku na soubor, takže
    /// soubory mají být vidět.
    @State private var collapsed: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(FileTreeNode.tree(of: files)) { node in
                    FileTreeBranch(
                        node: node,
                        depth: 0,
                        collapsed: $collapsed,
                        markers: markers,
                        isCompact: isCompact,
                        jump: jump
                    )
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
    }
}

/// Jedna větev stromu — řádek a pod ním potomci, když je rozbalená.
private struct FileTreeBranch: View {
    let node: FileTreeNode
    let depth: Int
    @Binding var collapsed: Set<String>
    let markers: [String: FileMarker]
    let isCompact: Bool
    let jump: (FileDiff) -> Void

    /// O kolik se odsazuje každá úroveň. Šířka šipky a ikony, ať řádky drží sloupec.
    /// V úzkém sloupci míň — každá úroveň jinak ukousne z jména.
    private var indent: Double { isCompact ? 11 : 18 }

    var body: some View {
        row
        if let children = node.children, !collapsed.contains(node.id) {
            ForEach(children) { child in
                FileTreeBranch(
                    node: child,
                    depth: depth + 1,
                    collapsed: $collapsed,
                    markers: markers,
                    isCompact: isCompact,
                    jump: jump
                )
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
                // Ikona nese **druh změny barvou**, ne jen tvarem: zelená přidává, červená
                // maže, modrá přejmenovává. Tvar sám se u `plus.square` a `minus.square` čte
                // až po zaostření, kdežto barva se vezme periferně — tatáž úvaha jako
                // u proužku v řádku fronty. Složka a obyčejná změna zůstávají tlumené,
                // aby v seznamu svítilo jen to, co je zvláštní.
                .foregroundStyle(file.flatMap(tint(of:)) ?? .secondary)
                .frame(width: 14)
            Text(verbatim: node.name)
                .font(isCompact ? .caption : .callout)
                .foregroundStyle(file == nil ? .secondary : .primary)
                .lineLimit(1)
                // **Soubor se ořezává zezadu, složka zepředu.** U jména souboru nese význam
                // začátek (`SecretClient.php` a `SecretClientTest.php` se poznají jen podle
                // něj), kdežto u cesty ke složce ta poslední část.
                .truncationMode(file == nil ? .head : .tail)
            if let marker = file.flatMap({ markers[$0.displayPath] }) {
                // Puntík, ne text: v sloupci 210 bodů širokém je místo na cestu, ne na slovo.
                // Barva je tatáž škála jako v řádku fronty a na kartě nálezu.
                Circle()
                    .fill(marker == .blocking ? Color.red : Color.orange)
                    .frame(width: 6, height: 6)
                    .help(marker == .blocking ? "Je tu blokující nález" : "Jsou tu nálezy")
            }
            if let badge = file.flatMap(badge(of:)), !isCompact {
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .background(.quaternary, in: .capsule)
            }
            Spacer(minLength: 6)
            // **Ve sloupci žádné počty** (#197). Zkoušely se vedle jména i pod ním a obojí bylo
            // horší než nic: vedle ukously jméno, pod ním rozhodily řádkování. GitHub je ve
            // stromu nemá taky — patří k hlavičce souboru v diffu, kde je na ně místo.
            // V popoveru (420 bodů) zůstávají, tam se vejdou.
            if !isCompact {
                DiffCounts.text(additions: node.additions, deletions: node.deletions)
                    .font(.caption)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, Double(depth) * indent)
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

    /// Barva ikony podle druhu změny. `nil` = beze změny odstínu (složka, upravený soubor).
    private func tint(of file: FileDiff) -> Color? {
        switch file.change {
        case .added: .green
        case .deleted: .red
        case .renamed: .blue
        case .modified: nil
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
