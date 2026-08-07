import SwiftUI

/// Můj rozdělaný komentář u řádku — to, co se odešle jako řádkový komentář review.
///
/// Vypadá jinak než nález i než cizí vlákno, a je to třetí druh bubliny schválně: nález je
/// tvrzení aplikace, vlákno je to, co napsal někdo jiný, a tohle je jediná bublina, do které
/// **píšu**. Kdyby splynula s ostatními, nebylo by z pohledu na diff poznat, co z něj odejde
/// na GitHub.
struct DraftCommentBubbleView: View {
    let comment: ReviewDraftComment
    /// Odsazení do sloupce s obsahem. Ve split pohledu je v buňce jedno číslo řádku místo
    /// dvou, takže je kratší — stejný parametr jako u `ThreadBubbleView`.
    var indent: Double = DiffLineView.contentInset(for: .unified)
    var update: (String) -> Void = { _ in }
    var remove: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            DraftTextEditor(
                text: comment.body,
                placeholder: "Co k tomu řádku chceš napsat…",
                minHeight: 54,
                // Prázdný komentář znamená „zahoď mě“, takže se prázdno musí doručit i tehdy,
                // když se nic nenapsalo — jinak zůstane ležet v draftu a blokuje odeslání.
                commitsEmpty: true,
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
        .padding(.leading, indent)   // stejné odsazení jako nálezy a vlákna — do sloupce s obsahem
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
            // U rozsahu se čísla ukazují vždycky (#110): bublina visí u **posledního** řádku,
            // takže bez nich není poznat, kde rozsah začíná. U jednoho řádku jen tehdy, když je
            // ze staré verze souboru — jinak by to byl šum u každého komentáře.
            if comment.anchor.isRange {
                Text(verbatim: "řádky \(Policy.lines(of: comment))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if comment.side == .left {
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

    /// Prázdný komentář GitHub odmítne a s ním celé review, takže se zahodí. Bez téhle věty
    /// by po odscrollování nebo přepnutí PR beze slova zmizel.
    ///
    /// Text říká **zahodí se**, ne „neuloží se“: v draftu prázdný komentář chvíli je (vzniká
    /// kliknutím, text se dopisuje potom) a zmizí, až se od něj odejde. Slibovat, že se nikam
    /// neuložil, by bylo tvrzení víc, než data unesou.
    private var emptyNote: some View {
        Text("Prázdný komentář se neodešle — zahodí se, jakmile od něj odejdeš.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
