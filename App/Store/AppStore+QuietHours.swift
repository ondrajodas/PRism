import Foundation

/// Tiché hodiny (#519) — velké PR pustí automat v noci, ne ve tři odpoledne.
///
/// **Odklad je vlastnost automatu, ne pull requestu.** Ruční `Spustit review` ho nezná: za tím
/// vždycky někdo stojí, a nechat člověka koukat na hlášku „poběží ve 22:00“ vedle otevřeného diffu
/// je zrovna to, čemu se tímhle vyhýbáme. Rozhoduje o tom brána v `AppStore.review` —
/// `automaticReviews.contains(pr)`, tedy tatáž, jaká rozhoduje o denním rozpočtu.
///
/// **Odklad není obejití limitu.** Denní limit běhů (`AutoRunLedger`) i strop útraty se strhávají
/// až v `canSpendSession`, tedy v okamžiku, kdy se session doopravdy utrácí — a to platí v noci
/// stejně jako ve dne. Odklad mění **kdy**, ne **kolik**.
extension AppStore {
    // MARK: - Načtení a dotazy

    /// Odložené běhy z disku. Čte se **jednou při startu a před prvním tikem** — tik, který
    /// proběhne dřív, by velké PR poslal do automatu a zaplatil `gh pr view` za rozhodnutí, které
    /// je na disku hotové.
    func loadDeferredRuns() async {
        guard let deferredRuns else { return }
        deferrals = await deferredRuns.load()
    }

    /// Odložený běh toho PR. `nil` = odložený není.
    ///
    /// **Jediné místo, kterého se ptá tab `Průběh` i plánovač automatu.** Druhá odpověď na tuhle
    /// otázku by znamenala dráhu, která slibuje noc, zatímco review běží.
    func deferral(of pr: PRIdentifier) -> DeferredRun? { deferrals[pr] }

    /// Je PR otevřený v záložce? Takový se **neodkládá** — člověk na něj čeká (#519).
    ///
    /// **Záložka, ne vybraný řádek.** Vybraný řádek se mění šipkami při projíždění fronty, takže
    /// by o odkladu rozhodovalo přejetí kurzorem. Záložka je proti tomu tah: otevřel jsem to,
    /// protože se na to chci dívat.
    ///
    /// **Platí to na rozhodnutí, ne na vyzvednutí**: otevření záložky nad PR, který už odložený
    /// je, běh nespustí — od toho je `Pustit teď`. Viz `Policy.deferralsToRelease`.
    func isOpenInTab(_ pr: PRIdentifier) -> Bool { openTabs.contains(pr) }

    // MARK: - Odložení a jeho zrušení

    /// Odloží běh do tichých hodin, nebo `nil`, když se nemá odkládat (#519).
    ///
    /// **Rozhoduje `Policy`, tady se jen dodá stav okna a hodiny.** Vrací `nil` i tehdy, když běh
    /// není automatický nebo když se odklad právě vyzvedl (`honoring == false`) — obojí je věta
    /// o tom, kdo si o běh řekl, ne o pravidlech.
    func quietHoursDeferral(
        for pr: PRIdentifier,
        of detail: PullRequest,
        honoring: Bool
    ) -> QuietHoursDeferral? {
        guard honoring, automaticReviews.contains(pr) else { return nil }
        return Policy.deferToQuietHours(
            pr: detail,
            isOpen: isOpenInTab(pr),
            now: time.now,
            rules: configuration.global.quietHours
        )
    }

    /// Zapíše odklad — do paměti i na disk (#519).
    ///
    /// **Na disk, protože noc bez běžící aplikace by jinak nepustila nic.** Restart je v tomhle repu
    /// běžná věc (po každém mergi), takže slib, který žije jen v paměti, není slib.
    func deferRun(of pr: PRIdentifier, at detail: PullRequest, _ decision: QuietHoursDeferral) async {
        // **Počet řádků i práh jdou z rozhodnutí, ne z detailu a z nastavení znovu.** Dobrat si je
        // podruhé by u počtu řádků znamenalo `?? 0` — tedy větu `0 řádků nad prahem 1 500` v okně,
        // kdyby se ta nedosažitelná větev jednou dosažitelnou stala.
        let run = DeferredRun(
            pullRequest: pr,
            headSha: detail.headSha,
            changedLines: decision.changedLines,
            threshold: decision.threshold,
            deferredAt: time.now,
            runAt: decision.runAt
        )
        deferrals[pr] = run
        await deferredRuns?.record(run)
    }

