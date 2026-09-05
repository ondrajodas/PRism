import Foundation

/// Odložení pull requestu (#512) — *tenhle teď vidět nechci, ozvi se mi, až…*.
///
/// **Odložení je stav, který něco skrývá, takže musí být poznat, že něco skryté je.** Fronta, ze
/// které PR potichu zmizí, je horší než fronta, ve které leží — proto se odložený PR schová
/// **a zároveň** se objeví v bloku `Odložené · N` pod frontou, na desce se počítá do věty pod
/// pozdravem a jeho návrat udělá řádek v `Dění`.
///
/// **Jen cizí PR, a je to zúžení, ne opomenutí.** Odložit se dá to, co po mně někdo chce; vlastní
/// PR je moje práce a „nechci to teď vidět“ na ni neodpovídá — o tom, kdy se na ni podívám,
/// rozhoduje to, kdy pushnu. Kdyby šlo odložit i vlastní PR, zmizel by ze sekce `Moje PR`,
/// **pod kterou žádný blok `Odložené` není** — tedy přesně ta tichá díra, které se tohle issue
/// vyhýbá. Brána je v `Policy.canSnooze(_:)`, ne v kresbě.
extension AppStore {
    // MARK: - Načtení a dotazy

    /// Odložení z disku. Čte se **jednou při startu a před prvním tikem** — tik, který proběhne
    /// dřív, by na odložený PR pustil automatické review, které si nikdo neobjednal.
    func loadStoredSnoozes() async {
        guard let snoozeStore else { return }
        snoozes = await snoozeStore.load()
    }

    /// Je tenhle PR odložený?
    ///
    /// **Jediné místo, kterého se ptá fronta, deska, odznak, souhrn, notifikace i automat.** Druhá
    /// odpověď na tuhle otázku by znamenala PR, který zmizel z fronty a přesto na něj běží review.
    func isSnoozed(_ pr: PRIdentifier) -> Bool { snoozes[pr] != nil }

    /// Odložení toho PR. `nil` = odložený není.
    func snooze(of pr: PRIdentifier) -> Snooze? { snoozes[pr] }

    /// Smí se tenhle PR odložit? Rozhoduje `Policy.canSnooze(_:)` nad autorstvím — viz doc typu.
    func canSnooze(_ pr: PRIdentifier) -> Bool {
        Policy.canSnooze(ownership(of: pr))
    }

    /// Co řádek umí s odložením — **jediné místo, které tu dvojici skládá** (#512, oprava po
    /// proklikání).
    ///
    /// Nabídka byla navěšená jedině ve `PullRequestListView`, jenže `PullRequestRow` se kreslí na
    /// **třech** místech. Kdo řádek kreslí, ptá se tady: brána (`canSnooze`), nabídka
    /// (`snoozeOffers`) i akce jsou v jedné odpovědi, takže se druhé místo nemá čím rozejít
    /// s prvním.
    ///
    /// **Vlastní PR dostane prázdnou nabídku, ne `nil`.** Rozdíl je čitelný v řádku: `nil` znamená
    /// „o odložení mi nikdo nic neřekl“ (náhledy), prázdno „řekl, a nesmí se“ — nakreslí se z toho
    /// obojího **nic**.
    ///
    /// **Bere `PullRequestSummary`, ne `PRIdentifier`, a je to výkonové rozhodnutí.** Přes identitu
    /// vede cesta k autorství lineárním hledáním v `pullRequests` (`AppStore.author(of:)`), takže
    /// by seznam o třiceti řádcích při každém překreslení udělal třicet průchodů. Všechna tři
    /// kreslicí místa summary mají — `ownership(of:)` nad ní je O(1). Druhé přetížení nad
    /// identitou schválně **není**: nikdo ho nepotřebuje a existovalo by jen kvůli testům.
    func snoozeAction(for pullRequest: PullRequestSummary) -> SnoozeAction {
        let pr = pullRequest.id
        return SnoozeAction(
            offers: Policy.canSnooze(ownership(of: pullRequest)) ? snoozeOffers : [],
            // **Strong `self`, ne `[weak self]`.** Cyklus tu není — store uzávěr nikam neukládá,
            // drží ho jen strom view, který store stejně vlastní. Slabá reference by z toho
            // udělala tlačítko, které po zániku storu potichu nedělá nic, tedy zrovna ten stav,
            // kvůli kterému se v #333 přestala kreslit němá `Prompt →`.
            snooze: { condition in
                Task { await self.snooze(pr, condition) }
            }
        )
    }

