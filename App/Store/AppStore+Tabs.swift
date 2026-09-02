import Foundation

/// Záložky, které přežijí restart (#527).
///
/// Aplikace se podle pravidel repa restartuje `bin/run.sh` po každém mergi, takže do #527 každý
/// merge zavřel všechno rozečtené. Snímek pruhu se proto zapisuje do `tabs.json` v cache slotu
/// a čte se **jednou** při startu.
///
/// **Obnovení nic nespouští, a je to ta podstatná věta.** Nepustí review ani session, nepřipraví
/// pracovní kopii a nepřidá nic do fronty — dotáhne **detail**, a to čtením (`gh pr view` přes
/// `GitHubGateway`, který zápisové metody nemá, tvrdá podmínka č. 1). Automat čte `summaries`
/// z tiku, takže se o obnovené záložce nemá kde dozvědět (#4).
extension AppStore {
    /// Zapíše snímek otevřených záložek.
    ///
    /// Volá se **při každé změně záložky** (otevření, zavření, přepnutí, změna tabu v PR, odchod
    /// domů) a **při ukončení aplikace**. Ty dva důvody se nedají spojit do jednoho: změna
    /// záložky je to, co drží snímek aktuální, kdežto ukončení je to, co zachytí **scroll**,
    /// kterým člověk skončil — bez něj by se po mergi obnovila poloha z okamžiku, kdy se do
    /// diffu přepnul.
    ///
    /// Zapisuje se **synchronně** (viz `OpenTabsStore`), protože z cesty ukončení není na co
    /// čekat.
    func persistOpenTabs() {
        guard let openTabsStore, !isRestoringTabs else { return }
        openTabsStore.save(openTabsSnapshot)
    }

    /// Snímek, jak se zapíše na disk. `internal` kvůli testům — ty se ptají na snímek, ne na
    /// obsah souboru, protože tvar JSONu hlídá vlastní sada.
    var openTabsSnapshot: OpenTabs {
        OpenTabs(
            tabs: openTabs.map { pullRequest in
                OpenTab(
                    pullRequest: pullRequest,
                    // **Volba tabu, ne výchozí hodnota** — `detailTab(for:)` odpovídá i za PR,
                    // který v mapě odchylek není, a právě to se má obnovit.
                    tab: detailTab(for: pullRequest),
                    anchor: diffScrollAnchors[pullRequest],
                    // Odkaz se pamatuje, obnovení ne: `restored` je značka **tohohle** spuštění,
                    // takže by se z ní jinak stal trvalý příznak „tenhle PR se kdysi obnovil“.
                    openedByLink: adoptedTabs[pullRequest] == .link
                )
            },
            active: activeTab.pullRequest
        )
    }

    /// Vrátí záložky z posledního běhu. Volá se **jednou, před prvním tikem** (`keepFresh()`).
    ///
    /// `async` je tady kvůli **pořadí, ne kvůli čekání**: `keepFresh()` na ni čeká, takže má okno
    /// poskládané záložky dřív, než se rozjede polling. Samotné čtení je synchronní (jeden malý
    /// soubor) a dotahování detailů se nechává běžet dál.
    ///
    /// Pořadí kroků má důvod: napřed se poskládá **celý** stav okna (záložky, jejich taby, kotvy
    /// a aktivní záložka), a **teprve pak** se začne dotahovat detail. Obráceně by první odpověď
    /// z GitHubu zapisovala do stavu, který se ještě staví.
    ///
    /// **Detail se dotahuje u každé obnovené záložky**, i u té, která ve zdrojích bude. Před
    /// prvním tikem se totiž neví, která to je — a čekat na tik znamená čekat i tam, kde by se
    /// čekat nemuselo, kdežto nedotáhnout znamená záložku, která zůstane na načítání navždycky
    /// (PR mimo zdroje se v seznamu neobjeví nikdy). Je to jedno `gh pr view` na záložku, tedy
    /// právě to, co si detail dotáhne sám při otevření.
    func restoreOpenTabs() async {
        guard let openTabsStore else { return }
        let stored = openTabsStore.load()
        guard !stored.isEmpty else { return }

        // Snímek se po celou dobu obnovení **nezapisuje** a uloží se jednou na konci: jinak by
        // každý nasazený tab uložil rozdělaný pruh (`setDetailTab` si zápis vyžádá). Ten jeden
        // zápis na konci má smysl — snímek se tím **srovná** s tím, co se doopravdy obnovilo,
        // typicky když aktivní záložka v pruhu nebyla.
        isRestoringTabs = true
        defer {
            isRestoringTabs = false
            persistOpenTabs()
        }

        for tab in stored.tabs {
            guard !openTabs.contains(tab.pullRequest) else { continue }
            openTabs.append(tab.pullRequest)
            // **Značka přijaté záložky je to, co drží obnovenou záložku naživu**: skládá jí
            // shrnutí z detailu, brání prvnímu tiku ji vyprázdnit a dělá z čekání na detail
            // `loading` místo věty „pull request zmizel“. `link` se u toho **nepřepisuje** —
            // pilulka `mimo zdroje` má přežít restart (#531).
            adoptedTabs[tab.pullRequest] = tab.openedByLink ? .link : .restored
            setDetailTab(tab.tab, for: tab.pullRequest)
            if let anchor = tab.anchor { pendingScrollAnchors[tab.pullRequest] = anchor }
        }

        // Aktivní až po celém seznamu, a **jen když je mezi záložkami**: `activeTab`, který
        // ukazuje mimo pruh, je okno bez jediné zvýrazněné záložky nad prázdnou plochou.
        if let active = stored.activeAmongTabs {
            activeTab = .pullRequest(active)
            selection = active
        }

        // Detaily **souběžně a bez čekání**, tou samou cestou jako u záložky otevřené odkazem
        // (#531). Čekat na ně by znamenalo odložit první tik o jedno `gh pr view` na záložku —
        // a přitom je to zbytečné: dokud detail nedorazí, má záložka puntík načítání, což je
        // přesně ten stav, kvůli kterému vznikl.
        //
        // **Ptá se jen u záložek, o kterých se nic neví.** Po restartu to je každá z nich (tik
        // ještě nebyl), ale podmínka tu být musí: `restoreOpenTabs()` se pouští jednou, jenže
        // kdyby ji někdo zavolal podruhé, nemá se ptát na PR, který už seznam přinesl.
        for tab in stored.tabs where summary(for: tab.pullRequest) == nil {
            Task { await loadExternalDetail(of: tab.pullRequest) }
        }
    }

