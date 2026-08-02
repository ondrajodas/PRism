import SwiftUI

/// Jeden řádek diffu: dvě čísla, znak změny a obsah.
struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            number(line.oldNumber)
            number(line.newNumber)
            Text(verbatim: sign)
                .foregroundStyle(signColor)
                .frame(width: 14, alignment: .leading)
            // Prázdný `Text` má nulovou výšku, takže by prázdný řádek v souboru z diffu
            // zmizel — a s ním by přestala sedět i čísla vedle něj.
            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Dlouhý řádek se zalomí; bez tohohle by se v líném seznamu ořízl.
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(line.kind == .meta ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .background(background)
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
