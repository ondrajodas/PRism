import Foundation

/// Brief na domově (#516) — **šestá session** a druhá, která nemá jediný nástroj.
///
/// **Čte stav aplikace, ne kód.** Materiál skládá `Policy.briefInput` z toho, co store doopravdy
/// má (pruhy desky, počet odložených, blok `Dění`); session ho jenom přeformuluje do tří
/// pojmenovaných vět.
/// Rozhodovací logika do promptu nepatří — kdyby o tom, co je na tahu, rozhodoval model, byl by to
/// druhý zdroj pravdy o desce, jen dražší a pokaždé jiný.
///
/// **Tři brány, každá jinde:**
///
/// 1. `GlobalConfig.brief` — výchozí `off`, a `firstTickOfDay` je jediné, co pouští session **bez
///    kliknutí**;
/// 2. `Policy.brief(mode:…)` — nenačtená fronta, běžící session a už shrnutý dnešek;
/// 3. **zavírání aplikace** — session, která ji přežije, je zrovna to, co se zavíráním zastavuje.
///
/// **Denní rozpočet (`autoRunsPerDay`) se tu nečerpá, a je to rozhodnutí.** Ten limit je pojistka
/// proti řadě **patnáctiminutových** review a agentů; brief je jeden odstavec bez nástrojů, nejvýš
/// jednou za den, takže by v tom limitu ukrojil místo běhu, na kterém záleží víc. Co brief stál, je
/// vidět na jeho řádku i v `Dneska stálo` — účet tedy nikde nemlčí.
extension AppStore {
    /// Přečte poslední brief z disku. Volá se jednou při startu.
    ///
    /// **Nepřepisuje běžící brief.** Start je jediné místo, odkud se tohle volá, ale kdyby se to
    /// změnilo, přepsalo by se `running` textem z minulého týdne — a to je tvrzení, které neplatí.
    func loadStoredBrief() async {
        guard let briefStore, !briefState.isRunning else { return }
        guard let stored = await briefStore.load() else { return }
        briefState = .ready(stored)
    }

    /// Tlačítko `Shrň` / `Shrň znovu` / `Zkusit znovu` v bloku na desce.
    func writeBrief() {
        start(trigger: .button)
    }

    /// Automat — **jediná cesta, kterou se brief pustí bez kliknutí**, a jen v režimu
    /// `firstTickOfDay`. Volá se z úspěšného tiku pollingu.
    ///
    /// `async` schválně, i když se uvnitř nečeká: volá se ze stejného místa jako ostatní rozhlídky
    /// po tiku a signatura má vypadat stejně. **Na běh se nečeká** — patnáct vteřin až dvě minuty
    /// uvnitř `afterSuccessfulTick` by zdržely úklid cache i hlášení o zbytku fronty.
    func writeBriefIfDue() async {
        start(trigger: .tick)
    }

    /// Jedno spuštění. **Jedno místo pro obě cesty**, aby se tlačítko a automat nemohly rozejít
    /// v tom, co se do briefu dostane.
    private func start(trigger: Policy.BriefTrigger) {
        guard let briefWriter else { return }
        // Zavírá se aplikace (#264): pouštět session, která ji přežije, je zrovna to, co se tím
        // zavíráním zastavuje.
        guard !isTerminating else { return }
        let decision = Policy.brief(
            mode: configuration.global.brief,
            state: briefState,
            last: briefState.brief,
            isLoaded: lastSuccess != nil,
            now: time.now,
            trigger: trigger
        )
        guard decision == .start else { return }

        // **Materiál se skládá teď, ne v tasku.** Deska je v paměti store a o tik později by to
        // byl jiný stav — brief by pak mluvil o něčem jiném, než co bylo na obrazovce ve chvíli,
        // kdy jsem na tlačítko klikl.
        let input = Policy.briefInput(board: board, snoozed: snoozedPullRequests.count, now: time.now)
        briefState = .running
        briefTask = Task { [weak self] in
            await self?.run(BriefRequest(input: input), with: briefWriter)
            self?.briefTask = nil
        }
    }

    /// Běh a jeho výsledek.
    ///
    /// **Cena jde do `SpendLedger` vždycky, i když text nedorazil** (`recordSpend`): zabitá session
    /// peníze stála taky, a útrata, která se ztratí právě u nepovedeného běhu, je o účtu lež.
    private func run(_ request: BriefRequest, with writer: any BriefWriting) async {
        let answer: BriefAnswer
        do {
            answer = try await writer.write(request)
        } catch is CancellationError {
            // Zrušení (zavírání aplikace) není porucha briefu — stav se vrátí tam, kde byl, a nic
            // se neukládá. Poslední hotový brief se přitom **nesmí ztratit**, proto se čte z disku.
            let stored: Brief? = if let briefStore { await briefStore.load() } else { nil }
            briefState = stored.map(BriefState.ready) ?? .never
            return
        } catch {
            // **Jiná chyba než zrušení se hlásí, nespolkne.** Protokol slibuje, že selhání session
            // přijde v `BriefAnswer`, ale kdyby přesto vyletělo ven, prázdný blok by vypadal jako
            // vypnutý brief — a to je zrovna ten stav, kvůli kterému má selhání vlastní větu.
            briefState = .failed(reason: "Shrnutí se nepovedlo spustit. \(error.localizedDescription)")
            return
        }
        await recordSpend(answer.usage)

        // **Selhání přebíjí text.** Napůl dopsaná věta u vytimeoutované session je horší než hláška
        // o tom, že se to nepovedlo — brief je pár vět, ne rozdělaná práce v souborech.
        if let failure = answer.failure {
            briefState = .failed(reason: failure)
            return
        }
        guard let lines = answer.lines else {
            briefState = .failed(reason: "Session nevrátila žádný text.")
            return
        }
        let brief = Brief(lines: lines, writtenAt: time.now, cost: answer.usage?.cost)
        briefState = .ready(brief)
        // **Na disk až po úspěchu.** Uložený neúspěch by po restartu vypadal jako brief, a hlavně
        // by automatu tvrdil, že je dnešek shrnutý.
        await briefStore?.save(brief)
    }
}
