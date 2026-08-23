import Foundation

/// Dění (#414) — sekce railu, ve které zůstane to, co dneska proletí jako notifikace.
///
/// Rozhodování, **co je novinka, co je nepřečtené a jak se to řadí**, je v `Policy`; tady je jen
/// to, kdy se store zeptá, co si o tom zapíše a co z toho drží v paměti.
///
/// **Zápis nezávisí na přepínačích notifikací** (#86). Ty rozhodují o **vyrušení**, ne o záznamu —
/// a právě proto je tahle obrazovka k něčemu: plní se i tehdy, když je aplikace jinak úplně
/// mlčící. Že banner nedorazil, řekne řádek chipem `bez banneru`.
extension AppStore {
    /// Sleduje vůbec někdo, co se na pull requestech děje? (#414)
    ///
    /// Notifikační centrum, nebo záznam dění — stačí jedno z těch dvou. Rozhoduje o tom, jestli se
    /// smí **spotřebovat** snímek fronty (`AnnouncedPullRequests`) a razítko oznámení
    /// (`ActivityNoticeLedger`): kdyby se posunuly bez konzumenta, vypadala by první nová PR jako
    /// už ohlášená a nikdo by se o ní nedozvěděl ani po zapnutí notifikací.
    ///
    /// Do #414 na tom místě stálo `notifications != nil`, protože konzument byl jeden. Dění je
    /// druhý a **schválně nezávisí na přepínačích** (#86) — ty rozhodují o vyrušení, ne o záznamu.
    var watchesPullRequestActivity: Bool {
        notifications != nil || activityLog != nil
    }

    // MARK: - Načtení a zápis

    /// Přečte záznam a značku poslední návštěvy — **jednou při startu**.
    func loadStoredActivity() async {
        // Značka se čte vždycky, i bez záznamu na disku: bez ní by po startu vyšlo jako nové
        // všechno (viz `Policy.unreadActivity`), tedy i to, co jsem už viděl.
        activityVisitSnapshot = activityVisits.lastVisit()
        guard let activityLog else { return }
        let stored = await activityLog.load()
        activityEvents = stored.events
        // Rozbitý soubor se **musí poznat**: prázdný záznam a ztracená historie dají obojí prázdný
        // seznam a klidné „nic se nestalo“ by nad tím druhým lhalo.
        isActivityLogUnreadable = stored.isUnreadable
    }

    /// Zapíše položky do dění. `nil` a prázdné pole neudělají nic.
    ///
    /// **Paměť se plní z návratové hodnoty**, ne vlastním vložením: vložení, odstranění duplicit
    /// a strop 200 je jedno rozhodnutí (`Policy.activityLog`) a druhá kopie by se s tou první
    /// rozešla — pak by na obrazovce byl jiný záznam než na disku.
    ///
    /// **Bez `activityLog` se nezapisuje ani do paměti.** `nil` znamená „odsud se
    /// nezaznamenává“ (testy), a záznam, který by po restartu zmizel, je horší než žádný: sekce
    /// by tvrdila, že historii má.
    func recordActivity(_ events: [ActivityEvent?]) async {
        let events = events.compactMap { $0 }
        guard !events.isEmpty, let activityLog else { return }
        activityEvents = await activityLog.record(events)
    }

    /// Zápis jedné položky — jen zkratka, ať se na volajících nehromadí `[…]`.
    func recordActivity(_ event: ActivityEvent?) async {
        await recordActivity([event])
    }

    // MARK: - Co je na obrazovce

    /// Sekce `Dění` po dnech, se značkou poslední návštěvy.
    ///
    /// Počítá se **z paměti**, jako dashboard: žádné čtení z disku při překreslení okna.
    var activityFeed: [ActivityFeedDay] {
        Policy.activityFeed(activityEvents, since: activityVisitSnapshot, now: time.now)
    }

    /// Kolik položek dění je nepřečtených.
    var unreadActivityCount: Int {
        Policy.unreadActivity(activityEvents, since: activityVisitSnapshot)
    }

    /// Odznak u `Dění` v railu. `nil` = nekreslí se — buď není co, nebo v té sekci zrovna stojím
    /// (v tomhle railu by odznak ikonu překryl).
    var railActivityCount: Int? {
        Policy.activityBadge(unread: unreadActivityCount, isActive: isActivityVisible)
    }

    /// Je sekce `Dění` zrovna na obrazovce? Sekce railu je obsah **domácí** záložky, takže nad
    /// otevřeným PR vidět není, i když je v railu vybraná.
    var isActivityVisible: Bool {
        activeTab == .home && railSection == .activity
    }

