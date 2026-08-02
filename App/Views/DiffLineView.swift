import SwiftUI

/// Jeden řádek diffu: dvě čísla, znak změny a obsah.
struct DiffLineView: View {
    let line: DiffLine
    /// Jazyk souboru kvůli obarvení. `nil` = jednobarevný řádek.
    var language: Language?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            number(line.oldNumber)
            number(line.newNumber)
            Text(verbatim: sign)
                .foregroundStyle(signColor)
                .frame(width: 14, alignment: .leading)
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Dlouhý řádek se zalomí; bez tohohle by se v líném seznamu ořízl.
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(line.kind == .meta ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .background(background)
    }

    /// Obsah řádku obarvený podle jazyka.
    ///
    /// Prázdný řádek se nahrazuje mezerou: prázdný `Text` má nulovou výšku, takže by
    /// z diffu zmizel a přestala by u něj sedět čísla vedle.
    ///
    /// Obarvení se počítá **při vykreslení řádku**, ne dopředu pro celý soubor. Seznam je
    /// líný, takže se to spočítá jen pro to, na co je vidět; nad jedním řádkem je to práce
    /// v řádu mikrosekund.
    private var content: AttributedString {
        guard !line.text.isEmpty else { return AttributedString(" ") }
        guard let language, line.kind != .meta else { return AttributedString(line.text) }

        let palette = SyntaxPalette.forScheme(colorScheme)
        var result = AttributedString()
        for run in SyntaxHighlighter.runs(of: line.text, in: language) {
            var piece = AttributedString(run.text)
            // `nil` u obyčejného textu schválně: řádek si tak nechá barvu, kterou mu dal
            // okolní styl (třeba ztlumenou u poznámky).
            piece.foregroundColor = palette.color(for: run.kind)
            result += piece
        }
        return result
    }

    /// Čísla řádků se píšou `verbatim` — `Text("\(number)")` jde přes locale a z řádku
    /// 21663 udělá „21 663“. Číslo řádku není množství.
    private func number(_ value: Int?) -> some View {
        Text(verbatim: value.map(String.init) ?? "")
            .font(.system(.caption, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .frame(width: 44, alignment: .trailing)
            .padding(.trailing, 8)
    }

    private var sign: String {
        switch line.kind {
        case .added: "+"
        case .removed: "-"
        case .context: " "
        case .meta: "\\"
        }
    }

    private var signColor: Color {
        switch line.kind {
        case .added: .green
        case .removed: .red
        case .context, .meta: .secondary
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: .green.opacity(0.12)
        case .removed: .red.opacity(0.12)
        case .context, .meta: .clear
        }
    }
}
