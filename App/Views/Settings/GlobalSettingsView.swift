import SwiftUI

/// Záložka „Obecné“ — hodnoty, které platí, dokud je repo nepřebije.
struct GlobalSettingsView: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                SourceListEditor(sources: $settings.draft.global.sources)
            } header: {
                Text("Zdroje")
            } footer: {
                Text("Search dotazy pro `gh search prs`. Výsledky se slévají a deduplikují.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            // `Běh` je hrst čísel, která se nastaví jednou. Denní limit patří mezi ně,
            // i když se týká automatu — je to strop na útratu, ne volba chování.
            Section("Běh") {
                SettingsNumberField(
                    label: "Interval pollingu (s)",
                    value: $settings.draft.global.pollIntervalSeconds,
                    range: 10...3600,
                    step: 10
                )
                SettingsNumberField(
                    label: "Rozpočet cache (MB)",
                    value: $settings.draft.global.cacheBudgetMegabytes,
                    range: 512...1_048_576,
                    step: 1024
                )
                SettingsNumberField(
                    label: "Souběžné session",
                    value: $settings.draft.global.maxConcurrentReviews,
                    range: 1...10
                )
                // Nula je platná hodnota: znamená, že automat nespustí nic.
                SettingsNumberField(
                    label: "Automatických review za den",
                    value: $settings.draft.global.autoRunsPerDay,
                    range: 0...500
                )
                TextField("Model", text: modelName, prompt: Text("výchozí podle claude"))
            }
        }
        .formStyle(.grouped)
    }

    /// Prázdné pole znamená „nech rozhodnout `claude`“, tedy `nil` v konfiguraci.
    /// `ClaudeCommand` prázdný řetězec taky přeskočí, ale mít v souboru dva zápisy téhož
    /// je past pro toho, kdo ho čte — `nil` je jediný.
    private var modelName: Binding<String> {
        Binding(
            get: { settings.draft.global.model ?? "" },
            set: { settings.draft.global.model = $0.isEmpty ? nil : $0 }
        )
    }
}