    /// Zruší odklad. Idempotentní a **volá se z každé cesty, která běh doopravdy pustí** — jinak by
    /// v cache zůstal slib na běh, který právě probíhá.
    func forgetDeferral(of pr: PRIdentifier) async {
        guard deferrals.removeValue(forKey: pr) != nil else { return }
        await deferredRuns?.forget(pr)
    }

    /// `Pustit teď` z dráhy v tabu `Průběh` (#519).
    ///
    /// **Ruční běh, ne vyzvednutý odklad**, a je to rozdíl, který je vidět na účtu: `startReview`
    /// PR z `automaticReviews` vyhodí, takže si nesáhne o denní rozpočet. Za tímhle stojí člověk,
    /// jako za každým jiným `Spustit review`.
    ///
    /// **Celé review, ne jeden reviewer.** Odklad padl na celý běh, takže ho celý ruší — na rozdíl
    /// od `Pustit přesto` u routingu (#518), kde je rozhodnutí opravdu o jednom revieweerovi.
    func runDeferredNow(_ pr: PRIdentifier) async {
        await forgetDeferral(of: pr)
        startReview(for: pr)
    }

    // MARK: - Vyzvednutí po tiku

    /// Pustí odložené běhy, kterým došel čas (#519).
    ///
    /// Volá se **po úspěšném tiku a před plánovačem**, jako rozhlídka po odložených PR: běh,
    /// kterému právě došel čas, se má pustit teď, ne za tik.
    ///
    /// **Otevřená záložka odsud běh nepouští** — otevřený PR se jen neodkládá (`deferToQuietHours`).
    /// Proč, je u `Policy.deferralsToRelease`: jinak by se dráha `odloženo na noc` nedala vidět,
    /// protože se kreslí jedině v otevřené záložce.
    ///
    /// **Pouští se jako automatický běh**, tedy s rozpočtem: byl to automat, kdo si o něj řekl.
    /// A **bez ohledu na tiché hodiny** (`honoringQuietHours: false`) — jinak by běh, jehož noc
    /// aplikace prospala, ráno spadl rovnou do dalšího odkladu a slib by se nesplnil nikdy.
    ///
    /// **Odklad se ruší až v `review`**, ne tady: mezi vyzvednutím a dotažením detailu se toho
    /// stane málo, ale kdyby se zápis smazal a běh se pak nerozjel (zavírá se aplikace), zůstal
    /// by PR bez slibu i bez běhu.
    func releaseDeferredRuns(for summaries: [PullRequestSummary]) {
        guard !isTerminating, reviewer != nil else { return }
        // **Bez odložených PR a jen cizí** (#512, #332) — tatáž dvojice zúžení jako v plánovači
        // o kus dál. Bez toho by odložení pull requestu („tenhle teď vidět nechci“) přišlo o svou
        // hlavní vlastnost u zrovna toho PR, které mezitím dostalo odklad do noci: v deset večer
        // by se na něj pustilo review, o které si nikdo neřekl.
        let queue = Policy.pullRequests(
            Policy.pullRequests(summaries, ownedBy: .theirs, mine: ownLogins),
            withoutSnoozed: isSnoozed(_:)
        )
        let due = Policy.deferralsToRelease(
            in: queue,
            deferred: { self.deferrals[$0] },
            now: time.now
        )
        for pr in due where reviewTasks[pr] == nil {
            automaticReviews.insert(pr)
            reviewTasks[pr] = RunningReview(
                task: Task { [weak self] in await self?.review(pr, honoringQuietHours: false) },
                skills: nil
            )
        }
    }
}
