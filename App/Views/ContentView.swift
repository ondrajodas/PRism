import SwiftUI

/// Hlavní okno: vlevo seznam PR, vpravo místo pro diff a nálezy.
struct ContentView: View {
    /// Store vlastní `PreflightModel` nad oknem, ne tohle view — okno nastavení je vlastní
    /// scéna a k `@State` uvnitř okna by se nedostalo.
    @Bindable var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    /// Čte se **tady, v těle okna**, ne v toolbaru bočního panelu — tam je to němá akce
    /// (viz `PullRequestListView.openReleaseNotes`).
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// Rozdělané odeslání review. `nil` = potvrzovací sheet je zavřený.
    ///
    /// Bydlí **tady, ne v detailu PR**, ačkoli se tam zakládá. Detail se kreslí jen tak dlouho,
    /// dokud je vybraný PR v seznamu z pollingu — a odeslané review ruší `review-requested`,
    /// takže právě ten PR z výchozího zdroje na příštím tiku **vypadne**. Sheet zavěšený na
    /// detailu by tím zmizel bez stopy: uprostřed odesílání, nebo zrovna nad hláškou „odpovědi
    /// nerozumím, zkontroluj to na GitHubu“, která je jediným místem, kde se to člověk dozví.
    /// Modalita proti tomu nechrání, ta zastaví uživatele, ne tik pollingu.
    ///
    /// Ve store to naopak být nesmí: objekt má zaniknout se zavřením sheetu, protože v něm
    /// vzniká jediná cesta ven (tvrdá podmínka č. 1).
    @State private var submission: ReviewSubmission?

