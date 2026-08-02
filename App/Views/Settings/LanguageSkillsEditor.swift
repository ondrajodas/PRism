import SwiftUI

/// Mapa „rozpoznaný jazyk → výchozí sada skillů“.
///
/// Ukazují se **jen jazyky, které v mapě jsou**. Deset prázdných seznamů pod sebou by
/// z formuláře udělalo tabulku, ve které není vidět to jediné, co je nastavené.
struct LanguageSkillsEditor: View {
    @Binding var skillsByLanguage: [ProjectLanguage: [String]]
    /// Sada, od které nový záznam začíná. Předává se zvenčí, protože editor sám globální
    /// konfiguraci nevidí.
    let globalFallback: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(configured, id: \.self) { language in
                section(for: language)
            }
            addButton
        }
    }

    /// Abecedně podle jména, ne pořadím slovníku — ten pořadí nemá a řádky by mezi
    /// překresleními poskakovaly. Jména jsou unikátní, takže je pořadí úplné.
    private var configured: [ProjectLanguage] {
        byName.filter { skillsByLanguage[$0] != nil }
    }

    private var unconfigured: [ProjectLanguage] {
        byName.filter { skillsByLanguage[$0] == nil }
    }

    private var byName: [ProjectLanguage] {
        ProjectLanguage.allCases.sorted { $0.displayName < $1.displayName }
    }

    private func section(for language: ProjectLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: language.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    skillsByLanguage[language] = nil
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Zrušit mapování — repa v tomhle jazyce pak berou globální sadu")
            }
            StringListEditor(
                items: skills(for: language),
                placeholder: "code-review",
                addLabel: "Přidat skill"
            )
        }
    }

    @ViewBuilder private var addButton: some View {
        if unconfigured.isEmpty {
            EmptyView()
        } else {
            Menu("Přidat programovací jazyk") {
                ForEach(unconfigured, id: \.self) { language in
                    // Nový záznam začíná od globální sady: nejčastější důvod pro mapování
                    // je jeden skill přidat nebo ubrat, ne psát seznam od nuly.
                    Button(language.displayName) { skillsByLanguage[language] = globalFallback }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .controlSize(.small)
        }
    }

    /// Stejná pojistka jako u ostatních editorů: záznam může zmizet dřív, než se seznam
    /// překreslí, a zápis do smazaného klíče by ho vzkřísil.
    private func skills(for language: ProjectLanguage) -> Binding<[String]> {
        Binding(
            get: { skillsByLanguage[language] ?? [] },
            set: { newValue in
                guard skillsByLanguage[language] != nil else { return }
                skillsByLanguage[language] = newValue
            }
        )
    }
}
