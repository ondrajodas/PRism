import AppKit
import SwiftUI

/// Okno nastavení. Tři záložky — globální hodnoty, notifikace a to, co si přebírá jednotlivé
/// repo.
///
/// Zapisuje do téhož `config.json`, který jde editovat ručně, takže platí dvě věci:
/// **rozbitý soubor se nepřepíše** (editor se zamkne a nabídne ho otevřít) a změna zvenčí
/// formulář srovná, viz `SettingsModel`.
struct SettingsView: View {
    let store: AppStore
    @Environment(\.controlActiveState) private var activeState
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
            // **Ne pevná velikost.** `frame(width:height:)` uvnitř `Settings` scény se pere
            // s tím, jak si okno řídí velikost samo — okno pak umí zmizet při tažení za
            // hlavičku. `ideal` mu velikost navrhne a `min` ji drží v použitelných mezích.
            .frame(minWidth: 720, idealWidth: 880, minHeight: 420, idealHeight: 560)
            // Střed **hlavního okna**, ne obrazovky: na velkém monitoru s oknem u kraje by se
            // nastavení otevřelo o půl metru vedle. Od #164 to má na jednom místě
            // (`WindowCentering`) i okno s novinkami.
            //
            // **Hladina se nechává normální.** Zkoušelo se `.floating`, ať okno zůstane nahoře
            // až do křížku, a **zahodilo se**: kliknutí mimo ho má odklidit, protože najíždět
            // na křížek kvůli jedné změně je otrava. Diagnostikou je přitom ověřené, že se okno
            // nezavírá — `willClose` nepřijde nikdy, jen zaleze za hlavní okno.
            .centeredInMainWindow()
            .task { settings.sync(with: store.configuration) }
            .onChange(of: store.configuration) { _, configuration in
                settings.sync(with: configuration)
            }
            // Okno o sobě ví, jestli má fokus — hlavní okno to o něm poznat nedokáže.
            .onAppear { store.isSettingsFrontmost = activeState == .key }
            .onChange(of: activeState) { _, state in
                store.isSettingsFrontmost = state == .key
            }
            // Zavřít okno jde dřív, než doběhne zpoždění před zápisem. Rozepsaná změna se
            // nesmí ztratit jen proto, že jsem byl rychlejší než ono.
            .onDisappear {
                store.isSettingsFrontmost = false
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

    /// Patička jde přes `safeAreaInset`, **ne do `VStack`u pod `TabView`**.
    ///
    /// Se `VStack`em přestane být `TabView` tím, co si řídí bezpečnou oblast okna, a jeho
    /// formulář si pak vyhradí místo od horní hrany — obsah tedy leze pod lištu se
    /// záložkami a první řádek je uříznutý. Stejná past jako u pruhu nad seznamem PR.
    private var editor: some View {
        TabView {
            GlobalSettingsView(settings: settings)
                .tabItem { Label("Obecné", systemImage: "gearshape") }
            NotificationSettingsView(settings: settings)
                .tabItem { Label("Notifikace", systemImage: "bell") }
            RepositorySettingsView(settings: settings, repositories: store.knownRepositories)
                .tabItem { Label("Repozitáře", systemImage: "folder") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                footer
            }
            .background(.bar)
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

    /// Otevře okno uprostřed **hlavního okna**, pokaždé.
    ///
    /// `Settings` scéna si jinak pozici pamatuje mezi spuštěními — a okno, které se otevře
    /// tam, kam ho někdo kdysi odtáhl, se hledá hůř, než se posouvá. Autosave se proto
    /// vypíná; bez toho by `setFrame` přepsal rámec, který si AppKit vzápětí obnoví ze
    /// zapamatovaného.
    ///
    private func openConfigFile() {
        NSWorkspace.shared.open(CacheLayout.applicationSupport.configFile)
    }
}
