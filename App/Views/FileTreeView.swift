import SwiftUI

/// Strom souborů diffu pro skok na soubor — levý sloupec u diffu (#197).
///
/// Strom, ne plochý seznam cest: u PR přes víc adresářů zaberou společné prefixy většinu
/// šířky a hledá se v tom očima špatně.
///
/// Vykresluje se ručně, ne přes `OutlineGroup`: ten odsazuje jen uvnitř `List`u, a bez
/// odsazení není z řádků poznat, co je pod čím.
///
/// **Sazba je úsporná a jiná není** (#219). Ve sloupci 210 bodů širokém se nevejde nic než jméno
/// a značka: počty `+/−` zaberou přes padesát bodů a slovní odznak (`nový`) další čtyřicet, takže
/// na jméno zbyde `…S.md`. Do #219 tu byla i plná varianta pro popover `Přejít na soubor`; ten se
/// z lišty odstranil, takže po ní zbyl parametr s jediným volajícím a jedinou hodnotou.
struct FileTreeView: View {
    let files: [FileDiff]
    /// Které soubory nesou nález (#197). Prázdné = nekreslí se žádná značka.
    var markers: [String: FileMarker] = [:]
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
                        jump: jump
                    )
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
        // **Rozměr se měří, nevyjednává** (#361): strom stojí v `VStack`u sloupce, takže by mu
        // ten `VStack` posílal svoje průzkumné dotazy na pružnost skrz na `LazyVStack`.
        .fillingSlot()
    }
}

/// Jedna větev stromu — řádek a pod ním potomci, když je rozbalená.
private struct FileTreeBranch: View {
    let node: FileTreeNode
    let depth: Int
    @Binding var collapsed: Set<String>
    let markers: [String: FileMarker]
    let jump: (FileDiff) -> Void

    /// O kolik se odsazuje každá úroveň. Šířka šipky a ikony, ať řádky drží sloupec — a málo,
    /// protože v úzkém sloupci každá úroveň ukousne z jména.
    private let indent = 11.0

    var body: some View {
        row
        if let children = node.children, !collapsed.contains(node.id) {
            ForEach(children) { child in
                FileTreeBranch(
                    node: child,
                    depth: depth + 1,
                    collapsed: $collapsed,
                    markers: markers,
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
                .font(.caption)
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
                    .fill(marker == .blocking ? Palette.crit : Palette.find)
                    .frame(width: 6, height: 6)
                    .help(marker == .blocking ? "Je tu blokující nález" : "Jsou tu nálezy")
            }
            // **Ve stromu žádné počty ani slovní odznak** (#197). Zkoušely se vedle jména
            // i pod ním a obojí bylo horší než nic: vedle ukously jméno, pod ním rozhodily
            // řádkování. GitHub je ve stromu nemá taky — patří k hlavičce souboru v diffu,
            // kde je na ně místo.
            Spacer(minLength: 6)
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
        case .added: Palette.ok
        case .deleted: Palette.crit
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
}
