import SwiftUI

/// Stránka `Zdroje PR` (#177) — odkud se seznam bere.
struct SourcesSettingsView: View {
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
        }
        .formStyle(.grouped)
    }

}
