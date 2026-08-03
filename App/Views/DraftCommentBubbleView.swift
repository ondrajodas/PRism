import SwiftUI

/// Můj rozdělaný komentář u řádku — to, co se odešle jako řádkový komentář review.
///
/// Vypadá jinak než nález i než cizí vlákno, a je to třetí druh bubliny schválně: nález je
/// tvrzení aplikace, vlákno je to, co napsal někdo jiný, a tohle je jediná bublina, do které
/// **píšu**. Kdyby splynula s ostatními, nebylo by z pohledu na diff poznat, co z něj odejde
/// na GitHub.
struct DraftCommentBubbleView: View {
    let comment: ReviewDraftComment
    var update: (String) -> Void = { _ in }
    var remove: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            DraftTextEditor(
                text: comment.body,
                placeholder: "Co k tomu řádku chceš napsat…",
                minHeight: 54,
                commit: update
            )
            if comment.body.isEmpty { emptyNote }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.07), in: .rect(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Rectangle().fill(.tint).frame(width: 3)
        }
        .clipShape(.rect(cornerRadius: 8))
        .padding(.leading, 104)   // stejné odsazení jako nálezy a vlákna — do sloupce s obsahem
        .padding(.trailing, 16)
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.pencil")
                .font(.caption)
                .foregroundStyle(.tint)
            Text("Můj komentář k review")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tint)
            if let reviewer = comment.origin.reviewer {
                Text(verbatim: "z nálezu od \(reviewer)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
                    .foregroundStyle(.secondary)
            }
            // Strana je vidět jen u odebraného řádku, kde je to důležité: komentář má číslo
            // ze **staré** verze souboru, takže bez toho vypadá, že je na jiném řádku.
            if comment.side == .left {
                Text(verbatim: "starý řádek \(comment.line)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Button("Vyjmout z review", systemImage: "trash", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Vyjmout komentář z rozdělaného review")
        }
    }

    /// Prázdný komentář GitHub odmítne a s ním celé review, takže se neuloží. Bez téhle věty
    /// by po přepnutí PR beze slova zmizel.
    private var emptyNote: some View {
        Text("Prázdný komentář se do review neuloží.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
