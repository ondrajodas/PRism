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
    /// Dá se k tomuhle výběru napsat návrh změny (#528), a co by nahradil? `nil` = na to se
    /// nikdo neptal (náhledy, testy skládání řádků) a tlačítko se nekreslí.
    var suggestion: SuggestionOffer?
    var update: (String) -> Void = { _ in }
    var remove: () -> Void = {}

    /// Kudy se do pole dostane blok návrhu (#528). Drží ho bublina, protože **ona to tlačítko
    /// kreslí** — pole je uvnitř a text v něm je živější než to, co ví store.
    @State private var insertion = TextInsertionBox()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let refusal = suggestion?.refusal { refusalNote(refusal) }
            DraftTextEditor(
                text: comment.body,
                placeholder: "Co k tomu řádku chceš napsat…",
                // Pole s návrhem je vyšší (#528): `TextEditor` s obsahem neroste, takže by se
                // blok v poli na dva řádky dal přepsat jedině naslepo.
                minHeight: Policy.draftEditorHeight(hasSuggestion: !suggestionsInBody.isEmpty),
                // Prázdný komentář znamená „zahoď mě“, takže se prázdno musí doručit i tehdy,
                // když se nic nenapsalo — jinak zůstane ležet v draftu a blokuje odeslání.
                commitsEmpty: true,
                insertion: insertion,
                commit: update
            )
            preview
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
            suggestionButton
            Button("Vyjmout z review", systemImage: "trash", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Vyjmout komentář z rozdělaného review")
        }
    }

    // MARK: - Návrh změny (#528)

    /// `Návrh změny` — vloží do komentáře blok předvyplněný **původními řádky**.
    ///
    /// Kreslí se jen tam, kde se na návrh někdo ptal (`suggestion != nil`); u výběru, ke kterému
    /// návrh napsat nejde, zůstává **zakázané s důvodem**, ne schované — a důvod je vidět i bez
    /// najetí myší, protože ho vypisuje řádek pod hlavičkou. Chybějící tlačítko by u sousedního
    /// řádku, kde tlačítko je, vypadalo jako závada.
    @ViewBuilder private var suggestionButton: some View {
        if let suggestion {
            Button("Návrh změny") {
                guard let block = suggestion.suggestion else { return }
                insertion.insert(Policy.suggestionFence(replacing: block.replacement))
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(suggestion.suggestion == nil)
            .help(suggestion.refusal
                ?? "Vloží blok ```suggestion předvyplněný původními řádky. Odejde s review jako text komentáře, ne hned.")
        }
    }

    private func refusalNote(_ reason: String) -> some View {
        Text(verbatim: reason)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Návrhy, které v komentáři doopravdy stojí — spárované s tím, co nahrazují.
    ///
    /// Čte se z **těla komentáře**, ne z toho, co tlačítko vložilo: blok se dá přepsat, smazat
    /// i napsat ručně, takže druhý zdroj pravdy by ukazoval návrh, který v komentáři není.
    /// Původní řádky přidává nabídka, protože v ` ```suggestion ` samotném nejsou.
    ///
    /// Ptá se nad **rozloženými** bloky, ne nad textem: bublina je buňka líného seznamu, takže by
    /// se markdown parsoval při každém překreslení (#224).
    private var suggestionsInBody: [CodeSuggestion] {
        Policy.suggestions(
            in: MarkdownRenderCache.shared.blocks(of: comment.body),
            replacing: suggestion?.suggestion?.original ?? []
        )
    }

    /// Náhled toho, co z návrhu uvidí autor PR — **co je vidět, to odejde** (#68).
    @ViewBuilder private var preview: some View {
        let suggestions = suggestionsInBody
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(suggestions.indices, id: \.self) { index in
                    SuggestionBlockView(
                        suggestion: suggestions[index],
                        note: "upravuješ ř. \(Policy.lines(of: comment))"
                    )
                }
                Text("Návrh odejde s review jako text komentáře, ne hned.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if suggestions.contains(where: \.changesNothing) {
                    Text("Blok zatím jen opisuje původní řádky — dokud se nepřepíšou, návrh nic nemění.")
                        .font(.caption2)
                        .foregroundStyle(Palette.stale)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