    /// Všechna odložená cizí PR — obsah bloku `Odložené` **na desce** a číslo ve větě pod
    /// pozdravem (#512, oprava po proklikání).
    ///
    /// **Nad `pullRequests`, tedy před filtrem**, protože na tomtéž vstupu stojí `boardEntries`:
    /// deska odpovídá na „co udělám teď“, ne na „co mám zrovna odškrtnuté“. Kdyby se počítalo ze
    /// zúženého seznamu, hlásila by věta pod pozdravem jiné číslo, než kolik deska schovala — což
    /// je zrovna to rozejití, kvůli kterému `snoozedQueuePullRequests` stojí nad **týmž** vstupem
    /// jako fronta.
    var snoozedPullRequests: [PullRequestSummary] {
        Policy.snoozedPullRequests(
            in: Policy.pullRequests(pullRequests, ownedBy: .theirs, mine: ownLogins),
            isSnoozed: isSnoozed(_:)
        )
    }

    /// Odložené PR z fronty — obsah bloku `Odložené` pod seznamem (#512).
    ///
    /// **Zúžení nad `visiblePullRequests`, tedy po filtru.** Blok leží pod frontou a mluví o tom,
    /// co se z ní schovalo; kdyby se skládal z plného seznamu, ukázal by nad zafiltrovanou frontou
    /// PR z repa, které je zrovna odškrtnuté — tedy řádek, který by ve frontě nebyl vidět, ani
    /// kdyby odložený nebyl.
    var snoozedQueuePullRequests: [PullRequestSummary] {
        Policy.snoozedPullRequests(
            in: Policy.pullRequests(visiblePullRequests, ownedBy: .theirs, mine: ownLogins),
            isSnoozed: isSnoozed(_:)
        )
    }

    /// Kolik odložených schoval **filtr** — do nadpisu bloku pod frontou (oprava po proklikání).
    ///
    /// Zrcadlí `hiddenQueuePullRequestCount`: je to rozdíl obou množin, ne třetí zdroj pravdy.
    /// Bez něj by `do fronty →` z desky (kde se počítá **před** filtrem) vedlo na menší číslo
    /// a nic by ten rozdíl nevysvětlilo.
    var hiddenSnoozedPullRequestCount: Int {
        snoozedPullRequests.count - snoozedQueuePullRequests.count
    }

    /// `vrátí se zítra 9:00` u řádku v bloku `Odložené`. `nil` = odložený není.
    func snoozeNote(for pr: PRIdentifier) -> String? {
        snoozes[pr].map { Policy.snoozeNote($0, now: time.now) }
    }

    /// Co nabídnout v `Odložit` — počítá se z **hodin storu**, ne z `Date.now` v kresbě.
    var snoozeOffers: [SnoozeOffer] { Policy.snoozeOffers(now: time.now) }

    // MARK: - Odložit a vrátit

    /// Odloží PR. **Jediná cesta, kterou odložení vzniká.**
    ///
    /// Otevřenou záložku to **nezavírá**, a je to rozhodnutí: odložení mluví o frontě, kdežto
    /// otevřená záložka je rozdělaná práce (a od #531 se počítá do `pullRequestsInPlay`, takže ji
    /// úklid po tiku nezahodí). Zavřít ji by znamenalo, že „schovat na později“ zahodí i to, co
    /// mám rozečtené na obrazovce.
    ///
    /// **Běžící review se neruší.** Odložení je o pozornosti, ne o penězích — session je utracená
    /// v okamžiku, kdy začne (viz `AutoRunLedger.take`), takže zabít ji uprostřed znamená zaplatit
    /// a nic nedostat. Co odložení opravdu vypne, je **další** běh (`Policy.automaticallyReviewable`
    /// odložený PR nevydá).
    func snooze(_ pr: PRIdentifier, _ condition: SnoozeCondition) async {
        guard canSnooze(pr) else { return }
        let snooze = Snooze(pullRequest: pr, condition: condition, since: time.now)
        // **Do paměti hned, na disk potom** — jako u razítek předání: obrazovka má zareagovat na
        // kliknutí, ne na dopsaný soubor.
        snoozes[pr] = snooze
        // Razítko rozhlídky se zahazuje schválně: nové odložení potřebuje **základ**, od kterého
        // se měří, a ten dodá první rozhlídka (`Policy.snoozeBaseline`). Se zděděným razítkem po
        // dřívějším odložení téhož PR by se rozhlídka na tenhle PR nezeptala, dokud by se
        // `updatedAt` nepohnul.
        snoozeProbes[pr] = nil
        await snoozeStore?.record(snooze)
    }

