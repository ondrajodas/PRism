import AppKit
import SwiftUI

/// Okno nastavení. Dvě záložky — globální hodnoty a to, co si přebírá jednotlivé repo.
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
            // Okno si nechává říct od view, které v něm běží — `NSApp.keyWindow` nemusí
            // být to naše a posunout omylem hlavní okno je horší než nevystředit.
            .background(WindowReader(onWindow: centerWindow))
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
    /// Střed **hlavního okna**, ne obrazovky: na velkém monitoru s oknem u kraje by se
    /// nastavení otevřelo o půl metru vedle.
    ///
    /// **Hladina se nechává normální.** Zkoušelo se `.floating`, ať okno zůstane nahoře až
    /// do křížku, a **zahodilo se**: kliknutí mimo ho má odklidit, protože najíždět na
    /// křížek kvůli jedné změně je otrava. Diagnostikou je přitom ověřené, že se okno
    /// nezavírá — `willClose` nepřijde nikdy, jen zaleze za hlavní okno. Vypadá to stejně
    /// a vyhovuje to líp.
    private func centerWindow(_ window: NSWindow) {
        window.setFrameAutosaveName("")
        window.setFrame(Self.centered(window.frame, in: host(besides: window)), display: true)
    }

    /// Hlavní okno aplikace. Poznává se podle titulku — `WindowGroup("PRism")` mu ho dává
    /// a je to jediný stabilní znak, kterým se odliší od okna nastavení a od panelů.
    private func host(besides settings: NSWindow) -> NSRect? {
        NSApp.windows.first { $0 !== settings && $0.isVisible && $0.title == "PRism" }?.frame
    }

    /// Vystředí rámec v hostiteli a zarovná ho zpátky na obrazovku.
    ///
    /// To druhé je podstatné: hlavní okno může být zpola mimo viditelnou plochu a nastavení
    /// vystředěné v něm by skončilo za hranou, kde po něm není ani křížek.
    ///
    /// Pořadí ořezu je `max(min(…))`, ne naopak. U okna **širšího než obrazovka** vyjde
    /// `maxX - width` menší než `minX` a opačné pořadí by ho poslalo za levý okraj; takhle
    /// skončí zarovnané k němu.
    private static func centered(_ frame: NSRect, in host: NSRect?) -> NSRect {
        guard let host else { return frame }
        var moved = frame
        moved.origin = CGPoint(x: host.midX - frame.width / 2, y: host.midY - frame.height / 2)

        guard let visible = NSScreen.screens
            .max(by: { $0.frame.intersection(host).area < $1.frame.intersection(host).area })?
            .visibleFrame
        else { return moved }
        moved.origin.x = max(visible.minX, min(moved.origin.x, visible.maxX - frame.width))
        moved.origin.y = max(visible.minY, min(moved.origin.y, visible.maxY - frame.height))
        return moved
    }

    private func openConfigFile() {
        NSWorkspace.shared.open(CacheLayout.applicationSupport.configFile)
    }
}

private extension NSRect {
    /// Plocha průniku — podle ní se pozná, na které obrazovce okno převážně leží.
    var area: CGFloat { isNull ? 0 : width * height }
}

/// Podá volajícímu okno, ve kterém tenhle kus UI běží.
///
/// Spolehlivější než `NSApp.keyWindow`: to je v `onAppear` klidně ještě hlavní okno,
/// a sáhnout omylem na cizí okno je horší než nesáhnout na žádné.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // `view.window` je `nil`, dokud se view nezasadí do hierarchie.
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
