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
        // Během zavírání už se nic nespouští (#264): session, která se rozjede po tom, co se
        // ostatní zabily, aplikaci přežije — a to je celý ten problém.
        guard !isTerminating, reviewer != nil, reviewTasks[pr] == nil else { return }
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
    /// Bere seznam **nezúžený filtrem**: „co neběželo“ je tvrzení o frontě, ne o tom, co je zrovna
    /// vidět — tatáž úvaha jako u dashboardu.
    ///
    /// **Jen cizí PR** (#332). Je to obsah akce `Pustit review na vše, co neběželo` v bloku
    /// `Co teď`, tedy hromadné spuštění nad **frontou** — a věta „Nic nečeká, fronta je vyřízená“
    /// vedle něj mluví o téže množině jako karta `Čeká na mě`. Ruční spuštění na jednom vlastním PR
    /// (tlačítko na řádku i v detailu) tím dotčené není: pravidlo se týká automatu a hromadné akce,
    /// ne toho, když si o review řeknu u konkrétního PR.
    var pullRequestsNotReviewed: [PRIdentifier] {
        queuePullRequests.map(\.id).filter { reviewState(for: $0) == .notStarted && reviewTasks[$0] == nil }
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

    /// Zabije všechna běžící review, protože se zavírá aplikace (#264).
    ///
    /// **Tou samou cestou jako zrušení** — `task.cancel()`, ze kterého se přes
    /// `continuation.onTermination` proudu dojde na `SIGKILL` v `LaunchedProcess`. Druhý `kill`
    /// v delegátovi by byl druhá pravda o tom, jak se běh zastavuje, a `SIGTERM` by tu byl
    /// vlastní volba proti té, která u zrušení už padla: `claude` se nemá komu dokončovat,
    /// protože aplikace, která na jeho výstup čekala, za chvíli nebude.
    ///
    /// **Musí se na to počkat.** Zrušení jde přes `WorkCoordinator`, který práci drží ve vlastním
    /// tasku, takže než signál odejde, proběhne několik hopů mezi aktory. Ukončit aplikaci hned
    /// po `cancel()` znamená zavřít ji dřív — a `claude` se pak přerodí na `launchd` a běží dál
    /// (změřeno u #264: dvě takové session běžely na stroji čtyři dny).
    ///
    /// **Ale ne donekonečna.** Po `terminationChecks × terminationStep` se vrací, i když něco
    /// zůstalo: ze zaseknuté session nesmí vzniknout aplikace, která se nedá zavřít.
    func stopReviewsBeforeTermination() async {
        isTerminating = true
        for review in reviewTasks.values { review.task.cancel() }
        // Kontrola nálezů (#150) je tatáž `claude` session, takže se zavírá stejně — bez toho by
        // přežila aplikaci a běžela dál na `launchd`, což je celý ten problém z #264.
        for recheck in recheckTasks.values { recheck.task.cancel() }
        // Rozhovor (#452) taky — je to `claude -p` jako každá jiná session tady.
        for ask in askTasks.values { ask.cancel() }
        // A slévání konfliktů (#467). Je to `claude -p` jako ostatní, jen navíc **píše do
        // souborů** — takže po zabité aplikaci nejen platí tokeny, ale pořád i mění pracovní strom
        // v cache. Rozdělaný rebase v něm je stav, o kterém okno mluví (`unresolved`), takže se tím
        // nic tichého nenechává.
        for sync in branchSyncTasks.values { sync.cancel() }
        // A anotace hunků (#524). Je to `claude -p` jako ostatní — bez zabití by přežila aplikaci
        // a platila tokeny dál na `launchd`, což je celý problém z #264.
        for annotation in annotationTasks.values { annotation.cancel() }
        // A brief (#516). Je to `claude -p` jako ostatní — bez nástrojů, ale se stejným účtem:
        // session, která přežije zavřenou aplikaci, platí tokeny dál.
        briefTask?.cancel()
        // A tělo návrhu review (#521). Je to `claude -p` jako ostatní — bez nástrojů, ale se
        // stejným účtem: session, která přežije zavřenou aplikaci, platí tokeny dál.
        for body in reviewBodyTasks.values { body.cancel() }

        var remaining = Self.terminationChecks
        while !reviewTasks.isEmpty || !recheckTasks.isEmpty || !askTasks.isEmpty
            || !branchSyncTasks.isEmpty || !annotationTasks.isEmpty || briefTask != nil
            || !reviewBodyTasks.isEmpty,
            remaining > 0 {
            remaining -= 1
            // `Task.sleep`, ne `time.sleep`: čeká se na skutečný proces, ne na rozvrh. Fake
            // hodiny čekání přeskočí, a test, který má tvrdit, že po zavření nic neběží, by
            // pak prošel i nad živou session.
            //
            // `try?` tu nic neschovává: uspání selže jedině zrušením a zrušit tohle čekání
            // nemá kdo (task drží delegát a zaniká s aplikací). I kdyby k tomu došlo, musí se
            // dojít až na konec — ukončení, které se nedokončí, je nezavíratelná aplikace,
            // a to je horší porucha než přežilá session.
            try? await Task.sleep(for: Self.terminationStep)
        }
    }

    /// Jak dlouho se čeká, než se běhy zastaví — 100 × 20 ms, tedy dvě sekundy.
    ///
    /// Zabití je v praxi otázka jednotek milisekund, takže se to skoro vždycky vrátí po prvním
    /// kole; strop je tu proti zaseknuté session, ne proti pomalému zabíjení. Dvě sekundy jsou
    /// tolik jako `gracePeriod` u timeoutu — stejný řád, stejný důvod.
    static let terminationChecks = 100
    static let terminationStep = Duration.milliseconds(20)

    /// Sada skillů pro repo. Chipy z ní berou pořadí i to, co ještě neběželo.
    func reviewSkills(for repo: RepoID) -> [String] { resolved(for: repo).skills }

    /// Koho routing na tomhle PR nepustil a z jakých vzorů (#518). Prázdné = nic se nepřeskočilo.
    ///
    /// Getter, ne mapa napřímo, ze stejného důvodu jako `timelines(for:)`: rozhodnutí „záznam
    /// z jiné hlavy se nepočítá“ nemá být `if` ve view. Hlavu k tomu drží `ReviewerRoutingPass`,
    /// takže se hodí i tam, kde volající hlavu nezná — kdyby ji znal, ptá se `Policy.standingSkips`.
    func skippedReviewers(for pr: PRIdentifier) -> [String: [String]] {
        routingSkips[pr]?.skipped ?? [:]
    }

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

    /// Průběh běžícího review do pruhu v hlavičce (#218). `nil` = neběží nic.
    func reviewProgress(for pr: PRIdentifier) -> ReviewRunProgress? {
        Policy.progress(
            startedAt: reviewTasks[pr]?.startedAt,
            phase: reviewPhases[pr],
            running: runningReviewers(for: pr)
        )
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

    /// - Parameter honoringQuietHours: smí se tenhle běh ještě odložit do tichých hodin (#519)?
    ///   `false` jedině u běhu, který se z odkladu právě **vyzvedl** — ten se odložit znovu nesmí,
    ///   jinak by běh, jehož noc aplikace prospala, ráno spadl do dalšího odkladu a slib
    ///   `poběží ve 22:00` by se nesplnil nikdy. Parametrem, ne polem storu: je to vlastnost
    ///   **tohohle** spuštění, a držený stav, který nikdo neuklidí, je zrovna ten vzor, co Copilot
    ///   v tomhle repu nachází.
    func review(
        _ pr: PRIdentifier,
        skills subset: [String]? = nil,
        honoringQuietHours: Bool = true
    ) async {
        defer {
            reviewTasks[pr] = nil
            automaticReviews.remove(pr)
        }
        guard let reviewer, let checkout, let reviews else { return }

        // Šablona bez zástupného textu se **nepustí** (#281). Okno neplatnou neuloží, takže
        // sem se dá dostat jedině ručně editovaným `config.json` — a tam platí, že tolerantní
        // čtení neznamená tiché: běh s promptem bez base sha by reviewer odpracoval proti
        // ničemu a v okně by z toho vyšlo „čisté review“. Osa se u toho **nemaže**: nic se
        // nespustilo, takže poslední průběh je pořád pravda o tomhle PR.
        if let problem = Policy.reviewPromptProblems(in: configuration.global.reviewPrompt).first {
            reviewPhases[pr] = .failed(detail: problem.reason)
            return
        }

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
            // Tiché hodiny (#519) — **před checkoutem, rozpočtem, zadáním i session**, tedy dřív
            // než cokoli, co něco stojí. Dotažený detail je jediné, co se za odložený běh zaplatí,
            // a bez něj to nejde: kolik řádků PR mění, vyhledávání neříká.
            //
            // Za bránou na `hasCurrentReview`, ne před ní: PR, který je zreviewovaný, se nemá co
            // odkládat — slib na běh, který se stejně nespustí, by v dráze svítil do rána.
            if let deferral = quietHoursDeferral(for: pr, of: detail, honoring: honoringQuietHours) {
                await deferRun(of: pr, at: detail, deferral)
                reviewPhases[pr] = nil
                return
            }
            // Běh, který se rozjel, odklad ruší — ať se vyzvedl sám, nebo ho pustil člověk. Je to
            // **jedno místo**, ne jedno na cestu: dvě by znamenala slib, který v cache přežije
            // běh, o kterém slibuje.
            await forgetDeferral(of: pr)

            // Nový průchod začíná bez přeskočení z toho předchozího (#518) — stejně jako s čistou
            // osou, a u opakování jednoho revieweera (#149) se maže **jen jeho** záznam, ze
            // stejného důvodu jako u osy: ostatní se v tomhle průchodu nerozhodují, takže by po
            // nich zůstalo prázdno a dráhy, kvůli kterým se do tabu chodí, by přišly o důvod.
            //
            // Maže se **až tady**, za bránou výš: kdyby se mazalo dřív, přišla by ta brána
            // o odpověď „tenhle je přeskočený, review je hotové“ zrovna ve chvíli, kdy se ptá.
            routingSkips[pr] = forgottenSkips(for: pr, running: subset)

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

            // Routing (#518) — **před rozpočtem, zadáním i session**, protože rozhoduje o tom,
            // jestli se vůbec bude co utrácet. Sada je v tuhle chvíli hotová (odhad jazyka je
            // o řádek výš) a cesty se berou z pracovní kopie, takže dřív se to rozhodnout nedá.
            let routed = await routedSkills(for: pr, of: detail, in: worktree, only: subset, using: checkout)
            // Routing zrušení **nevyhazuje** (výpis cest se z něj vrací jako „cesty neznáme“),
            // takže se na něj musí zeptat tady — jinak by zrušené review pokračovalo na rozpočet
            // a na zadání, tedy zaplatilo za session, o kterou si nikdo neřekl. Tatáž kontrola,
            // jakou má cesta po odhadu jazyka repa a po příbuznosti větví (#517).
            try Task.checkCancellation()
            // Nezůstalo koho pustit: **nic se neutrácí a nic se neukládá**. Není to porucha, takže
            // se nehlásí chyba — jen se řekne v `Průběhu`, kde dráhy nesou kapsli `přeskočeno`
            // i důvod. Uložený záznam by tu byl na škodu: běh, který se nestal, nemá co přepsat
            // nálezy z předchozí hlavy.
            guard !routed.isEmpty else {
                reviewPhases[pr] = nil
                return
            }

            // Rozpočet **až tady**: `runSkills` je jediné místo, které session utrácí.
            // Cokoli dřív znamená platit i za běhy, které se nikdy nerozjely — selhal
            // checkout, nebo repo nemá nastavený žádný skill. Ráno to spálilo šest z dvaceti
            // za jedno dopoledne, když se to strhávalo v plánovači, a znovu, když se to
            // strhávalo před checkoutem.
            guard await canSpendSession(on: pr) else { return }

            // Zadání se připravuje **po checkoutu a před `runSkills`** (#120): leží vedle
            // pracovního stromu, takže složka pod ním má existovat, a session ho musí mít
            // v ruce dřív, než se poskládá prompt.
            //
            // Od #345 to **něco stojí** — jeden dotaz na komentáře a jedna krátká `claude -p`
            // session (~$0,2 a ~20 s). Je to schválně **tady**, tedy až za rozpočtem a za
            // checkoutem: platit za text zadání u běhu, který se pak nerozjede, je ta samá chyba,
            // kvůli které se rozpočet strhává až v `runSkills`.
            let intent = try await prepareIntent(for: pr, of: detail)

            // Nad čím se poběží (#517). Skládá se to **tady**, po checkoutu: rozhodnutí stojí na
            // tom, jestli je společná historie, a to je otázka na `git` v pracovní kopii.
            // Záznam se bere z paměti (`reviewRecords`), tedy ten, který je vidět v okně — a to
            // je ten samý, ze kterého se v panelu kreslí nálezy z minula.
            let previous = reviewRecords[pr]
            let ancestry = await incrementalAncestry(
                of: previous,
                head: detail.headSha,
                in: worktree,
                using: checkout,
                enabled: resolved(for: pr.repo).incrementalAfterPush
            )
            // `ancestry` zrušení **nevyhazuje** (nemá jak — nevrací chybu), takže se na něj musí
            // zeptat tady: bez toho by zrušené review ještě zaplatilo session, o kterou si nikdo
            // neřekl. Tatáž kontrola, jakou má cesta po odhadu jazyka repa a po zadání.
            try Task.checkCancellation()

            try await runSkills(
                for: pr,
                of: detail,
                in: worktree,
                using: reviewer,
                saving: reviews,
                only: routed,
                intent: intent.file,
                gap: intent.gap,
                previous: previous,
                ancestry: ancestry
            )
            reviewPhases[pr] = nil
            // Anotace hunků (#524) — **po review, jedině po automatu a jedině za zapnutou bránou**.
            // Vlastní task, takže se s ní nezdrží ani uložení nálezů, ani notifikace: je to session
            // navíc a review na ni nečeká.
            annotateAfterAutomaticReview(of: pr)
            await notifyAboutFinishedReview(of: pr)
            // Návrh review (#520) — **jen tady, ne za chybovými cestami**: skládá se z toho, co
            // reviewery našli, takže po spadlém checkoutu ani po chybě GitHubu není z čeho.
            // Hlava se předává z **čerstvě dotaženého detailu**, ne z okna; proč, je u metody.
            // Ve výchozím stavu je brána vypnutá, takže se nestane nic.
            await planAutoDraft(for: pr, at: detail.headSha)
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

    /// Které reviewery tenhle běh doopravdy pustí (#518) — a co si o přeskočených zapamatuje.
    ///
    /// **Routing platí jedině na celou sadu, ne na vyžádanou podmnožinu** (#149, `Pustit přesto`),
    /// a je to celá odpověď na otázku, jak se přeskočený reviewer pustí ručně: podmnožina je
    /// výslovný pokyn člověka na konkrétního revieweera, takže se nefiltruje. Pravidlo tedy
    /// rozhoduje o tom, co si vybírá **aplikace** — automat i tlačítko `Pustit review`.
    ///
    /// **Na cesty se ptá jedině repo, které si nějaké pravidlo napsalo.** Bez pravidel se `git`
    /// nespouští vůbec, takže se repo bez routingu chová do posledního podprocesu jako do #518.
    ///
    /// **Selhání výpisu cest routing vypne, nepoloží review.** `git`, který neodpověděl, znamená
    /// „cesty neznáme“ — a přeskočit revieweera kvůli tomu je tichá ztráta review, kdežto běh navíc
    /// je jen běh navíc. Je to tatáž strana, jakou drží `Policy.reviewersToRun` u prázdného seznamu.
    private func routedSkills(
        for pr: PRIdentifier,
        of detail: PullRequest,
        in worktree: URL,
        only subset: [String]?,
        using checkout: any RepoCheckout
    ) async -> [String] {
        if let subset { return subset }
        // Sada se čte **až tady**, po odhadu jazyka repa — tedy z téhož místa a v tomtéž okamžiku,
        // jako by ji přečetl `runSkills`.
        let skills = reviewSkills(for: pr.repo)
        let rules = Policy.routingRules(of: skills, paths: resolved(for: pr.repo).reviewerPaths)
        guard rules.contains(where: { !$0.paths.isEmpty }) else { return skills }
        // Bez základu není proti čemu diffovat. Nesmí to být **tichý** pád zpátky na celou sadu:
        // pravidlo, které v tomhle běhu nikoho neovlivnilo, se z okna jinak nepozná.
        guard !detail.baseSha.isEmpty else {
            reportRoutingGap(for: pr, reason: "PR nemá základní commit.")
            return skills
        }

        let files: [String]
        do {
            files = try await checkout.changedFiles(in: worktree, since: detail.baseSha)
        } catch {
            // **Zrušení není porucha routingu.** Běh se o pár řádků dál stejně zastaví
            // (`checkCancellation` za tímhle voláním), takže by hláška mluvila o review, které si
            // nikdo nevyžádal — a zůstala by ležet ve stavovém řádku. Ptáme se na stav tasku, ne na
            // `CancellationError`: `git` zabitý zrušením ohlásí selhání podprocesu.
            guard !Task.isCancelled else { return skills }
            reportRoutingGap(for: pr, reason: Self.routingFailureText(error))
            return skills
        }

        let plan = Policy.reviewersToRun(files: files, rules: rules)
        // Zapisuje se **i prázdné přeskočení**, protože nese hlavu: bez ní by brána proti druhému
        // běhu (`hasCurrentReview`) nepoznala rozhodnutí o dnešní hlavě od toho o včerejší.
        routingSkips[pr] = ReviewerRoutingPass(headSha: detail.headSha, skipped: plan.skipped)
        return plan.skills
    }

    /// Že routing v tomhle běhu **nerozhodoval** — a proč (#518).
    ///
    /// Jedna věta na jednom místě, protože důvody jsou dva (chybějící základ a `git`, který
    /// neodpověděl) a vedou na totéž: review poběží celé, jako by pravidlo nastavené nebylo.
    /// **Hlásí se jmenovitě k PR**, protože `configurationFailure` je jeden řetězec pro celou
    /// aplikaci — bez subjektu je ve frontě dvaceti PR nepoužitelný (tatáž úvaha jako
    /// u `intentFailure`).
    private func reportRoutingGap(for pr: PRIdentifier, reason: String) {
        configurationFailure = "Změněné cesty \(pr.repo)#\(pr.number) se nepodařilo zjistit, "
            + "review běží celé bez routingu. " + reason
    }

    /// Co z chyby výpisu cest ukázat člověku (nález Copilota na #518).
    ///
    /// **`CheckoutError` není `LocalizedError`**, takže `localizedDescription` u něj vydá
    /// `The operation couldn’t be completed. (PRism.CheckoutError error 5.)` — anglickou větu
    /// o interním čísle případu. Věta pro člověka je `userDescription` a nese i to, co řekl `git`;
    /// je to tentýž vzor, jakým se hlásí selhání checků (`AppStore+Checks.reason`).
    ///
    /// Fallback zůstává, protože `changedFiles` je za protokolem: fake i budoucí implementace
    /// můžou vyhodit cokoli, a „chyba, o které se nic neřekne“ je horší než anglická věta.
    private static func routingFailureText(_ error: any Error) -> String {
        (error as? CheckoutError)?.userDescription ?? error.localizedDescription
    }

    /// Co si z přeskočení nechat, když se pouští další průchod (#518).
    ///
    /// Celá sada zahodí všechno, podmnožina jen to své — tatáž úvaha jako u osy: rozhodnutí
    /// o revieweerovi, který v tomhle průchodu nefiguruje, pořád platí.
    private func forgottenSkips(for pr: PRIdentifier, running subset: [String]?) -> ReviewerRoutingPass? {
        guard let subset, let pass = routingSkips[pr] else { return nil }
        let kept = pass.skipped.filter { !subset.contains($0.key) }
        return kept.isEmpty ? nil : ReviewerRoutingPass(headSha: pass.headSha, skipped: kept)
    }

    /// Uloží zadání PR vedle pracovního stromu a vrátí cestu k němu (#120).
    ///
    /// `nil` znamená, že prompt o zadání mlčet **má** — a jsou k tomu tři různé důvody, které se
    /// nesmí slít:
    ///
    /// - **Store není** (testy). Tehdy se nic nepřipravuje a review běží jako do #120.
    /// - **Nebylo co uložit** — prázdný popis PR bez jediného odkazu. Není to porucha, takže se
    ///   o tom nic nehlásí: soubor se samými větami o tom, co v něm není, by reviewera poslal
    ///   čtením za nic.
    /// - **Zápis selhal.** To porucha je, a proto se hlásí — review poběží dál, ale bez zadání,
    ///   a to je v okně k nerozeznání od běhu, který zadání dostal.
    ///
    /// **Popis se bere z `detail`, tedy z čerstvého `gh pr view`** v téhle cestě — ne z uloženého
    /// snímku. Prázdný `body` a nedotažený `body` jsou v modelu tatáž hodnota (`String` s defaultem
    /// `""`), ale sem se nedotažený nedostane: `fetchDetail` o pár řádků výš by vyhodil a review by
    /// se nespustilo. Tvrzení o prázdném popisu se do souboru přesto **nepíše** (viz
    /// `ReviewIntentText.noDescription`) — prázdný popis znamená, že se soubor nezakládá vůbec.
    private func prepareIntent(
        for pr: PRIdentifier,
        of detail: PullRequest
    ) async throws -> (file: URL?, gap: IntentGap?) {
        guard let intents else { return (nil, nil) }

        let comments = await intentComments(for: pr)
        // **Zrušení se ptáme dřív, než se pustí session.** `intentComments` cancelaci spolkne
        // (nevyhazuje), a `SubprocessRunner` proces **spustí a teprve pak** se dozví o zrušení —
        // takže bez tohohle by zrušené review ještě zaplatilo boot session, o kterou si nikdo
        // neřekl. Je to tatáž kontrola, jakou má cesta review po odhadu jazyka repa.
        try Task.checkCancellation()
        // Jedno vytažení nad **spojeným** textem, ne dvě: dedup i pořadí prvního výskytu drží
        // `Policy.intentLinks`, takže tentýž issue z popisu a z linkbacku vyjde jednou. Popis je
        // první, protože zadání píše autor PR — linkback je jen odkaz na něj.
        let joined = ([detail.body] + comments.bodies).joined(separator: "\n\n")
        let links = Policy.intentLinks(in: joined)
        let text = try await fetchIntentText(of: links)
        let material = IntentMaterial(
            description: detail.body,
            links: links,
            issues: text.issues,
            textGap: text.gap,
            commentsUnavailable: comments.unavailable
        )
        // Na osu jde **jeden** příznak, i když nastanou oba důvody — rozhoduje o tom `Policy`,
        // ne tenhle kód. V souboru je zapsané obojí.
        let gap = Policy.intentGap(text: text.gap, commentsUnavailable: comments.unavailable)

        do {
            let brief = Policy.intentBrief(of: pr, material: material)
            let file = try intents.save(brief, for: pr, at: detail.headSha)
            // Úspěch hlášku **maže**: minulé selhání zápisu už není pravda o tomhle běhu.
            intentFailure = nil
            return (file, gap)
        } catch {
            // **Hláška jmenuje PR**, protože ve frontě dvaceti PR je „zadání se nepodařilo
            // připravit“ bez subjektu nepoužitelné — a `intentFailure` je jeden řetězec pro celou
            // aplikaci, takže si sám o sobě neřekne, o kterém běhu mluví.
            intentFailure = "Zadání pro reviewera \(pr.repo)#\(pr.number) se nepodařilo připravit, "
                + "review běží bez něj. " + error.localizedDescription
            // **Na osu nejde nic** (nález Copilota na #388). Když zápis selže, reviewer nedostal
            // soubor **vůbec** — a věty u příznaku mluví o tom, co v zadání chybí („dostal jen
            // odkazy“), takže by nad během bez zadání tvrdily víc, než data unesou. Selhat tady může
            // jedině vlastní cache a to je **jiná porucha**, kterou hlásí stavový řádek
            // (`intentFailure`, tak to zavedlo #120 — a tam to zůstává schválně, protože odznak nad
            // rozbitým diskem je UI pro stav, který nenastává).
            return (nil, nil)
        }
    }

    /// Komentáře pod PR **do cesty review** (#345). Vrací jejich těla a jestli se to nepovedlo.
    ///
    /// Konverzace se jinak načítá až při výběru řádku (`AppStore+Conversation`), v cestě review
    /// vůbec — tady se ale načíst musí: **linkback z trackeru chodí jako komentář**, tedy zrovna
    /// ten častý případ, kvůli kterému #120 vzniklo. Je to 1 bod GraphQL a jeden podproces na
    /// review (u automatu se to násobí počtem PR, ne tikem).
    ///
    /// **Uložená konverzace se nepoužívá**, i když by se tím podproces ušetřil: je klíčovaná
    /// `updatedAt` z posledního seznamu, takže může být starší než hlava, na kterou se pouští
    /// review — a komentář s odkazem mohl přijít mezitím. Jeden zdroj pravdy je tady levnější než
    /// úvaha „která kopie je čerstvější“.
    ///
    /// **Selhání review nepoloží**, ale ani se nespolkne: `unavailable` jde do souboru i na osu.
    /// Zadání bez odkazů je horší review, ne rozbité review — mlčení by z toho ale udělalo tvrzení,
    /// že PR na žádném zadání nestojí.
    private func intentComments(for pr: PRIdentifier) async -> (bodies: [String], unavailable: Bool) {
        do {
            let conversation = try await gateway.fetchConversation(id: pr)
            return (conversation.comments.items.map(\.body), false)
        } catch {
            // **Včetně zrušení**: tady se z něj nedělá výjimka, protože zrušené review se stejně
            // zastaví o pár řádků dál (`intentText`, `runSkills`) a rozdíl mezi „nevíme“
            // a „zrušeno“ se do souboru, který nikdy nevznikne, nemá kde propsat.
            return ([], true)
        }
    }

    /// Text issues, nebo důvod, proč není (#345).
    ///
    /// Tři různé odpovědi a **žádná z nich není prázdná hodnota**: bez odkazů se neptá nikdo
    /// (gap `nil` — nechybí nic, protože není na co se ptát), bez jména nástroje v konfiguraci se
    /// **netahá** (`toolNotConfigured`), a jinak se pustí session. Chybějící jméno nesmí skončit
    /// prázdným pokusem: boot session stojí peníze a nevrátil by nic.
    private func fetchIntentText(of links: [IntentLink]) async throws -> IntentTextResult {
        guard !links.isEmpty, let intentText else { return IntentTextResult() }
        guard let tool = Policy.issueTextTool(from: configuration.global.issueTextTool) else {
            return IntentTextResult(gap: .toolNotConfigured)
        }
        return try await intentText.fetchText(of: links, using: tool)
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
        only subset: [String]? = nil,
        intent intentFile: URL?,
        gap: IntentGap?,
        previous: ReviewRecord?,
        ancestry: BranchAncestry
    ) async throws {
        // Sada se čte **až tady**, po odhadu jazyka repa — proto se podmnožina předává jako
        // parametr a ne jako snímek pořízený při spuštění.
        let skills = subset ?? reviewSkills(for: pr.repo)
        reviewPhases[pr] = .running(finished: 0, total: skills.count)
        // Rozhodnutí na skill (#517), a **jednou pro celý běh**: sada je v tuhle chvíli hotová
        // a rozsah se nesmí změnit pod rukama běhu, který už jede.
        let increments = await incrementalRun(
            for: pr,
            at: detail.headSha,
            skills: skills,
            previous: previous,
            ancestry: ancestry
        )

        // Průběh teče přes proud, ne přímo do store: hlásí se ze session, která běží mimo
        // hlavní vlákno, a **pořadí událostí je to hlavní, co časová osa říká**. Proud ho
        // drží; hop do vlastního tasku na každou událost by o pořadí nechal rozhodovat
        // plánovač.
        //
        // **Uložení běhu jde tímtéž proudem** (#308), a to je celý smysl toho, že `.finished`
        // nese celý `ReviewRun`: osa se ukládá až v okamžiku, kdy do ní dojely i události, které
        // konci předcházely. Do #308 se uložení dělo mimo proud, takže si čtení osy a její zápis
        // závodily o `MainActor` — a v souboru končila osa, kterou zbyl závod, ne osa běhu.
        let (events, reporter) = AsyncStream<ReviewEvent>.makeStream()
        async let drained: (any Error)? = drain(
            events,
            for: pr,
            at: detail.headSha,
            in: worktree,
            saving: reviews,
            increments: increments
        )
        // Příznak zadání jde do osy **jako první událost každé dráhy** (#345), ne po konci běhu.
        // Odpověď je v tuhle chvíli hotová (zadání se připravilo před `runSkills`), takže s ní není
        // na co čekat — a událost, která by přišla až po doběhnutí, může dorazit do osy, kterou už
        // nikdo nečte. Za každého revieweera zvlášť, protože příznak žije na dráze: dráha bez
        // události by o sobě tvrdila, že zadání dostala celé.
        if let gap {
            for skill in skills { reporter.yield(.progress(skill: skill, .intentGap(gap))) }
        }
        // Nad čím se běží, jde do osy **taky jako první událost dráhy** (#517) a ze stejného
        // důvodu jako příznak zadání: rozhodnutí je hotové, než se session pustí, a kapsle
        // `přírůstek` má v `Průběhu` stát od chvíle, kdy se dráha objeví. **Jen když je co říct**
        // — o tom rozhoduje `ReviewScope`, ne `if` tady.
        for skill in skills {
            guard let scope = increments.reportableScope(of: skill) else { continue }
            reporter.yield(.progress(skill: skill, .scope(scope)))
        }
        await runSkills(
            for: pr,
            of: detail,
            in: worktree,
            using: reviewer,
            skills: skills,
            reporting: reporter,
            intent: intentFile,
            increments: increments
        )
        reporter.finish()
        let failure = await drained

        // Značky se mažou **až po vyprázdnění proudu** (#97). Značka i uložení výsledku jdou
        // přes něj (uložení od #308), takže se smazání nemá jak předběhnout — a i tak se maže
        // teprve tady, po `await drained`, ať to platí i pro běh, který se uložit nepovedlo.
        // Chytil to test, ne úvaha.
        //
        // Maže se **celá sada, ne jen uložené běhy**: sem se dojde jedině tehdy, když review
        // skončilo, takže značka po něm už nemá co znamenat. Pokrývá to i **zrušený** běh,
        // který se schválně neukládá — nechat mu značku by znamenalo, že příští start dotáhne
        // z transcriptu nálezy, které si člověk zrušil, tedy proti pravidlu „zrušení neuloží
        // nic“. Po pádu se sem naopak nedojde vůbec, a o to jde.
        // Maže se jen za **spuštěné** reviewery (#149): značka po skillu, který tenhle běh
        // nepouštěl, pořád platí — a smazat ji znamená přijít o nálezy, které po něm zbyly
        // v transcriptu.
        // **Při zavírání aplikace se značky nemažou** (#264). Ukončení je pro běh totéž jako pád:
        // session se zabila a co reviewer nahlásil, leží v transcriptu, odkud to příští start
        // dotáhne jako `přerušeno` (#97). Smazat značku tady by z „přerušeno se dvěma nálezy“
        // udělalo „neběželo“ — tedy ztrátu, kterou dneska zavření aplikace nedělá a dělat nemá.
        // Zrušení člověkem je jiná otázka: tam se maže dál, protože si ty nálezy nikdo nevyžádal.
        if !isTerminating {
            for skill in skills {
                await interrupted?.forget(
                    ReviewRunKey(pullRequest: pr, headSha: detail.headSha, skillID: skill)
                )
            }
        }

        if let failure { throw failure }
    }

    /// Zapisuje průběh v pořadí, ve kterém dorazil — a doběhlé běhy ukládá.
    ///
    /// Vrací **první** chybu zápisu, `nil` když se všechno uložilo. Ostatní skilly se kvůli ní
    /// nezastavují: co se uložit povedlo, se nemá zahazovat.
    private func drain(
        _ events: AsyncStream<ReviewEvent>,
        for pr: PRIdentifier,
        at headSha: String,
        in worktree: URL,
        saving reviews: ReviewStore,
        increments: IncrementalRun
    ) async -> (any Error)? {
        var saveFailure: (any Error)?
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
            case .finished(let run):
                finish(run.outcome, usage: run.summary.usage, of: run.key.skillID, for: pr)
                do {
                    // Výsledek přírůstku se skládá **tady, z materiálu toho běhu** (#517), ne
                    // v runneru: verdikty jsou v posledním sdělení session a spárovat je umí
                    // jedině ten, kdo drží seznam, na který se ptalo.
                    try await store(increments.completing(run), for: pr, saving: reviews)
                } catch {
                    // Nezapsaný nález je ztracený nález. Spolknout to by znamenalo, že řádek
                    // po doběhlém review ukazuje „neběželo“ — tedy přesně to, čemu se celý ten
                    // rozlišený stav vyhýbá. Ostatní skilly doběhnou, ať se nezahodí i to, co
                    // se uložit povedlo.
                    saveFailure = saveFailure ?? error
                }
            }
        }
        return saveFailure
    }

    /// Uloží doběhlý běh i s osou, kterou má v tuhle chvíli store.
    ///
    /// Volá se **z proudu událostí, těsně za zápisem konce osy do storu** (#308) — a to je jediné
    /// místo, odkud se osa dá uložit celá. Snímek pořízený mimo proud (tak to bylo do #308) čte
    /// `reviewTimelines` uprostřed toho, jak ho proud plní, takže do souboru šla osa zkrácená
    /// o rozjezd i o konec — a `dropped` u toho zůstalo nulové, tedy o zkrácení mlčelo. Kolik
    /// událostí zbylo, rozhodovalo pořadí na `MainActoru`: změřeno na `AppStoreProgressTests`,
    /// kde nad volným strojem v souboru končilo `[ve frontě]` a při souběžné suitě osa vůbec žádná.
    ///
    /// Osa se ukládá **s během**, ne zvlášť: je to jeho průběh, takže patří do téhož souboru
    /// a zestárne s ním (#203).
    private func store(_ run: ReviewRun, for pr: PRIdentifier, saving reviews: ReviewStore) async throws {
        // Ukládá se **před** překladem: ten je krátká síťová operace navíc a když se na ní
        // aplikace zavře, nálezy už jsou na disku. V originále, ale jsou — což je přesně to,
        // co pravidlo „co doběhlo, zůstane“ chce.
        reviewRecords[pr] = try await reviews.save(
            run,
            timeline: reviewTimelines[pr]?.first { $0.skill == run.key.skillID }?.stored()
        )
        revealFindingsOutsideTheDiff(for: pr)
        if let translated = await translated(run, for: pr.repo) {
            reviewRecords[pr] = try await reviews.save(translated)
        }
        // Nové nálezy patří do součtu po reviewerech (#514) — jinak by blok na domově až do
        // restartu tvrdil čísla z doby před tímhle během. Přepočet je tu **jednou, za oběma
        // zápisy**: překlad je druhý zápis **téhož** běhu, takže výpis po něm dá totéž.
        await refreshReviewerTallies()
    }

    /// `internal`, ne `private`, aby měření ceny jedné události průběhu (#350) sypalo do storu
    /// **tou samou cestou**, jakou to dělá běh — vlastní zápis do `reviewTimelines` v harnessu by
    /// byl druhá kopie pravidla a měřil by ji místo aplikace.
    func record(_ progress: ReviewProgress, of skill: String, for pr: PRIdentifier, in worktree: URL) {
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
    ///
    /// `internal`, protože to čte i kontrola nálezů (`AppStore+Recheck`, #150) — je to tatáž
    /// session a stejné peníze, takže druhé počítání by o mém účtu lhalo.
    func recordSpend(_ usage: RunUsage?) async {
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

    /// Pustí session a doběhlé běhy pošle do proudu. **Neukládá** — uložení sedí na konci proudu
    /// (viz `drain`), aby osa v souboru byla celá.
    private func runSkills(
        for pr: PRIdentifier,
        of detail: PullRequest,
        in worktree: URL,
        using reviewer: any ReviewRunning,
        skills: [String],
        reporting reporter: AsyncStream<ReviewEvent>.Continuation,
        intent intentFile: URL?,
        increments: IncrementalRun
    ) async {
        // Limit se bere **tady a jednou** (#320), ze stejného důvodu jako šablona o pár řádků níž:
        // všechny session tohohle běhu poběží s tímtéž limitem, i kdyby se mezitím uložilo
        // nastavení. Přes `resolved(for:)`, protože je to hodnota **repa** — velké repo si o víc
        // říct smí, zbytek fronty se tím měnit nemá.
        let timeout = resolved(for: pr.repo).reviewTimeout
        await withTaskGroup(of: ReviewRun?.self) { group in
            for skill in skills {
                let request = ReviewRequest(
                    key: ReviewRunKey(pullRequest: pr, headSha: detail.headSha, skillID: skill),
                    worktree: worktree,
                    baseSha: detail.baseSha,
                    // Šablona se bere **tady a jednou** (#281): všechny session tohohle běhu
                    // dostanou tutéž, i kdyby se mezitím uložilo nastavení. Runner si ji
                    // nečte sám — viz `ReviewRequest.promptTemplate`.
                    promptTemplate: configuration.global.reviewPrompt,
                    timeout: timeout,
                    // Jeden soubor pro celý běh (#120): zadání se váže na `(PR, headSha)`, takže
                    // ho všechny skilly sdílejí — připravuje se jednou, ne na každou session.
                    intentFile: intentFile,
                    // Přírůstek je **na skill** (#517): jeden reviewer může jít nad tím, co
                    // přibylo, a druhý — ten, který minule nedoběhl — nad celým diffem.
                    increment: increments.request(for: skill)
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
            for await run in group {
                finished += 1
                reviewPhases[pr] = .running(finished: finished, total: skills.count)
                guard let run else { continue }
                // Útrata se zapisuje **před** kontrolou zrušení: session, která doběhla,
                // peníze stála, ať už se její výsledek uloží, nebo ne. Číslo, které zrušením
                // zmizí, by o mém účtu lhalo.
                await recordSpend(run.summary.usage)
                // Zrušený běh se **neukládá** — a proto se do proudu ani nepošle. Osa si tím
                // konec nedostane, což je pravda: zrušené review nedoběhlo.
                guard !Task.isCancelled else { continue }
                reporter.yield(.finished(run))
            }
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
    ///
    /// `internal` kvůli kontrole nálezů (`AppStore+Recheck`, #150): připravuje strom tou samou
    /// cestou, takže po sobě musí stav srovnat stejně.
    func syncCheckoutState(for repo: RepoID, using checkout: any RepoCheckout) async {
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
    ///
    /// **Za hotové se počítá i to, co routing přeskočil** (#518), a bez toho by ta brána na repu
    /// s routingem přestala platit: přeskočený reviewer doběhlý běh nemá a nikdy mít nebude, takže
    /// by hotové review vypadalo jako nedokončené a stačil by komentář pod PR (mění `updatedAt`),
    /// aby si automat zaplatil celé review znovu. Rozhoduje o tom `Policy.standingSkips`, tedy
    /// **dnešní** pravidlo nad **dnešní** hlavou — po změně vzorů se review pustí, jak se čeká
    /// od úpravy nastavení.
    private func hasCurrentReview(of pr: PRIdentifier, at headSha: String) -> Bool {
        let skills = reviewSkills(for: pr.repo)
        let skipped = Policy.standingSkips(
            routingSkips[pr],
            head: headSha,
            rules: Policy.routingRules(of: skills, paths: resolved(for: pr.repo).reviewerPaths)
        )
        // **Sada přeskočená celá se počítá za hotovou i bez záznamu** (#518): není co pustit, takže
        // není co ukládat — a bez tohohle by se PR, který se nikoho netýká, klonoval po každém
        // komentáři znovu. Ptát se na `record` tady nejde: běh, který se nestal, žádný nezaložil.
        // Prázdná sada sem **nespadá** (`!skills.isEmpty`): „nemám žádného revieweera“ není hotové
        // review, je to nenastavené repo — a odpovídá na to `canSpendSession`, ne tahle brána.
        if !skills.isEmpty, Set(skills).isSubset(of: skipped) { return true }
        guard let record = reviewRecords[pr], record.headSha == headSha, !record.isStale else {
            return false
        }
        return Set(skills).isSubset(of: Set(record.runs.map(\.skillID)).union(skipped))
    }

    /// Nový head commit zneplatní i to, co držíme v paměti — jinak by řádek do konce běhu
    /// ukazoval nálezy proti kódu, který v PR není.
    ///
    /// `internal` kvůli kontrole nálezů (`AppStore+Recheck`, #150): ta si taky dotahuje detail,
    /// takže se v tu chvíli může dozvědět novou hlavu — a tvrdá podmínka č. 5 platí i tam.
    func markStaleInMemory(for pr: PRIdentifier, current headSha: String) {
        guard var record = reviewRecords[pr], record.headSha != headSha else { return }
        record.isStale = true
        reviewRecords[pr] = record
    }
}
