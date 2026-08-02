import SwiftUI

/// Diff v plné šířce: soubory pod sebou, hlavička souboru se při scrollu drží nahoře.
///
/// Skládá se líně (`LazyVStack`) — diff o tisících řádků je běžný a vykreslit ho celý
/// naráz by okno na chvíli položilo.
struct DiffView: View {
    let diff: Diff
    /// Kam odscrollovat. Nastaví ho panel nálezů; po skoku se vrací na `nil`, aby šlo
    /// na totéž místo skočit i podruhé.
    @Binding var scrollTarget: String?
    /// Rozbalování kontextu. Bere se ze store, ne z vlastního stavu — jinak by rozbalení
    /// přeteklo z jednoho pull requestu na druhý.
    let expansion: DiffExpansionActions

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                summary(jumpingWith: proxy)
                Divider()
                files
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
        }
    }

    /// Každý **řádek** je vlastní buňka líného seznamu, ne každý hunk. Hunk jako celek
    /// se po změně šířky okna překresloval jen zčásti a v diffu zůstávala prázdná místa.
    private var files: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(diff.files) { file in
                    Section {
                        rows(of: file)
                    } header: {
                        fileHeader(file)
                    }
                    .id(file.id)
                }
            }
        }
    }

    private func rows(of file: FileDiff) -> some View {
        let state = expansion.state(file)
        let language = Language(path: file.displayPath)
        return ForEach(DiffRow.rows(of: file, revealed: state.revealed, content: state.content)) { row in
            DiffRowView(
                row: row,
                language: language,
                isLoadingContent: state.isLoading,
                contentFailure: state.failure,
                reveal: { expansion.reveal(file, $0) }
            )
        }
    }

    private func summary(jumpingWith proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(files(diff.files.count)) · +\(diff.additions) −\(diff.deletions)")
                .font(.callout)
                .foregroundStyle(.secondary)
            if diff.unrecognizedLines > 0 {
                unrecognizedWarning
            }
            Spacer()
            if let collapse = expansion.collapse {
                Button("Zobrazit jen diff", systemImage: "arrow.down.right.and.arrow.up.left") {
                    collapse()
                }
                .font(.callout)
                .buttonStyle(.borderless)
            }
            jumpMenu(proxy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Nerozpoznaný řádek znamená, že se člověk dívá na neúplný podklad. Bez téhle věty
    /// by neúplný diff vypadal jako úplný.
    private var unrecognizedWarning: some View {
        let count = Plural.czech(diff.unrecognizedLines, one: "řádek", few: "řádky", many: "řádků")
        return Label {
            Text(verbatim: "\(count) diffu se nepodařilo přečíst")
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private func jumpMenu(_ proxy: ScrollViewProxy) -> some View {
        Menu {
            ForEach(diff.files) { file in
                Button {
                    withAnimation { proxy.scrollTo(file.id, anchor: .top) }
                } label: {
                    Text(verbatim: "\(file.displayPath)  +\(file.additions) −\(file.deletions)")
                }
            }
        } label: {
            Label("Přejít na soubor", systemImage: "list.bullet.indent")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func fileHeader(_ file: FileDiff) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: file.displayPath)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .truncationMode(.head)
            if let badge = badge(for: file) {
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
            }
            if file.change == .renamed, let oldPath = file.oldPath {
                Text(verbatim: "← \(oldPath)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Text(verbatim: "+\(file.additions) −\(file.deletions)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Ukotvená hlavička jede přes obsah, takže pod ní musí být neprůhledné pozadí.
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func badge(for file: FileDiff) -> String? {
        if file.isBinary { return "binární" }
        switch file.change {
        case .added: return "nový"
        case .deleted: return "smazaný"
        case .renamed: return "přejmenovaný"
        case .modified: return nil
        }
    }

    private func files(_ count: Int) -> String {
        Plural.czech(count, one: "soubor", few: "soubory", many: "souborů")
    }
}
