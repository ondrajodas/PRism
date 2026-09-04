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
    @Environment(\.dismiss) private var dismiss
    @State private var settings: SettingsModel
    /// Vybraná stránka. `@State`, ne `@AppStorage`: nastavení se otevírá kvůli konkrétní věci
    /// a vracet se do něj tam, kde jsem skončil minule, není, co člověk čeká — na rozdíl od
    /// výšky panelu, kterou si vytáhne jednou a chce ji mít.
    @State private var section: SettingsSection = .sources
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
            // **Hladinu okna nastavuje `SettingsScene`** (#243) — okno zůstává před hlavním, dokud
            // je otevřené. Do #243 tady stálo, že se hladina nechává normální a `.floating` je
            // zamítnuté, protože kliknutí mimo má okno odklidit; jenže neodklidí, jen ho schová za
            // hlavní okno, ve kterém je vystředěné. Proč se to změnilo, je u `AuxiliaryWindowLevel`.
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
            // nesmí ztratit jen proto, že jsem byl rychlejší než ono. Platí pro křížek i ⌘W,
            // tedy pro cesty, kde se aplikace o zavření dozví až z konce view.
            .onDisappear {
                store.isSettingsFrontmost = false
                Task { await settings.flush() }
            }
            // **Esc okno zavře** (#151) — a doručení je tady **výslovně**, ne odkázané na
            // `onDisappear` výš.
            //
            // Escem se zavírá jedním hmatem **uprostřed psaní**, takže je to ta cesta, u které
            // se rozepsaná hodnota ztratí nejsnáz: mezi posledním úhozem a zavřením nemusí
            // uběhnout ani těch 600 ms, po kterých se ukládá samo. Zapsat to na jedno pořadí
            // (`flush`, pak `dismiss`) stojí dva řádky a nezávisí to na tom, kdy SwiftUI view
            // zahodí — na rozdíl od `onDisappear`, který je tady pořád kvůli ostatním cestám.
            //
            // Zavírá se **i když zápis selhal**: křížek a ⌘W se taky nezastaví, a okno, ze
            // kterého jedna z cest ven nejde, vypadá jako zaseknuté. Chyba zůstává v patičce,
            // až se nastavení otevře znovu.
            .hiddenShortcuts {
                Button("Zavřít nastavení") {
                    Task {
                        await settings.flush()
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)
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
        EmptyStateView(
            nature: .failure,
            symbol: "exclamationmark.triangle",
            title: "Konfiguraci se nepodařilo přečíst",
            message: "Soubor zůstal nedotčený — nic se do něj nezapsalo.",
            // Hláška od dekodéru zůstává, jak přišla: `Neočekávaný znak na řádku 12` je jediné,
            // podle čeho se dá chyba najít.
            detail: failure,
            primary: .init(title: "Otevřít soubor") { openConfigFile() },
            secondary: .init(title: "Načíst znovu") { Task { await store.reloadConfiguration() } }
        )
    }

    /// Boční navigace, ne záložky (#177).
    ///
    /// Tři taby, ze kterých jeden nesl osm sekcí, se hledaly scrollováním. Seznam vlevo je i vzor,
    /// který má systém — systémové nastavení vypadá od Ventury takhle, takže se to nemusí učit.
    ///
    /// **`HStack` s `Listem`, ne `NavigationSplitView`**: uvnitř `Settings` scény si okno řídí
    /// velikost samo a split view se s tím pere (viz `frame` níž). Tenhle vzor je navíc v okně
    /// už jednou ověřený — přesně takhle je postavená stránka `Repozitáře`.
    ///
    /// Patička jde přes `safeAreaInset`, **ne do `VStack`u pod obsah**: jinak přestane být obsah
    /// tím, co si řídí bezpečnou oblast okna, a formulář si vyhradí místo od horní hrany, takže
    /// první řádek zůstane uříznutý. Tatáž past jako u pruhu nad seznamem PR.
    private var editor: some View {
        HStack(spacing: 0) {
            navigation
                .frame(width: 210)
            Divider()
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                footer
            }
            .background(.bar)
        }
    }

    private var navigation: some View {
        List(selection: $section) {
            ForEach(SettingsSection.Group.allCases) { group in
                Section(group.title) {
                    ForEach(group.sections) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
            }
        }
    }

    /// Vybraná stránka. `Repozitáře` dostávají seznam rep zvlášť — jsou jediná stránka, která
    /// nečte jen konfiguraci, ale i to, co dorazilo z pollingu.
    @ViewBuilder private var page: some View {
        switch section {
        case .sources:
            SourcesSettingsView(
                settings: settings,
                viewer: store.viewer,
                // Katalog je od #533 ve storu, ne v `@State` tohohle okna: čtou ho dvě obrazovky
                // (tahle a paleta ⌘K), a dvě instance by znamenaly dvě cache téhož seznamu.
                // `nil` = sekce `Organizace k prohledávání` se nekreslí (tak jsou na tom testy).
                catalog: store.repositoryCatalog,
                time: store.time
            )
        case .review: ReviewSettingsView(settings: settings)
        case .diff: DiffSettingsView(settings: settings)
        case .publishing: PublishingSettingsView(settings: settings)
        case .notifications: NotificationSettingsView(settings: settings)
        case .repositories:
            RepositorySettingsView(
                settings: settings,
                repositories: store.knownRepositories,
                // Příznaky merge (#556) jsou ve storu, ne v `@State` tohohle okna: čtou je dvě
                // obrazovky (tahle a potvrzení merge), a dvě cache téhož by znamenaly dvě volání
                // a dvě různé odpovědi. `nil` = ještě se to nezjistilo, tedy „nevím“.
                mergeSettings: { store.repositoryMergeSettings[$0] },
                loadMergeSettings: { await store.loadMergeSettings(for: $0) }
            )
        case .runtime: RuntimeSettingsView(settings: settings)
        // `Systém` (#529) je vedle `Repozitářů` druhá stránka, která nečte jen konfiguraci:
        // přihlašovací položka je **stav systému**, takže se čte a zapisuje přes store.
        case .system: SystemSettingsView(settings: settings, store: store)
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
                .foregroundStyle(Palette.find)
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
