import Foundation

/// Spuštění a průběh review — session, osa, uložení výsledku.
///
/// Nejdelší z těch extensionů, a schválně jeden: běh review je jedna cesta od `startReview`
/// přes `runSkills` a `drain` po `finish`, a rozříznout ji uprostřed znamená hledat,
/// kde pokračuje.
extension AppStore {
    /// Spustí review vybraného PR. Opakované zmáčknutí, dokud běží, nic nedělá.
    ///
    /// `skills` je podmnožina k opakování (#149) — typicky jeden reviewer, který spadl.
    /// `nil` znamená celou nastavenou sadu, a to **není totéž jako její snímek**: sadu ještě
    /// může změnit odhad jazyka repa, který běží až nad pracovní kopií.
    func startReview(for pr: PRIdentifier, skills: [String]? = nil) {
        guard reviewer != nil, reviewTasks[pr] == nil else { return }
        // Prázdná podmnožina by spustila review bez jediného revieweera — tedy běh, který
        // utratí checkout a nic nezjistí.
        guard skills.map({ !$0.isEmpty }) ?? true else { return }
        // Ruční spuštění přebíjí automat: kdyby PR mezitím spustil automat, nespustí se
        // podruhé (`reviewTasks` už není `nil`), ale zůstal by označený jako automatický
        // a zmizení ze seznamu by ho zrušilo pod rukama.
        automaticReviews.remove(pr)
        reviewTasks[pr] = RunningReview(
            task: Task { [weak self] in await self?.review(pr, skills: skills) },
            skills: skills
        )
    }

    /// PR ve frontě, na kterých se ještě nic nespustilo (#181).
    ///
    /// Bere **plný** seznam, ne zúžený filtrem: „co neběželo“ je tvrzení o frontě, ne o tom,
    /// co je zrovna vidět — tatáž úvaha jako u dashboardu.
    var pullRequestsNotReviewed: [PRIdentifier] {
        pullRequests.map(\.id).filter { reviewState(for: $0) == .notStarted && reviewTasks[$0] == nil }
    }

    /// Pustí review na všem, na čem ještě neběželo (#181).
    ///
    /// Limit souběhu hlídá `ReviewRunner`, takže tohle jen naplní frontu — session se spustí
    /// po tolika, kolik je nastaveno, a zbytek čeká ve stavu `queued`.
    ///
    /// **Stojí to peníze za každý PR**, proto se na to v dashboardu ptá potvrzení: je to jediná
    /// akce v aplikaci, která z jednoho kliknutí utratí víc než jednu session.
    func startReviewsForNotReviewed() {
        for pullRequest in pullRequestsNotReviewed { startReview(for: pullRequest) }
    }

    /// Zrušení uživatelem. Session dostane `SIGKILL`, rozdělané výsledky se zahodí.
    func cancelReview(for pr: PRIdentifier) {
        reviewTasks[pr]?.task.cancel()
    }

    /// Sada skillů pro repo. Chipy z ní berou pořadí i to, co ještě neběželo.
    func reviewSkills(for repo: RepoID) -> [String] { resolved(for: repo).skills }

    /// Reviewery, kteří na PR **právě běží**.
    ///
    /// Odvozeno, ne vedeno zvlášť: běh, který ještě nestihl poslat první událost, osu
    /// nemá — a přesto běží. Proto se počítá jako „všechno, co nedoběhlo“.
    func runningReviewers(for pr: PRIdentifier) -> Set<String> {
        guard isReviewing(pr) else { return [] }
        let finished = Set(timelines(for: pr).filter(\.isFinished).map(\.skill))
        // Jen ty, které tenhle běh pouští (#149). Celá sada by u opakování jednoho revieweera
        // označila za běžící i ty ostatní — a jejich chipy by přestaly ukazovat výsledek,
        // který mají uložený.
        return Set(runningSkills(for: pr)).subtracting(finished)
    }

