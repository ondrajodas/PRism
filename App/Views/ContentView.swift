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
        VStack(spacing: 0) {
            header
            // Rail místo `NavigationSplitView` (#180). Seznam PR je obsah domácí záložky, ne
            // trvalý levý sloupec: při čtení kódu se v něm nehrabe, a diff tím dostal celou
            // šířku okna. Záložky jsou **v hlavičce okna**, viz `toolbar` níž.
            HStack(spacing: 0) {
                SidebarRail(
                    section: $store.railSection,
                    queueCount: store.railQueueCount,
                    draftCount: store.pullRequestsWithDraft.count
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
        HStack(spacing: 3) {
            headerButton("sparkles", label: ReleaseNotesWindow.title, help: "Co se v které verzi změnilo") {
                openWindow(id: ReleaseNotesWindow.id)
            }
            headerButton("arrow.clockwise", label: "Obnovit", help: "Obnovit seznam") {
                Task { await store.refresh() }
            }
            headerButton("gearshape", label: "Nastavení", help: "Nastavení aplikace (⌘,)") {
                openSettings()
            }
        }
    }

    /// `label` je **povinný**, ne odvozený z ikony: VoiceOver by u ikonového tlačítka jinak
    /// přečetl jméno symbolu (`sparkles`), což uživateli neřekne nic.
    private func headerButton(
        _ symbol: String,
        label: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 27, height: 25)
                .foregroundStyle(Palette.ink2)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
    }

    /// Obsah okna: domácí záložka, nebo otevřené review.
    ///
    /// PR, který mezitím ze seznamu vypadl, si záložku **drží** — mergnutý pull request jde
    /// ještě dočíst a zavřít ho má člověk, ne tik pollingu. Když se o něm ale nedá zjistit ani
    /// titulek, řekne se to místo prázdné plochy.
    @ViewBuilder private var content: some View {
        switch store.activeTab {
        case .home:
            HomeView(store: store)
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