    /// Prázdný stav sekce. `nil` = něco v ní je.
    var activityEmptyState: ActivityEmptyState? {
        Policy.activityEmptyState(
            hasEvents: !activityEvents.isEmpty,
            isUnreadable: isActivityLogUnreadable,
            notificationsDenied: notificationFailure != nil,
            notificationsEnabled: configuration.global.notifications.isEnabled
        )
    }

    // MARK: - Značka poslední návštěvy

    /// Posune značku, když se ze sekce `Dění` odešlo (#414).
    ///
    /// **Při odchodu, ne při vstupu.** Kdyby se přepsala vstupem, přestalo by být nové zrovna to,
    /// na co se koukám — je to tatáž nesymetrie jako u `seedVisitBaseline(for:)` (#335).
    ///
    /// Volá se ze **všech** čtyř míst, která umí sekci opustit (`show(_:)`, `openTab`, `closeTab`,
    /// `selectTab`), a je proto napsané tak, aby na pořadí ani na počtu volání nezáleželo:
    /// rozhoduje **změna** viditelnosti, ne to, které tlačítko ji způsobilo.
    func syncActivityVisit() {
        let visible = isActivityVisible
        defer { wasActivityVisible = visible }
        guard wasActivityVisible, !visible else { return }
        let now = time.now
        activityVisitSnapshot = now
        activityVisits.record(now)
    }

    // MARK: - Klik na řádek

    /// Klik na řádek dění (#414) — otevře záložku PR a v ní ten tab, kde je co vidět.
    ///
    /// **Jde tím jediným vstupním bodem** (`openTab(_:in:)`, #409), ne vlastní dvojicí zápisů:
    /// tou samou cestou jde klik na notifikaci, řádek seznamu, karta dashboardu i paleta ⌘K.
    /// Dvě cesty k témuž skoku se rozejdou přesně v tom, na co se zapomene — u notifikací to byl
    /// `activeTab`, takže se po kliknutí v okně nestalo nic.
    ///
    /// **Tab se jmenuje**, na rozdíl od kliku na notifikaci: řádek dění ví, o čem je (nálezy,
    /// diskuze, commity), takže poslat člověka „tam, kde skončil“ by ho poslalo jinam, než na co
    /// klikl.
    ///
    /// **Čí PR to je, se tady nerozlišuje** — a nesmí se to plést s pravidlem o tom, co se do dění
    /// vůbec **zapisuje** (#332, `Policy.isReported`). Řádek o cizí aktivitě je o **vlastním** PR
    /// (#335) a záložka si obsah bere z plného seznamu, takže zúžení podle autora by tady znamenalo
    /// zahozený klik za nic.
    ///
    /// `.gitHub` sem nechodí: PR, který z fronty odešel, v seznamu není, takže by `openTab` otevřel
    /// záložku bez obsahu. Odkaz ven kreslí view (`ActivityFeedView`), tady se nedělá nic.
    func show(_ event: ActivityEvent) {
        guard case .tab(let tab) = Policy.destination(of: event.kind) else { return }
        openTab(event.pullRequest, in: tab)
    }

    // MARK: - Dopočítané druhy

    /// Zapíše, že nálezy zastaraly (#414) — **bez volání navíc**.
    ///
    /// Volá se z `loadDetail(for:)`, tedy ve chvíli, kdy aplikace **poprvé zná novou hlavu**.
    /// Nastavit se to tikem pollingu nedá: `PullRequestSummary` ze searche `headSha` nenese
    /// (`gh search prs` ho neumí), takže by za tím musel stát `gh pr view` na každé PR — tedy
    /// N+1 past, kvůli které se netahá ani detail. Cena je, že se rozchod zapíše teprve tehdy, kdy
    /// se na PR podívám nebo nad ním něco poběží; přínos je, že od té chvíle **zůstane** —
    /// dneska je to žlutý proužek, který zmizí s obrazovkou.
    ///
    /// Klíčem položky je hlava, takže se druhé všimnutí téhož rozchodu zahodí
    /// (`Policy.activityLog` odstraňuje duplicity podle identity).
    func noteStaleFindingsActivity(for pr: PRIdentifier) async {
        guard let stale = staleFindings(for: pr), stale.hasFindings else { return }
        await recordActivity(Policy.staleFindingsActivity(
            for: pr,
            ownership: ownership(of: pr),
            head: stale.head,
            // Commity zná dotažený detail (`loadDetail` je tahá hned za hlavičkou), takže se
            // počet nedopočítává žádným dalším voláním. `nil` (hlava nálezů v seznamu není,
            // typicky po force-pushi) znamená o commitech nemluvit.
            commits: Policy.commitsAfter(stale.findingsHead, in: commits[pr] ?? []),
            at: time.now
        ))
    }
}