    /// Časová osa běhů posledního review. Prázdná, dokud se nic nespustilo.
    func timelines(for pr: PRIdentifier) -> [ReviewerTimeline] {
        // Živá osa má přednost (#203): běžící review si ji drží v paměti a uložená patří
        // předchozímu běhu — přebít ji tou z disku by ukázalo starý průběh nad novým během.
        //
        // Rozhoduje **existence klíče, ne to, jestli je pole prázdné**. Nový běh si osu nuluje
        // ještě před prvním eventem, takže by se v tom okně sáhlo na disk a nad rozjetým během
        // by probliknul průběh toho předchozího — přesně to, čemu se tohle pravidlo vyhýbá.
        // Cena: běh zrušený dřív, než cokoli dorazilo, nechá tab prázdný až do restartu. To je
        // ale pravda o tomhle PR — poslední, co se s ním dělo, opravdu žádnou osu nemá.
        if let live = reviewTimelines[pr] { return live }
        return Policy.timelines(of: reviewRecords[pr])
    }

    func review(_ pr: PRIdentifier, skills subset: [String]? = nil) async {
        defer {
            reviewTasks[pr] = nil
            automaticReviews.remove(pr)
        }
        guard let reviewer, let checkout, let reviews else { return }

        // Nový běh začíná s čistou osou — míchat dohromady, co dělaly dva různé běhy, by
        // z časové osy udělalo nesmysl.
        //
        // U opakování jednoho revieweera (#149) se maže **jen jeho** osa: ostatní neběží,
        // takže by po nich zbylo prázdno a průběh, kvůli kterému se do tabu chodí, by zmizel
        // za cizí běh.
        reviewTimelines[pr] = subset.map { skills in
            timelines(for: pr).filter { !skills.contains($0.skill) }
        } ?? []
        reviewPhases[pr] = .preparing
        do {
            // SHA umí dát jen detail — vyhledávání ho nevrací (viz rozhodnutí u #4).
            let detail = try await gateway.fetchDetail(id: pr)
            try await reviews.markCurrent(detail.headSha, of: pr)
            markStaleInMemory(for: pr, current: detail.headSha)

            // Tady se rozhoduje, jestli se utratí session. Výběr po tiku jede podle
            // `updatedAt`, které se mění i po komentáři — teprve `headSha` řekne, jestli
            // se kód opravdu změnil. Ruční spuštění se **nezastavuje**: když si o něj
            // někdo řekl podruhé, chce to pustit znovu.
            // Nemá cenu klonovat kvůli commitu, který je zreviewovaný. Rozpočet se tu ale
            // **nestrhává** — session utrácí až `runSkills` a mezi tím může selhat checkout.
            if automaticReviews.contains(pr), hasCurrentReview(of: pr, at: detail.headSha) {
                reviewPhases[pr] = nil
                return
            }

            checkoutStates[pr.repo] = .preparing
            let worktree = try await checkout.worktree(for: pr, at: detail.headSha)
            await syncCheckoutState(for: pr.repo, using: checkout)
            try Task.checkCancellation()

            // Musí to být **před** `runSkills`, ne po: sada, kterou detekce zapíše, je
            // ta, se kterou má tenhle běh jet.
            await adoptDetectedSkills(for: pr.repo, in: worktree, using: checkout)
            // Odhad jazyka zrušení **spolkne** — nepovedený výpis se od zrušeného nepozná
            // a obojí tam znamená „sadu neodvodíme“. Zrušené review by pak jelo dál, takže
            // se to musí zeptat znovu tady.
            try Task.checkCancellation()

            // Rozpočet **až tady**: `runSkills` je jediné místo, které session utrácí.
            // Cokoli dřív znamená platit i za běhy, které se nikdy nerozjely — selhal
            // checkout, nebo repo nemá nastavený žádný skill. Ráno to spálilo šest z dvaceti
            // za jedno dopoledne, když se to strhávalo v plánovači, a znovu, když se to
            // strhávalo před checkoutem.
            guard await canSpendSession(on: pr) else { return }

            try await runSkills(
                for: pr,
                of: detail,
                in: worktree,
                using: reviewer,
                saving: reviews,
                only: subset
            )
            reviewPhases[pr] = nil
            await notifyAboutFinishedReview(of: pr)
        } catch is CancellationError {
            // Zrušení není selhání — stav se srovná podle disku, ne do chyby.
            //
            // A **neoznamuje se**: zrušil si ho člověk, takže o něm ví. Notifikace o tom, co
            // jsem právě sám zastavil, je čisté vyrušení za nic.
            reviewPhases[pr] = nil
            await syncCheckoutState(for: pr.repo, using: checkout)
        } catch let error as CheckoutError {
            // Chyba pracovní kopie je stav **repa**, ne tohohle PR: druhé PR téhož repa na
            // ni narazí taky a řeší se stejným tlačítkem.
            reviewPhases[pr] = nil
            checkoutStates[pr.repo] = .failed(error.userDescription)
            await notifyAboutFinishedReview(of: pr)
        } catch let error as GitHubError {
            reviewPhases[pr] = .failed(detail: error.userDescription)
            await notifyAboutFinishedReview(of: pr)
        } catch {
            reviewPhases[pr] = .failed(detail: error.localizedDescription)
            await notifyAboutFinishedReview(of: pr)
        }
    }

