import SwiftUI

/// Stránka `Diff` (#177) — nastavení **člověka, ne repa**, proto jen globálně.
struct DiffSettingsView: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            // Vlastní sekce, ne řádek v `Režimu review`: pohled na diff s review nesouvisí,
            // je to nastavení **člověka, ne repa** — a proto ho `RepositoryConfig` nemá.
            Section {
                Picker("Pohled na diff", selection: $settings.draft.global.diffLayout) {
                    ForEach(DiffLayout.allCases, id: \.self) { layout in
                        Text(verbatim: layout.displayName).tag(layout)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Diff")
            } footer: {
                // Musí být jasné, že přepínač v liště tuhle hodnotu **nepřepisuje** — jinak
                // by nastavení vypadalo jako něco, co se samo mění.
                Text("S tímhle pohledem se diff otevírá. `Vedle sebe` staví starý obsah proti novému spárovaný po řádcích, `Pod sebou` je klasický unified diff. V liště nad diffem se dá pohled přepnout kdykoli; taková odchylka platí do zavření aplikace a sem se nezapisuje.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

}
