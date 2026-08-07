import SwiftUI

/// Celý hunk jako **jeden** text, ve kterém se dá vybírat i **přes bubliny** (#157).
///
/// V diffu se od #157 přes řádky vybírat dá, ale jen v rámci bloku — ten končí u bubliny, u hlavičky
/// hunku a u rozbalovacího řádku, protože přes ně jeden text vést nejde (visí na nich komentáře,
/// pilulka, tažení rozsahu i pozadí podle druhu řádku). Kdo chce výřez přes ně, dostane ho tady.
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

    /// Kód k vybírání. Kreslí ho `SelectableCodeView` (`NSTextView`) — SwiftUI `Text` dává selekci
    /// po jednotlivých textech, viz tam.
    private var code: some View {
        SelectableCodeView(code: content.code, path: content.path, colorScheme: colorScheme)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