    /// Co se nakreslí u záložky v pruhu (#527).
    ///
    /// Skládá se **ve store, ne ve view**: dovnitř jde pět různých míst stavu (fáze běhu,
    /// obsah záložky, drafty, snímek shrnutí, stav review) a rozhodnutí nad nimi patří do
    /// `Policy` — `ReviewTabsView` z toho dostane hotovou odpověď.
    func tabMark(for pullRequest: PRIdentifier) -> WindowTabMark {
        Policy.tabMark(
            isRunning: isReviewing(pullRequest),
            // **Načítání se čte z obsahu záložky**, ne z vlastní značky: „detail ještě nedorazil“
            // je tatáž otázka, na kterou odpovídá plocha záložky (`Policy.tabContent`), takže dvě
            // místa by znamenala pruh, který tvrdí něco jiného než obrazovka pod ním.
            isLoading: tabContent(for: pullRequest) == .loading,
            hasDraft: hasDraft(pullRequest),
            state: summary(for: pullRequest)?.state ?? openTabSnapshots[pullRequest]?.state,
            review: reviewState(for: pullRequest)
        )
    }

    /// Kotva, kterou má diff doposadit — a **spotřebuje ji** (#527).
    ///
    /// Spotřebování je celý smysl: skok se má stát **jednou**, po obnovení. Kdyby kotva v mapě
    /// zůstala, vracel by se výřez na uložené místo při každém přepnutí do `Změněných souborů`,
    /// tedy i po tom, co si člověk odscrolloval jinam.
    func takePendingScrollAnchor(for pullRequest: PRIdentifier) -> DiffScrollAnchor? {
        guard let anchor = pendingScrollAnchors[pullRequest] else { return nil }
        pendingScrollAnchors[pullRequest] = nil
        return anchor
    }

    /// Kde stojí výřez diffu. Hlásí to `DiffAnchorReporter` při scrollování.
    ///
    /// **Nezapisuje na disk**, jen do paměti: zápis při každém posunu výřezu by z `tabs.json`
    /// udělal soubor, do kterého se sahá při scrollování. Na disk to jde s příští změnou
    /// záložky, nebo při ukončení aplikace — obojí je `persistOpenTabs()`.
    ///
    /// **Zapisuje se jen u otevřené záložky.** Diff commitu ani náhled kotvu nehlásí (nemají
    /// komu), ale i tak: mapa bez téhle brány by držela záznamy o PR, které v pruhu nejsou.
    func noteDiffScrollAnchor(_ anchor: DiffScrollAnchor?, for pullRequest: PRIdentifier) {
        guard openTabs.contains(pullRequest) else { return }
        // `nil` **nemaže**, a je to rozhodnutí: „zrovna nevím, kde výřez stojí“ (rozsahy souborů
        // se přeměřují, bloky se odpojily) není totéž jako „do diffu se nekouklo“. Zahodit
        // poslední známou polohu kvůli jednomu průchodu bez odpovědi by znamenalo obnovit se na
        // začátek diffu právě po tom, co se okno přerovnalo.
        guard let anchor else { return }
        diffScrollAnchors[pullRequest] = anchor
    }
}