    /// Odvodí sadu skillů z toho, co v repu leží.
    ///
    /// Běží při **každém** review, dokud si repo o skilly neřeklo (`skills == nil`) — ne
    /// jen při prvním. Je to schválně: mapa jazyků se dá vyplnit až potom, co se repo
    /// jednou zreviewovalo, a bez opakování by se projevila teprve na dalším repu.
    /// Stojí to jedno lokální `git ls-files` navíc.
    ///
    /// Ruční hodnota má přednost a **i prázdná** („tady nereviewuj nic“) detekci
    /// navždycky umlčí — přepsat ji by znamenalo vracet uživateli jeho rozhodnutí zpátky.
    ///
    /// Zapisuje se jen to, co se od globální sady liší. Zápis „stejné jako globální“ by byl
    /// override, o který nikdo nežádal — a pozdější změna globální sady by tenhle repo
    /// tiše minula.
    private func adoptDetectedSkills(for repo: RepoID, in worktree: URL, using checkout: any RepoCheckout) async {
        guard configuration.repositories[repo]?.skills == nil else { return }

        let files: [String]
        do {
            files = try await checkout.trackedFiles(in: worktree)
        } catch {
            // Nepovedený výpis znamená, že se sada neodvodí a poběží globální — tedy přesně
            // to, co běželo před #24. Nic se neztrácí a příští review to zkusí znovu,
            // protože `skills` zůstává `nil`. Položit kvůli tomu celé review by bylo dražší
            // než ta ztráta.
            return
        }

        let detected = configuration.defaultSkills(for: Policy.projectLanguages(in: files))
        guard detected != resolved(for: repo).skills else { return }

        var entry = configuration.repositories[repo] ?? RepositoryConfig()
        entry.skills = detected
        var updated = configuration
        updated.setRepository(entry, for: repo)

        do {
            try await updateConfiguration(updated)
        } catch {
            // Review poběží dál, jen s globální sadou — `resolved(for:)` čte to, co je
            // v paměti, a tam se nic nezměnilo. Mlčet o tom ale nejde: nastavení, které
            // se neuložilo, je přesně to, kvůli čemu se pak hledá, proč něco nefunguje.
            configurationFailure = "Rozpoznanou sadu skillů se nepodařilo uložit. \(error.localizedDescription)"
        }
    }

