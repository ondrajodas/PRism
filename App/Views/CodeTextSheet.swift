import SwiftUI

/// Kus kódu jako **jeden** text, ve kterém se dá vybírat přes řádky (#157).
///
/// Existuje proto, že v diffu to nejde a jít nemůže: každý řádek je vlastní `Text` a selekce se
/// mezi dvěma `Text`y neslévá. Složit hunk do jednoho `Text`u **uvnitř** diffu nejde kvůli tomu,
/// co na řádcích visí (bubliny mezi řádky, tlačítko na komentář, tažení rozsahu, pozadí podle
/// druhu řádku) — a hlavně kvůli měřené pasti s hunkem jako jednou buňkou líného seznamu.
///
/// Tady je to bezpečné, protože je to **mimo diff**: read-only `NSTextView` nad jedním textem.
struct CodeText: Identifiable, Hashable {
    /// Odkud kód je — cesta a hlavička hunku. Identita sheetu je z ní, takže dvě různá místa
    /// otevřou různý obsah.
    let id: String
    let path: String
    /// Hlavička hunku (`@@ -1905,7 +1905,13 @@`), nebo prázdné.
    let heading: String
    /// Kód **bez** znaků změny a bez čísel řádků — do vybraného textu nemá co připlést diff.
    let code: String
}

/// Sheet s kódem k vybrání a zkopírování.
struct CodeTextSheet: View {
    let content: CodeText
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            code
        }
        .frame(minWidth: 560, idealWidth: 820, minHeight: 320, idealHeight: 520)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: content.path)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.head)
                if !content.heading.isEmpty {
                    Text(verbatim: content.heading)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // Celý blok jedním kliknutím — vybírat rukou má smysl u výřezu, ne u všeho.
            Button(didCopy ? "Zkopírováno" : "Kopírovat vše", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                Clipboard.copy(content.code)
                didCopy = true
            }
            .disabled(didCopy)
            Button("Zavřít") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    /// Kód k vybírání. Kreslí ho `SelectableCodeView` (`NSTextView`), protože SwiftUI `Text`
    /// selekci přes víc řádků nedá — viz tam.
    private var code: some View {
        SelectableCodeView(code: content.code, path: content.path, colorScheme: colorScheme)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
