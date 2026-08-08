import SwiftUI

/// Stránka `Review a skilly` (#177).
///
/// Tři věci, které spolu souvisí a do #177 byly ve třech různých sekcích jedné dlouhé záložky:
/// **kdy** se review pouští, **co** se pouští a **co z toho je vážné**.
struct ReviewSettingsView: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Výchozí režim", selection: $settings.draft.global.mode) {
                    Text("Manuální").tag(ReviewMode.manual)
                    Text("Automatický").tag(ReviewMode.automatic)
                }
                .pickerStyle(.radioGroup)

                // Jazyk patří sem, ne mezi hodnoty běhu: je to spolu s režimem to, co se
                // u jednotlivých rep mění nejčastěji, a v obou případech je globální
                // hodnota jen výchozí.
                Picker("Jazyk nálezů", selection: $settings.draft.global.findingsLanguage) {
                    ForEach(FindingsLanguage.allCases, id: \.self) { language in
                        Text(verbatim: language.displayName).tag(language)
                    }
                }
            } header: {
                Text("Režim review")
            } footer: {
                Text("Platí pro repa, která si neřeknou o jiný. Manuální čeká na tlačítko, automatický spustí review, jakmile se PR objeví v seznamu. Jazyk se týká textu nálezů; `category` zůstává vždycky anglicky, protože je to slug, na který se váže blokující sada.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                StringListEditor(
                    items: $settings.draft.global.skills,
                    itemLabel: "Skill",
                    placeholder: "code-review:code-review",
                    addLabel: "Přidat skill"
                )
            } header: {
                Text("Skilly")
            } footer: {
                Text("Každý skill je jedna headless session. Repo si sadu může přebít.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LanguageSkillsEditor(
                    skillsByLanguage: $settings.draft.global.skillsByLanguage,
                    globalFallback: settings.draft.global.skills
                )
            } header: {
                // „Jazyk“ samotné se plete s jazykem, ve kterém reviewer píše nálezy
                // (#52) — proto všude „programovací jazyk“, i když je to delší.
                Text("Skilly podle programovacího jazyka")
            } footer: {
                Text("Při review se z obsahu repa pozná, čím je psané, a použije se sada odsud. Rozhoduje to, **které skilly se spustí** — ne jazyk, ve kterém reviewer píše nálezy. Jazyk, který tu není, bere sadu výš.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                StringListEditor(
                    items: $settings.draft.global.blockingCategories,
                    itemLabel: "Kategorie",
                    placeholder: "correctness",
                    addLabel: "Přidat kategorii"
                )
            } header: {
                Text("Blokující kategorie")
            } footer: {
                // Jeden literál, ne konkatenace: složený výraz spadne na `Text(String)`,
                // které markdown neumí — a `CONFIRMED` by se vykreslilo se zpětnými
                // apostrofy místo monospace.
                Text("Nález blokuje, když je `CONFIRMED` a jeho kategorie je v téhle sadě. Na velikosti písmen nezáleží.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

}
