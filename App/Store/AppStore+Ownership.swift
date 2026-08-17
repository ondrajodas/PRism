import Foundation

/// Čí jsou pull requesty v seznamu (#330).
///
/// Samo **dotažení** loginu (`loadViewer()`) je v `AppStore.swift` u ostatních věcí, které se
/// načítají při startu — a taky proto, že `viewer` je `private(set)`: zapsat ho smí jedině ten
/// jeden loader, ne kterýkoli extension nebo view.
extension AppStore {
    /// Loginy, které se počítají za moje — viewer plus to, co je v konfiguraci (#330).
    ///
    /// **Počítá se při každém čtení, nedrží se ve stavu.** Jsou to jeden až dva loginy, kdežto
    /// uložená množina by měla dvě místa, která by ji musela obnovovat (dotažený login a `apply(_:)`
    /// konfigurace) — tedy dvě pravdy o tom, kdo jsem. Kdo ji potřebuje pro **celý seznam**, si ji
    /// má vzít jednou do lokální hodnoty a zavolat `Policy.ownership(of:mine:)` nad řádky, ne se
    /// ptát storu u každého z nich.
    var ownLogins: Set<String> {
        Policy.ownLogins(viewer: viewer, configured: configuration.global.ownLogins)
    }

    /// Čí je pull request. Dokud není znám `viewer`, je všechno `.theirs`.
    ///
    /// Počítá se **nad hotovým seznamem**, ne při slučování zdrojů: `PullRequestList.merged` je
    /// o deduplikaci, ne o tom, čí co je, a jeden PR umí přijít z víc zdrojů naráz.
    func ownership(of summary: PullRequestSummary) -> PullRequestOwnership {
        Policy.ownership(of: summary, mine: ownLogins)
    }

    /// Je mezi zdroji ten, který přináší vlastní PR (#330)?
    ///
    /// Prázdná sekce `Moje PR` bez něj znamená „zdroj chybí“, ne „nic tam neleží“ — a to jsou dvě
    /// různé věty. Kreslí ji #331, poznat se to musí tady.
    ///
    /// Ptá se na **aktivní** zdroje, tedy tytéž, na které se aplikace doopravdy ptá: rozepsaný
    /// řádek bez dotazu se přeskakuje v `activeSources`, takže by jinak stačilo mít v nastavení
    /// prázdný řádek, aby si okno myslelo, že vlastní PR sleduje.
    var tracksOwnPullRequests: Bool {
        Policy.tracksOwnPullRequests(in: configuration.activeSources, mine: ownLogins)
    }

    // MARK: - Sekce `Moje PR` (#331)

    /// Moje PR pro sekci `Moje PR` — **zúžené filtrem a pak podle autora**.
    ///
    /// Stojí na `visiblePullRequests`, a je to v pořádku právě proto, že to čte **jedině seznam**:
    /// rozřazení podle autora je další zúžení pohledu, ne nový zdroj pravdy (viz
    /// `AppStore.pullRequests` a `Policy.pullRequests(_:ownedBy:mine:)`). Kdyby na něm viselo
    /// cokoli z úklidu, znamenalo by přihlášení jiným účtem smazanou cache.
    ///
    /// **Množina loginů se bere jednou pro celý seznam**, ne u každého řádku — `ownLogins` se
    /// počítá při každém čtení.
    var visibleOwnPullRequests: [PullRequestSummary] {
        Policy.pullRequests(visiblePullRequests, ownedBy: .mine, mine: ownLogins)
    }

    /// Kolik mých PR schoval filtr. Vlastní číslo, ne `hiddenPullRequestCount`: v sekci
    /// `Moje PR` by celkový počet mluvil i o cizích řádcích, které tam nikdy nebyly.
    var hiddenOwnPullRequestCount: Int {
        guard filter.isActive else { return 0 }
        let mine = ownLogins
        return Policy.pullRequests(pullRequests, ownedBy: .mine, mine: mine).count { !filter.matches($0) }
    }

    /// Odznak u sekce `Moje PR` v railu (#331) — kolik vlastních PR **čeká na tah**.
    ///
    /// Ne počet otevřených PR: odznak na railu znamená „je co dělat“ (viz
    /// `Policy.ownPullRequestsAwaitingMove`). `nil`, dokud se seznam nenačetl — tatáž úvaha jako
    /// u fronty: nula nad nenačtenými daty vypadá jako hotovo.
    var railMineCount: Int? {
        guard lastSuccess != nil else { return nil }
        return Policy.ownPullRequestsAwaitingMove(
            visibleOwnPullRequests,
            records: reviewRecords,
            conversation: conversation(for:)
        )
    }

    /// Proč je sekce `Moje PR` prázdná — chybějící zdroj, nenačtený login, filtr, nebo nic
    /// otevřeného (#331). Rozhoduje `Policy.ownListEmptyReason`.
    var ownListEmptyReason: ListEmptyReason? {
        // Jedním průchodem, jako u `listEmptyReason`: tenhle getter čte SwiftUI při každém
        // překreslení seznamu.
        let mine = ownLogins
        let own = Policy.pullRequests(pullRequests, ownedBy: .mine, mine: mine)
        let hidden = filter.isActive ? own.count { !filter.matches($0) } : 0
        return Policy.ownListEmptyReason(
            poll: emptyReason,
            tracksOwnSource: tracksOwnPullRequests,
            knowsViewer: !mine.isEmpty,
            visible: own.count - hidden,
            hidden: hidden
        )
    }

    /// Moje PR na dashboardu — tytéž řádky jako v sekci, jen seřazené podle závažnosti.
    ///
    /// **Plný seznam, ne zúžený filtrem**, ze stejného důvodu jako `dashboardQueue`: dashboard je
    /// tvrzení o tom, co venku mám, ne o tom, co je zrovna vidět.
    var dashboardOwnPullRequests: [QueueEntry] {
        Policy.byUrgency(
            Policy.pullRequests(pullRequests, ownedBy: .mine, mine: ownLogins).map {
                QueueEntry(
                    pullRequest: $0,
                    state: reviewState(for: $0.id),
                    row: queueRow(for: $0.id),
                    hasDraft: hasDraft($0.id)
                )
            }
        )
    }
}