    /// Reviewery běží paralelně; limit souběhu hlídá `ReviewRunner`, ne tenhle kód.
    ///
    /// Ukládá se po **každém** doběhlém skillu, ne až na konci: když se aplikace zavře
    /// uprostřed, co doběhlo, zůstane.
    private func runSkills(
        for pr: PRIdentifier,
        of detail: PullRequest,
        in worktree: URL,
        using reviewer: any ReviewRunning,
        saving reviews: ReviewStore,
        only subset: [String]? = nil
    ) async throws {
        // Sada se čte **až tady**, po odhadu jazyka repa — proto se podmnožina předává jako
        // parametr a ne jako snímek pořízený při spuštění.
        let skills = subset ?? reviewSkills(for: pr.repo)
        reviewPhases[pr] = .running(finished: 0, total: skills.count)

        // Průběh teče přes proud, ne přímo do store: hlásí se ze session, která běží mimo
        // hlavní vlákno, a **pořadí událostí je to hlavní, co časová osa říká**. Proud ho
        // drží; hop do vlastního tasku na každou událost by o pořadí nechal rozhodovat
        // plánovač.
        let (events, reporter) = AsyncStream<ReviewEvent>.makeStream()
        async let drained: Void = drain(events, for: pr, at: detail.headSha, in: worktree)
        let failure = await runSkills(
            for: pr,
            of: detail,
            in: worktree,
            using: reviewer,
            saving: reviews,
            skills: skills,
            reporting: reporter
        )
        reporter.finish()
        await drained

        // Značky se mažou **až po vyprázdnění proudu** (#97). Zápis značky jde přes něj, kdežto
        // uložení výsledku ne — takže by se smazání umělo předběhnout a značka by zůstala ležet
        // nad hotovým během. Chytil to test, ne úvaha.
        //
        // Maže se **celá sada, ne jen uložené běhy**: sem se dojde jedině tehdy, když review
        // skončilo, takže značka po něm už nemá co znamenat. Pokrývá to i **zrušený** běh,
        // který se schválně neukládá — nechat mu značku by znamenalo, že příští start dotáhne
        // z transcriptu nálezy, které si člověk zrušil, tedy proti pravidlu „zrušení neuloží
        // nic“. Po pádu se sem naopak nedojde vůbec, a o to jde.
        // Maže se jen za **spuštěné** reviewery (#149): značka po skillu, který tenhle běh
        // nepouštěl, pořád platí — a smazat ji znamená přijít o nálezy, které po něm zbyly
        // v transcriptu.
        for skill in skills {
            await interrupted?.forget(
                ReviewRunKey(pullRequest: pr, headSha: detail.headSha, skillID: skill)
            )
        }

        if let failure { throw failure }
    }

    /// Zapisuje průběh v pořadí, ve kterém dorazil.
    private func drain(
        _ events: AsyncStream<ReviewEvent>,
        for pr: PRIdentifier,
        at headSha: String,
        in worktree: URL
    ) async {
        for await event in events {
            switch event {
            case .progress(let skill, let progress):
                // Značka se zapisuje **v proudu a s `await`**, ne ve vlastním tasku (#97).
                // Odložený zápis se umí propsat až po tom, co běh doběhl a značku smazal —
                // pak zůstane ležet nad hotovým během a příští start by ho dotahoval znovu.
                // Chytil to test, ne úvaha.
                if case .started(let sessionID) = progress {
                    await markInterrupted(sessionID, of: skill, for: pr, at: headSha, in: worktree)
                }
                record(progress, of: skill, for: pr, in: worktree)
            case .finished(let skill, let outcome, let usage):
                finish(outcome, usage: usage, of: skill, for: pr)
            }
        }
    }

    private func record(_ progress: ReviewProgress, of skill: String, for pr: PRIdentifier, in worktree: URL) {
        var timelines = reviewTimelines[pr] ?? []
        if let index = timelines.firstIndex(where: { $0.skill == skill }) {
            timelines[index].record(progress, at: time.now)
        } else {
            var timeline = ReviewerTimeline(skill: skill, worktree: worktree)
            timeline.record(progress, at: time.now)
            timelines.append(timeline)
        }
        reviewTimelines[pr] = timelines
    }

    private func finish(
        _ outcome: ReviewRunOutcome,
        usage: RunUsage?,
        of skill: String,
        for pr: PRIdentifier
    ) {
        record(outcome)
        guard var timelines = reviewTimelines[pr],
              let index = timelines.firstIndex(where: { $0.skill == skill })
        else { return }
        timelines[index].finish(outcome, usage: usage, at: time.now)
        reviewTimelines[pr] = timelines
    }

