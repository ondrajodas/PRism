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

    /// Odznak u `Dění` v railu. `nil` = nekreslí se, a od #526 je to jediný důvod: **není co**.
    /// Do #526 do toho padalo i „v té sekci zrovna stojím“ — odznak tehdy seděl na ikoně a překryl
    /// ji. Od #526 je v rohu a aktivní sekci značí pruh na hraně railu, takže se počet nepřečtených
    /// ukazuje i zevnitř `Dění`.
    var railActivityCount: Int? {
        Policy.activityBadge(unread: unreadActivityCount)
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
    /// Volá se z `loadDetail(for:)`, tedy ve chvíli, kdy aplikace hlavu zná z jiného důvodu.
    /// Tikem to od #420 pozná `refreshStaleHeads(in:)`, takže obvykle je řádek na obrazovce dřív,
    /// než se na PR vůbec podívám; tahle cesta zůstává proto, že o rozchodu ví **s počtem
    /// commitů** — a je to jediná cesta u PR, na které se dotaz nedostal (strop dotazu, chybějící
    /// odpověď GitHubu, nebo `updatedAt`, které se od minula nepohnulo).
    ///
    /// Klíčem položky je hlava, takže se druhé všimnutí téhož rozchodu zahodí
    /// (`Policy.activityLog` odstraňuje duplicity podle identity) — **včetně** toho z tiku. Kdo je
    /// první, ten zapíše řádek; datum je z obou cest stejné, protože je to čas vzniku hlavy.
    func noteStaleFindingsActivity(for pr: PRIdentifier) async {
        guard let stale = staleFindings(for: pr), stale.hasFindings else { return }
        let commits = commits[pr] ?? []
        await recordActivity(Policy.staleFindingsActivity(
            for: pr,
            ownership: ownership(of: pr),
            head: stale.head,
            // Commity zná dotažený detail (`loadDetail` je tahá hned za hlavičkou), takže se
            // počet nedopočítává žádným dalším voláním. `nil` (hlava nálezů v seznamu není,
            // typicky po force-pushi) znamená o commitech nemluvit.
            commits: Policy.commitsAfter(stale.findingsHead, in: commits),
            // Čas události, ne zjištění (#420) — a je to tatáž hodnota, jakou z druhé strany nese
            // `PullRequestHead.committedAt`, jen vytažená z už načteného seznamu commitů.
            headAt: Policy.commitDate(of: stale.head, in: commits),
            noticedAt: time.now
        ))
    }

    /// Zeptá se na **hlavy** PR, na kterých leží uložené nálezy, a zapíše, které zastaraly (#420).
    ///
    /// Do #420 se rozchod poznal jedině při otevření PR nebo při běhu review — tedy zrovna tehdy,
    /// když už ho vidím i bez dění (hlavička nad taby ho říká), takže ten řádek nepřinášel nic.
    /// Novinka, která přijde jedině tehdy, když se na PR koukám, je nakreslená nula.
    ///
    /// **Jedno volání na tik, ne jedno na PR ani na repozitář.** Koho se zeptat, rozhoduje
    /// `Policy.staleHeadProbe`; `gateway.fetchHeads(of:)` z toho složí jeden GraphQL dokument.
    /// Předfiltr přes `updatedAt` znamená, že se na klidný den neptáme vůbec — a prázdný seznam
    /// se ani nespouští.
    ///
    /// **Bez záznamu dění se neptá vůbec.** Za zastaralé nálezy banner nechodí (jsou to data pro
    /// tu obrazovku, ne vyrušení), takže je záznam jediný konzument — dotaz bez něj by byl dotaz
    /// za nic. Je to jiná podmínka než `watchesPullRequestActivity`: ta jmenuje obojí právě proto,
    /// že u ostatních druhů je druhým konzumentem notifikační centrum.
    func refreshStaleHeads(in summaries: [PullRequestSummary]) async {
        guard activityLog != nil else { return }
        let candidates = Policy.staleHeadProbe(
            of: summaries,
            mine: ownLogins,
            // Uložené nálezy v paměti — `reviewRecords` se plní při startu z disku, takže předfiltr
            // nestojí ani čtení souboru. Odmítnuté se počítají, viz `Policy.staleFindings(of:head:)`.
            hasFindings: { reviewRecords[$0].map { !$0.findings.isEmpty } ?? false },
            probedAt: { headProbes[$0] }
        )
        guard !candidates.isEmpty else { return }

        let heads: [PRIdentifier: PullRequestHead]
        do {
            heads = try await gateway.fetchHeads(of: candidates)
        } catch {
            // **Razítka se neposouvají**, takže se příští tik zeptá znovu — tatáž nesymetrie jako
            // u razítka rozhlídky (#335). Do okna se to nehlásí schválně: nic v něm netvrdí, že
            // hlavy zná, a stav GitHubu drží stavový řádek z pollingu (`gitHubCall`). Jediný
            // následek je řádek dění o tik později, nebo až při otevření PR.
            return
        }

        // `updatedAt` se vytáhne **jednou**, ne hledáním v seznamu u každého kandidáta: je to tatáž
        // úvaha jako u `titles(from:)` v `AppStore+Notifications`.
        let updates = Dictionary(summaries.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })

        var events: [ActivityEvent?] = []
        for pr in candidates {
            // Razítko dostane jedině PR, na kterou se **doopravdy ptalo** a odpověď dorazila:
            // chybějící alias znamená „nevíme“, a to se nesmí zapsat jako „zjištěno“, jinak by se
            // na tu PR nezeptalo, dokud se `updatedAt` nepohne.
            guard let head = heads[pr] else { continue }
            headProbes[pr] = updates[pr]
            guard let stale = Policy.staleFindings(of: reviewRecords[pr], head: head.sha),
                  stale.hasFindings
            else { continue }
            events.append(Policy.staleFindingsActivity(
                for: pr,
                ownership: ownership(of: pr),
                head: stale.head,
                // **O commitech se z tiku nemluví.** Kolik jich po hlavě nálezů přišlo, se ze
                // seznamu commitů dopočítat dá (`Policy.commitsAfter`), jenže ten se tahá až
                // s detailem — a dotáhnout ho kvůli číslu v řádku je zpátky ta N+1 past. Řádek
                // proto řekne jen `hlava je teď <sha>`; číslo, které by se nemělo o co opřít, je
                // horší než žádné.
                commits: nil,
                headAt: head.committedAt,
                noticedAt: time.now
            ))
        }
        // **Jeden zápis za tik, ne jeden na PR** — jako u nových PR v `announceNewPullRequests`.
        // `recordActivity` sahá na disk, takže zápis v cyklu by u pěti rozchodů znamenal pět
        // uložení téhož souboru; prázdné pole se navíc nedotkne ničeho.
        await recordActivity(events)
    }
}
