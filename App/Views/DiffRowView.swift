import SwiftUI

/// Vykreslí jeden řádek diffu — hlavičku hunku, řádek souboru, rozbalovací řádek nebo
/// poznámku.
struct DiffRowView: View {
    let row: DiffRow
    /// Jazyk souboru kvůli obarvení kódu. `nil` u souboru, kterému nerozumíme.
    var language: Language?
    /// Načítá se právě obsah souboru, do kterého řádek patří?
    var isLoadingContent = false
    /// Proč se obsah souboru nepodařilo načíst.
    var contentFailure: String?
    var reveal: (ClosedRange<Int>) -> Void = { _ in }
    /// Místo, na které se právě skočilo z tabulky.
    var highlighted: FindingHighlight?
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories

    var body: some View {
        switch row {
        case .hunk(_, let hunk):
            hunkHeader(hunk)
        case .line(_, let line):
            DiffLineView(line: line, language: language)
        case .expander(_, let expander):
            DiffExpanderView(
                expander: expander,
                isLoading: isLoadingContent,
                failure: contentFailure,
                reveal: reveal
            )
        case .finding(_, let group, let anchored):
            FindingBubbleView(
                group: group,
                blockingCategories: blockingCategories,
                isAnchored: anchored,
                reveal: reveal,
                isHighlighted: highlighted?.matches(group) ?? false
            )
        case .note(_, let text):
            note(text)
        }
    }

    private func hunkHeader(_ hunk: DiffHunk) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: hunk.header)
            if !hunk.heading.isEmpty {
                Text(verbatim: hunk.heading)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