    /// Přičte, co běh stál. Jde to **proudem událostí mimo**, přímo na aktor: útrata se neváže
    /// na osu ani na uložený záznam, takže by ji zdržovalo pořadí, na kterém jí nezáleží.
    private func recordSpend(_ usage: RunUsage?) async {
        guard let spend else { return }
        dailySpend = await spend.record(usage)
        // Graf se musí posunout se stejným během, jinak by karta ukazovala novou částku nad
        // starým sloupcem.
        spendHistory = await spend.recentDays()
    }

    /// Doběhlý běh jako zdravotní signál Claude — puntík ve stavovém řádku jede na skutečném
    /// provozu, ne na sondě.
    ///
    /// **`timedOut` nezapisuje nic.** Session jsme po patnácti minutách zabili sami, takže
    /// z toho nejde vyvodit ani „funguje“, ani „nefunguje“ — a dlouhé review je běžná věc.
    /// `failed` naopak signál je, i když příčina může být na naší straně (třeba neexistující
    /// skill); věta v nápovědě proto říká, co přišlo na stderr, a to, jestli za to může
    /// Claude, se pozná ze žlutého puntíku.
    /// **Při opakovaném selhání se `since` drží.** Nese začátek výpadku, ne poslední pokus —
    /// jinak by se „Nedaří se od …“ posouvalo s každou další spadlou session a nešlo by poznat,
    /// jak dlouho to trvá. Je to tatáž úvaha (a tatáž věta v nápovědě) jako
    /// `PollingService.failingSince`; u GitHubu ji drží `PollState`, tady ji musí držet tohle.
    private func record(_ outcome: ReviewRunOutcome) {
        switch outcome {
        case .finished:
            lastReviewCall = ServiceCall(since: time.now)
        case .failed(let detail):
            let failingSince = lastReviewCall.flatMap { $0.succeeded ? nil : $0.since } ?? time.now
            lastReviewCall = ServiceCall(since: failingSince, failure: detail)
        case .timedOut, .interrupted:
            // Ani jedno není zpráva o Claude: timeout jsme způsobili my (zabili jsme session
            // po patnácti minutách) a přerušení taky (spadla aplikace). Zapsat z toho červený
            // puntík by ukazoval na cizí službu za naši vlastní nehodu.
            break
        }
    }

    private func runSkills(
        for pr: PRIdentifier,
        of detail: PullRequest,
        in worktree: URL,
        using reviewer: any ReviewRunning,
        saving reviews: ReviewStore,
        skills: [String],
        reporting reporter: AsyncStream<ReviewEvent>.Continuation
    ) async -> (any Error)? {
        await withTaskGroup(of: ReviewRun?.self) { group in
            for skill in skills {
                let request = ReviewRequest(
                    key: ReviewRunKey(pullRequest: pr, headSha: detail.headSha, skillID: skill),
                    worktree: worktree,
                    baseSha: detail.baseSha
                )
                // Protokol slibuje, že selhání session se vrací jako výsledek a vyhodí se
                // jen zrušení — ale spolehnout se na to znamená, že jakákoli jiná chyba
                // zmizí a řádek se bude tvářit, že se nic nespustilo. Radši ji přeložíme
                // na `failed`, kde je vidět.
                group.addTask {
                    do {
                        return try await reviewer.run(request) { reporter.yield(.progress(skill: skill, $0)) }
                    } catch is CancellationError {
                        return nil
                    } catch {
                        return ReviewRun(
                            key: request.key,
                            summary: StreamSummary(),
                            outcome: .failed(detail: error.localizedDescription)
                        )
                    }
                }
            }

            var finished = 0
            var saveFailure: (any Error)?
            for await run in group {
                finished += 1
                reviewPhases[pr] = .running(finished: finished, total: skills.count)
                guard let run else { continue }
                // Útrata se zapisuje **před** kontrolou zrušení: session, která doběhla,
                // peníze stála, ať už se její výsledek uloží, nebo ne. Číslo, které zrušením
                // zmizí, by o mém účtu lhalo.
                await recordSpend(run.summary.usage)
                guard !Task.isCancelled else { continue }
                reporter.yield(.finished(skill: run.key.skillID, run.outcome, usage: run.summary.usage))
                do {
                    // Ukládá se **před** překladem: ten je krátká síťová operace navíc
                    // a když se na ní aplikace zavře, nálezy už jsou na disku. V originále,
                    // ale jsou — což je přesně to, co pravidlo „co doběhlo, zůstane“ chce.
                    reviewRecords[pr] = try await reviews.save(
                        run,
                        // Osa se ukládá **s během**, ne zvlášť: je to jeho průběh, takže patří
                        // do téhož souboru a zestárne s ním (#203).
                        timeline: reviewTimelines[pr]?
                            .first { $0.skill == run.key.skillID }?
                            .stored()
                    )
                    revealFindingsOutsideTheDiff(for: pr)
                    if let translated = await translated(run, for: pr.repo) {
                        reviewRecords[pr] = try await reviews.save(translated)
                    }
                } catch {
                    // Nezapsaný nález je ztracený nález. Spolknout to by znamenalo, že
                    // řádek po doběhlém review ukazuje „neběželo“ — tedy přesně to, čemu se
                    // celý ten rozlišený stav vyhýbá. Ostatní skilly doběhnou, ať se
                    // nezahodí i to, co se uložit povedlo.
                    saveFailure = saveFailure ?? error
                }
            }
            return saveFailure
        }
    }