    /// `Vrátit teď` — ruční návrat z odložení.
    ///
    /// Zapíše řádek do `Dění` stejně jako návrat po splněné podmínce, jen s jiným důvodem: PR se
    /// ve frontě objeví tak jako tak a **odnikud se objevit nesmí**.
    func wake(_ pr: PRIdentifier) async {
        guard snoozes.removeValue(forKey: pr) != nil else { return }
        snoozeProbes[pr] = nil
        await snoozeStore?.forget(pr)
        await recordActivity(Policy.snoozeReturnActivity(
            for: pr,
            ownership: ownership(of: pr),
            reason: .manual,
            at: time.now
        ))
    }

    // MARK: - Rozhlídka po tiku

    /// Vrátí, co se z odložení má vrátit — a doplní měřidla u zbytku (#512).
    ///
    /// Běží **uvnitř `afterSuccessfulTick`**, a to je celý mechanismus, jak dědí backoff: při rate
    /// limitu `PollingService` čeká a netiká, takže se ani nekouká. Vlastní časovač by tu ochranu
    /// obešel — tatáž úvaha jako u rozhlídky po cizí aktivitě (#335) a po hlavách (#420).
    ///
    /// **Před `startAutomaticReviews(for:)`**, ne za ním: odložení, které v tomhle tiku skončilo,
    /// má být vidět hned, včetně toho, že se na ně smí pustit automat. Opačné pořadí by znamenalo
    /// tik zpoždění u každého návratu.
    ///
    /// **Čas se vyhodnotí i bez dotazu na GitHub**, a je to podstatné: PR odložený `do zítra 9:00`
    /// se musí vrátit i tehdy, když se na něm od té chvíle nic nestalo — tedy když ho žádná
    /// rozhlídka nemá proč zahrnout do dotazu.
    func refreshSnoozes(in summaries: [PullRequestSummary]) async {
        guard !snoozes.isEmpty else { return }
        let signals = await snoozeSignals(in: summaries)

        var returned: [PRIdentifier] = []
        var baselines: [Snooze] = []
        var events: [ActivityEvent?] = []
        let now = time.now

        for summary in summaries {
            guard let snooze = snoozes[summary.id] else { continue }
            let signal = signals[summary.id]
            if Policy.snoozeExpired(snooze, head: signal?.head, comments: signal?.comments, now: now) {
                returned.append(summary.id)
                events.append(Policy.snoozeReturnActivity(
                    for: summary.id,
                    ownership: ownership(of: summary),
                    reason: Policy.snoozeReturn(of: snooze.condition),
                    at: now
                ))
                continue
            }
            // Základ se doplňuje **jen u odložení, které trvá dál**: u vráceného by se zapisoval
            // do záznamu, který se o řádek níž maže.
            if let updated = Policy.snoozeBaseline(snooze, head: signal?.head, comments: signal?.comments) {
                baselines.append(updated)
            }
        }

        // **Nejdřív paměť, pak disk, a obojí jedním zápisem** — `SnoozeStore` sahá na soubor,
        // takže zápis v cyklu by ho u tří návratů uložil třikrát.
        for pr in returned { snoozes[pr] = nil; snoozeProbes[pr] = nil }
        for snooze in baselines { snoozes[snooze.pullRequest] = snooze }
        await snoozeStore?.forget(returned)
        await snoozeStore?.update(baselines)
        await recordActivity(events)
    }

    /// Co se na odložených PR změřilo. Prázdno = nikoho se ptát nemuselo, nebo dotaz nedorazil.
    ///
    /// **Razítko dostane jedině PR, na které se doopravdy ptalo a odpověď dorazila**: chybějící
    /// alias znamená „nevíme“, a to se nesmí zapsat jako „zjištěno“ — jinak by se na to PR
    /// nezeptalo, dokud se `updatedAt` nepohne, a odložení `do dalšího pushe` by nemělo od čeho
    /// měřit.
    ///
    /// **Selhání dotazu se do okna nehlásí**, jako u rozhlídky po hlavách: nic v okně netvrdí, že
    /// se na odložené PR aplikace zrovna ptala, a stav GitHubu drží stavový řádek z pollingu.
    /// Jediný následek je návrat o tik později.
    private func snoozeSignals(in summaries: [PullRequestSummary]) async -> [PRIdentifier: SnoozeSignal] {
        let candidates = Policy.snoozeProbe(
            of: summaries,
            snoozed: { self.snoozes[$0] },
            probedAt: { self.snoozeProbes[$0] }
        )
        guard !candidates.isEmpty else { return [:] }
        guard let signals = try? await gateway.fetchSnoozeSignals(of: candidates) else { return [:] }

        let updates = Dictionary(summaries.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })
        for pr in candidates where signals[pr] != nil {
            snoozeProbes[pr] = updates[pr]
        }
        return signals
    }
}