    var body: some View {
        // Průchod tělem se počítá, jen když je zapnutá diagnostika (#361) — jinak je to načtení
        // jednoho statického `Optional`u. Viz `RenderDiagnostics`.
        let _ = RenderDiagnostics.pass(Self.self)
        VStack(spacing: 0) {
            header
            // Rail místo `NavigationSplitView` (#180). Seznam PR je obsah domácí záložky, ne
            // trvalý levý sloupec: při čtení kódu se v něm nehrabe, a diff tím dostal celou
            // šířku okna. Záložky jsou **v hlavičce okna**, viz `toolbar` níž.
            HStack(spacing: 0) {
                SidebarRail(
                    // **Přes `show(_:)`, ne přímo do `railSection`** (#414). Odchod ze sekce `Dění`
                    // posouvá značku poslední návštěvy, a to umí jedině store — binding rovnou do
                    // pole by tu jednu cestu obešel a značka by se z railu nikdy neposunula.
                    section: Binding(get: { store.railSection }, set: { store.show($0) }),
                    queueCount: store.railQueueCount,
                    mineCount: store.railMineCount,
                    draftCount: store.pullRequestsWithDraft.count,
                    activityCount: store.railActivityCount,
                    // Vzhled se čte z konfigurace a zapisuje do ní (#278) — rail je ovládání, ne
                    // druhé místo, kde by se stav držel.
                    appearance: store.configuration.global.appearance,
                    setAppearance: { mode in Task { await store.setAppearance(mode) } }
                )
                content
            }
            StatusBarView(store: store)
        }
        // **Bezpečná oblast se ignoruje pro celé okno, ne jen pro hlavičku.** `fullSizeContentView`
        // obsah pod lištu roztáhne, ale SwiftUI si pod ni vloží inset — a když ho ignoruje jen
        // hlavička, zůstane ten pruh **pod ní**. Změřeno přes accessibility: hlavička končila
        // na y=76 a obsah začínal až na y=120.
        .ignoresSafeArea(edges: .top)
        // Barvy okna drží `Palette` (#180): systémová šedá je neutrální, kdežto návrh stojí na
        // neutrálech posunutých do modrofialové — do stejné rodiny jako akcent. Tint se nasazuje
        // **na kořen okna**, takže ho dědí i odznaky a tlačítka uvnitř; jinde v aplikaci se
        // fialová nezadrátovává.
        .background(Palette.background)
        .tint(Palette.accent)
        .fullSizeContentWindow()
        // Potvrzení odeslání. `item:`, ne `isPresented:`: sheet nemá co ukazovat bez snímku
        // draftu, takže `nil` je zavřený stav i zdroj dat naráz.
        .sheet(item: $submission) { submission in
            ReviewSubmissionSheet(submission: submission) { self.submission = nil }
        }
        .hiddenShortcuts { shortcuts }
        // Paleta je **překryv okna, ne sheet**: sheet si bere šířku okna a přijíždí shora jako
        // dialog, kdežto návrh má kartu 560 bodů, která visí nad obsahem a zbytek jen ztmaví.
        .overlay(alignment: .top) { palette }
        // **Ztmavení, ne rozostření.** `.blur()` protlačí celé okno přes offscreen
        // vykreslení, a to i s poloměrem 0 — text tím ztratí subpixelové vyhlazení a
        // v seznamu, diffu i hlavičce vypadá rozmazaně a „skáče“. Ověřeno tím, že se
        // modifikátor odebral: bez něj je vykreslení v pořádku.
        .overlay {
            Color.black
                .opacity(store.isSettingsFrontmost ? 0.18 : 0)
                // Klik má okno vybrat, ne se zastavit o překryv.
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.18), value: store.isSettingsFrontmost)
        }
        // Smyčka žije, dokud žije okno — zavření okna task zruší a polling se zastaví.
        .task { await store.keepFresh() }
        // Konfigurace se edituje v souboru mimo aplikaci, takže se načte pokaždé, když se
        // do ní člověk vrátí.
        .onChange(of: scenePhase) { _, phase in
            // Na pozadí se dostupnost služeb nekontroluje — aplikace, kterou nikdo nevidí,
            // nemá komu svítit puntíkem.
            store.windowVisibilityChanged(phase != .background)
            guard phase == .active else { return }
            Task { await store.reloadConfiguration() }
        }
    }

    /// Zkratky, které registruje **okno**, ne obsah v něm (#441).
    ///
    /// Bydlí tady schválně: paleta ⌘K (#184), přepínání záložek (#245), zavření záložky, obnovení
    /// i sekce railu mají chodit **i z domácí záložky** — tlačítko v pruhu nebo v railu by je
    /// registrovalo jen tam, kde je pruh nebo rail sám. Kombinace kláves se tady nepíšou, jsou
    /// v katalogu (`Policy.windowShortcut`); tady se rozhoduje jen o akci a o tom, kdy je zakázaná.
    ///
    /// Zakázané tlačítko klávesu **nebere a propadne dál** — tentýž vzorec jako u `⌘⏎` a `⌘2`
    /// v detailu PR.
    @ViewBuilder private var shortcuts: some View {
        WindowShortcutButtons(action: .palette) { store.togglePalette() }
        WindowShortcutButtons(action: .nextTab) { store.selectTab(.forward) }
        WindowShortcutButtons(action: .previousTab) { store.selectTab(.backward) }
        // Na domácí záložce není co zavírat — rozhoduje `Policy.closableTab`, ne `if` tady.
        WindowShortcutButtons(action: .closeTab, isEnabled: closableTab != nil) {
            guard let closableTab else { return }
            store.closeTab(closableTab)
        }
        // Dokud běží dotaz, je zakázané i tlačítko `⟳` — a je to **tatáž podmínka** (#442):
        // druhý dotaz by ten první nezrychlil.
        WindowShortcutButtons(
            action: .refresh,
            isEnabled: Policy.refreshControl(isRefreshing: store.isRefreshing).isEnabled
        ) {
            Task { await store.refresh() }
        }
        // Sekce se berou z `allCases`, takže šestá dostane zkratku sama — vybrat jí klávesu si
        // vynutí `Policy.windowShortcut`, kde je nad `RailSection` vyčerpávající `switch`.
        ForEach(RailSection.allCases) { section in
            WindowShortcutButtons(action: .openSection(section)) { store.show(section) }
        }
    }

    private var closableTab: PRIdentifier? { Policy.closableTab(in: store.activeTab) }

    /// Vlastní hlavička okna (#180) — záložky vedle semaforu a vpravo akce.
    ///
    /// **Kreslí se sama, systémová titulková lišta je schovaná** (`.windowStyle(.hiddenTitleBar)`).
    /// Přes `toolbar` to nešlo: macOS si položky sází po svém a pruh záložek z toho vyšel jako
    /// řádek tlačítek, ne jako záložky. Cenou je odsazení na semafor a to, že se okno musí dát
    /// táhnout — obojí je vyřešené níž.
    private var header: some View {
        HStack(spacing: 14) {
            // Místo pro semafor. Pevná hodnota, protože ta tři kolečka mají pevnou velikost
            // i rozteč; menší odsazení je překryje, větší nechá díru.
            // Semafor macOS končí na x=70 (tři kolečka po 16 s roztečí 23, od x=8). Návrh dává
            // za světla mezeru 14, takže záložky mají začínat na x=84: 13 odsazení + 57 + 14.
            // Změřeno přes accessibility, ne odhadnuto.
            Spacer().frame(width: 57)
            ReviewTabsView(
                active: $store.activeTab,
                tabs: store.openTabSummaries,
                state: store.reviewState(for:),
                hasDraft: store.hasDraft(_:),
                isRunning: store.isReviewing(_:),
                close: store.closeTab(_:)
            )
            headerActions
        }
        .padding(.horizontal, 13)
        .frame(height: 40)
        .background(Palette.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
        // Bez systémové lišty se okno tahá za hlavičku — jinak by se s ním nedalo hnout jinak
        // než za okraje.
        .gesture(WindowDragGesture())
    }

    private var headerActions: some View {
        HStack(spacing: HeaderButtonMetrics.spacing) {
            paletteButton
            HeaderButton(
                symbol: "sparkles",
                label: ReleaseNotesWindow.title,
                help: "Co se v které verzi změnilo"
            ) {
                openWindow(id: ReleaseNotesWindow.id)
            }
            // Podobu i to, jestli tlačítko bere klik, rozhoduje `Policy.refreshControl` (#442).
            // Je to **jediné místo**, ze kterého se ta podmínka čte: bere si ji odsud
            // i `AppStore.refresh()` a #441 z ní vyrobí povolení pro zkratku `⌘R`.
            RefreshButton(isRefreshing: store.isRefreshing) {
                Task { await store.refresh() }
            }
            HeaderButton(
                symbol: "gearshape",
                label: "Nastavení",
                help: "Nastavení aplikace (⌘,)"
            ) {
                openSettings()
            }
        }
    }

    /// Vstup do palety v hlavičce okna (`.tbtn.key` z návrhu) — obtažená kapsle s `⌘K`.
    ///
    /// Zkratka sama by stačila k používání, ne k **nalezení**: paleta je jediná obrazovka, na
    /// kterou z okna nevede žádné kliknutí, takže bez tohohle tlačítka by o ní věděl jen ten,
    /// kdo si přečetl release notes.
    private var paletteButton: some View {
        Button { store.togglePalette() } label: {
            Text(verbatim: "⌘K")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ink3)
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background(Palette.surface, in: .rect(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 1) }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Najít nález, soubor, pull request nebo akci (⌘K)")
        .accessibilityLabel("Najít")
    }

    /// Karta palety a ztmavený zbytek okna.
    ///
    /// Zavřená paleta se do hierarchie **vůbec nedostane**, a to je podmínka, ne úspora: jsou v ní
    /// zkratky na plné šipky, které by jinak seznamu PR sebraly pohyb po řádcích.
    @ViewBuilder private var palette: some View {
        if store.isPaletteOpen {
            ZStack(alignment: .top) {
                // Ztmavení **bere kliknutí**: klik mimo kartu paletu zavře, jako v každém
                // vyhledávacím okně. Tím se liší od ztmavení pod oknem nastavení, které klik
                // schválně propouští, protože tam má klik vybrat okno.
                Color.black.opacity(0.28)
                    .onTapGesture { store.closePalette() }
                CommandPaletteView(
                    items: store.paletteItems,
                    run: choose(_:),
                    close: store.closePalette
                )
                // Pod hlavičkou okna (40 bodů), ne uprostřed: karta roste dolů, takže od horní
                // hrany zůstává na stejném místě, ať je výsledků kolik chce.
                .padding(.top, 88)
            }
            .ignoresSafeArea()
        }
    }

    /// Vykonání řádku palety.
    ///
    /// Paleta se zavírá **vždycky**, i u akce, po které okno zůstane, jak bylo: ⌘K je jeden hmat
    /// a otevřená karta nad hotovou akcí by ho zdvojila. Nastavení otevírá okno, a to umí jedině
    /// view — proto ten efekt ze store chodí až sem.
    private func choose(_ item: CommandPalette.Item) {
        store.closePalette()
        switch store.reveal(item.target) {
        case .openSettings: openSettings()
        case nil: break
        }
    }

    /// Obsah okna: domácí záložka, nebo otevřené review.
    ///
    /// PR, který mezitím ze seznamu vypadl, si záložku **drží** — mergnutý pull request jde
    /// ještě dočíst a zavřít ho má člověk, ne tik pollingu. Když se o něm ale nedá zjistit ani
    /// titulek, řekne se to místo prázdné plochy.
    @ViewBuilder private var content: some View {
        switch store.activeTab {
        case .home:
            // `openSettings` se předává jako uzávěr **z těla okna** (#331), stejně jako
            // `openWindow` u novinek: prázdný stav sekce `Moje PR` nabízí dopsat chybějící zdroj,
            // a scénickou akci z environmentu si má brát to view, o kterém je ověřené, že jí
            // rozumí — ne každé, které ji potřebuje.
            HomeView(store: store, openSettings: { openSettings() })
        case .pullRequest(let id):
            if let summary = store.summary(for: id) {
                PullRequestDetailView(store: store, pullRequest: summary, submission: $submission)
            } else {
                EmptyStateView(
                    // Čekání, ne porucha: nic se nerozbilo, PR jen vypadl z výsledků hledání
                    // (typicky po odeslaném review).
                    nature: .waiting,
                    symbol: "questionmark.folder",
                    title: "Pull request zmizel ze seznamu",
                    message: "Nejspíš se mergnul nebo už po tobě review nikdo nechce. Zavři záložku, nebo počkej na další načtení.",
                    primary: .init(title: "Zavřít záložku") { store.closeTab(id) }
                )
            }
        }
    }

}