    /// Doplní běhu překlady nálezů. `nil` = není co ukládat znovu.
    ///
    /// Jazyk se čte **teď**, ne při startu, takže se přepnutí projeví na dalším běhu.
    /// Zpětně neplatí: uložené nálezy zůstanou v jazyce, ve kterém se uložily.
    private func translated(_ run: ReviewRun, for repo: RepoID) async -> ReviewRun? {
        guard let translator, !run.summary.findings.isEmpty else { return nil }
        // Zrušené review nemá utrácet session za překlad. Nálezy jsou v tu chvíli uložené
        // v originále, takže se nic neztrácí — jen se nepřekládá to, co si nikdo nevyžádal.
        guard !Task.isCancelled else { return nil }
        // Angličtina se nepřekládá — reviewer v ní píše sám od sebe (ověřeno na skutečných
        // bězích). Volat kvůli tomu model by byla session za nic.
        let language = resolved(for: repo).findingsLanguage
        guard language != .english else { return nil }

        // Selhání překladu review nepoloží: nálezy jsou uložené a v originále čitelné.
        // Že jsou anglicky, je vidět na první pohled — mlčení tu nic neschovává.
        guard let translations = try? await translator.translate(run.summary.findings, to: language),
              translations.contains(where: { $0 != nil })
        else { return nil }

        var translated = run
        translated.translations = translations
        return translated
    }

    /// Srovná stav pracovní kopie podle disku.
    ///
    /// Volá se po každé fázi, která ho mohla nechat v `.preparing` — a to je i zrušení.
    /// Zapomenout na to znamená řádek, který do restartu ukazuje „ve frontě · clone“.
    private func syncCheckoutState(for repo: RepoID, using checkout: any RepoCheckout) async {
        if let clone = await checkout.existingClone(for: repo) {
            checkoutStates[repo] = .ready(clone)
        } else {
            checkoutStates[repo] = .absent
        }
    }

    /// Je pro tenhle `headSha` hotové review se **všemi** nastavenými skilly?
    ///
    /// Chybějící skill znamená, že se sada mezitím rozšířila nebo že běh nedoběhl celý —
    /// a to je důvod pustit ho znovu. Zastaralý záznam se nepočítá vůbec.
    private func hasCurrentReview(of pr: PRIdentifier, at headSha: String) -> Bool {
        guard let record = reviewRecords[pr], record.headSha == headSha, !record.isStale else {
            return false
        }
        let finished = Set(record.runs.map(\.skillID))
        return Set(reviewSkills(for: pr.repo)).isSubset(of: finished)
    }

    /// Nový head commit zneplatní i to, co držíme v paměti — jinak by řádek do konce běhu
    /// ukazoval nálezy proti kódu, který v PR není.
    private func markStaleInMemory(for pr: PRIdentifier, current headSha: String) {
        guard var record = reviewRecords[pr], record.headSha != headSha else { return }
        record.isStale = true
        reviewRecords[pr] = record
    }
}
