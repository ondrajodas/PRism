import AppKit
import SwiftUI

/// Okno nastavení. Dvě záložky — globální hodnoty a to, co si přebírá jednotlivé repo.
///
/// Zapisuje do téhož `config.json`, který jde editovat ručně, takže platí dvě věci:
/// **rozbitý soubor se nepřepíše** (editor se zamkne a nabídne ho otevřít) a změna zvenčí
/// formulář srovná, viz `SettingsModel`.
struct SettingsView: View {
    let store: AppStore
    @State private var settings: SettingsModel

    init(store: AppStore) {
        self.store = store
        _settings = State(
            initialValue: SettingsModel(configuration: store.configuration) { configuration in
                try await store.updateConfiguration(configuration)
            }
        )
    }

    var body: some View {
        content
            .frame(width: 880, height: 560)
            .task { settings.sync(with: store.configuration) }
            .onChange(of: store.configuration) { _, configuration in
                settings.sync(with: configuration)
            }
            .onAppear { store.isSettingsOpen = true }
            // Zavřít okno jde dřív, než doběhne zpoždění před zápisem. Rozepsaná změna se
            // nesmí ztratit jen proto, že jsem byl rychlejší než ono.
            .onDisappear {
                store.isSettingsOpen = false
                Task { await settings.flush() }
            }
    }

    @ViewBuilder private var content: some View {
        if let failure = store.configurationFailure {
            brokenFile(failure)
        } else {
            editor
        }
    }

    /// Soubor, který se nepodařilo přečíst, editor **nepřepíše**. Uložit přes něj výchozí
    /// hodnoty by znamenalo zahodit něco, co uživatel psal — kvůli chybějící čárce.
    private func brokenFile(_ failure: String) -> some View {
        ContentUnavailableView {
            Label("Konfiguraci se nepodařilo přečíst", systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure)
        } actions: {
            Button("Otevřít soubor", systemImage: "square.and.pencil") { openConfigFile() }
            Button("Zkusit načíst znovu") {
                Task { await store.reloadConfiguration() }
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            TabView {
                GlobalSettingsView(settings: settings)
                    .tabItem { Label("Obecné", systemImage: "gearshape") }
                RepositorySettingsView(settings: settings, repositories: store.knownRepositories)
                    .tabItem { Label("Repozitáře", systemImage: "folder") }
            }
            Divider()
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(verbatim: CacheLayout.applicationSupport.configFile.path(percentEncoded: false))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            saveStatus
            Button("Otevřít soubor") { openConfigFile() }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// Neuložená změna, o které se mlčí, vypadá jako uložená — a po restartu je pryč.
    @ViewBuilder private var saveStatus: some View {
        if let failure = settings.saveFailure {
            Label(failure, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .help(failure)
        } else if let saved = settings.lastSaved {
            Label(
                "Uloženo v \(saved.formatted(date: .omitted, time: .standard))",
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func openConfigFile() {
        NSWorkspace.shared.open(CacheLayout.applicationSupport.configFile)
    }
}
