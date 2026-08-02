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
    /// Nálezy k zavěšení pod řádky. Seskupené podle místa už volajícím.
    var findings: [FindingGroup] = []
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    /// Místo, na které se právě skočilo z tabulky nálezů.
    var highlighted: FindingHighlight?

    /// Předvolba pohledu napříč pull requesty, takže patří do `UserDefaults`, ne do store.
    @AppStorage("showFindingBubbles") private var showBubbles = true
    @State private var isPickingFile = false

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                summary(jumpingWith: proxy)
                Divider()
                files
            }
            // Doprostřed, ne na vrch: bublina visí **pod** svým řádkem, takže u horní hrany
            // by bylo vidět jen ji a kód nad ní ne. Ukotvená hlavička souboru navíc vršek
            // překrývá, takže by řádek scrollnutý „na vrch“ skončil pod ní.
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
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
        let rows = DiffRow.rows(
            of: file,
            revealed: state.revealed,
            content: state.content,
            findings: showBubbles ? findings : []
        )
        return ForEach(rows) { row in
            DiffRowView(
                row: row,
                language: language,
                isLoadingContent: state.isLoading,
                contentFailure: state.failure,
                reveal: { expansion.reveal(file, $0) },
                highlighted: highlighted,
                blockingCategories: blockingCategories
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
            if !findings.isEmpty {
                Toggle("Bubliny", isOn: $showBubbles)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .help("Zobrazit nálezy u řádků, kterých se týkají")
            }
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

    /// Popover se stromem, ne rozbalovací menu: u PR přes třicet souborů je plochý seznam
    /// cest nepoužitelný a vnořená podmenu se špatně trefují.
    private func jumpMenu(_ proxy: ScrollViewProxy) -> some View {
        Button {
            isPickingFile = true
        } label: {
            Label("Přejít na soubor", systemImage: "list.bullet.indent")
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isPickingFile, arrowEdge: .bottom) {
            FileTreeView(files: diff.files) { file in
                isPickingFile = false
                withAnimation { proxy.scrollTo(file.id, anchor: .top) }
            }
        }
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
