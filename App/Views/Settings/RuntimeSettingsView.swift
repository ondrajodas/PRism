import SwiftUI

/// Stránka `Běh` (#177) — hrst čísel, která se nastaví jednou.
struct RuntimeSettingsView: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
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
