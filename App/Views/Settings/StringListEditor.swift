import SwiftUI

/// Editor seznamu řetězců — skilly, blokující kategorie.
///
/// Prázdný seznam je **vlastní odpověď**, ne chyba: u repa znamená „tady nereviewuj nic“.
/// Editor ho proto nedoplňuje ani nezakazuje, jen ho volající umí popsat.
struct StringListEditor: View {
    @Binding var items: [String]
    /// Čím je jedna položka — `Skill`, `Kategorie`. Vizuálně schovaný, ale **musí být
    /// vyplněný**: `.labelsHidden()` skryje jen zobrazení, pro VoiceOver zůstává labelem,
    /// a prázdný by mu nenechal co číst.
    let itemLabel: LocalizedStringKey
    let placeholder: String
    let addLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                row(at: index)
            }
            Button(addLabel, systemImage: "plus.circle") { items.append("") }
                .controlSize(.small)
        }
    }

    private func row(at index: Int) -> some View {
        HStack(spacing: 6) {
            // Nápověda patří do `prompt:`. První argument se ve `Form`u vykreslí jako
            // **popisek vlevo od pole**, ne jako nápověda uvnitř — u vyplněného řádku to
            // pak vypadá jako dvě hodnoty vedle sebe.
            TextField(itemLabel, text: binding(at: index), prompt: Text(verbatim: placeholder))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
            Button {
                items.remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Odebrat")
        }
    }

    /// Index je identita řádku, takže mezi odebráním a překreslením existuje okamžik, kdy
    /// `ForEach` sahá na řádek, který v poli už není. `$items[index]` by na něm spadl —
    /// tohle vrátí prázdný řetězec a zápis zahodí.
    private func binding(at index: Int) -> Binding<String> {
        Binding(
            get: { index < items.count ? items[index] : "" },
            set: { newValue in
                guard index < items.count else { return }
                items[index] = newValue
            }
        )
    }
}
