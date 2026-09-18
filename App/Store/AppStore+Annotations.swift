import Foundation

/// Anotace hunků (#524) — „proč je tady tahle změna“ ke každému hunku a druh změny u souboru.
///
/// Je to **vlastní druh běhu**, ne review s jiným promptem: odpovídá **jiným tvarem**
/// (`AnnotationSchema`, ve kterém pole pro závažnost není), ukládá se do vlastního souboru
/// (`AnnotationStore`) a do `runs` se nedostane, takže si nepřidá chip ani nález. Cesta je jinak
/// tatáž jako u kontroly nálezů (#150) — detail, pracovní kopie na hlavě PR, jedna `claude`
/// session —, protože popsat změnu jde jedině **nad kódem**: bez pracovního stromu by session
/// odpovídala z hlavy.
extension AppStore {
    /// Věta pro pokus, který se o kód ani neotřel, protože vrstva pod ním není zapojená.
    ///
    /// **Jedna konstanta pro obě místa**, ve kterých se to pozná (`startAnnotating` a `annotate`):
    /// dvě formulace téhož by znamenaly, že se v okně dá poznat, ve které polovině cesty se to
    /// zastavilo — a to člověka u okna nezajímá.
    static let unwiredAnnotationFailure =
        "Popis změn se nespustil — session na popis změn není v téhle instanci aplikace zapojená."

    /// Běží nad PR anotační session?
    func isAnnotating(_ pr: PRIdentifier) -> Bool { annotationTasks[pr] != nil }

    /// Anotace, které platí pro **dnešní** hlavu PR. `nil` = neplatí žádné (tvrdá podmínka č. 5).
    ///
    /// Getter, ne mapa napřímo, ze stejného důvodu jako `timelines(for:)`: rozhodnutí „záznam
    /// z jiné hlavy se nepočítá“ nemá být `if` ve view.
    func annotations(for pr: PRIdentifier) -> StoredAnnotations? {
        Policy.annotations(of: hunkAnnotations[pr], head: head(of: pr))
    }

    /// Dráha `anotace` do tabu `Průběh`. `nil` = nekreslí se.
    ///
    /// **Selhání jde dovnitř**, ne vedle: pokus, ze kterého nezbyl ani běh, by jinak v `Průběhu`
    /// nezanechal nic, a prázdno se od „neklikalo se“ nepozná.
    func annotationLane(for pr: PRIdentifier) -> ReviewerLane? {
        Policy.annotationLane(
            pass: annotationProgress[pr],
            stored: hunkAnnotations[pr],
            head: head(of: pr),
            failure: annotationFailures[pr]
        )
    }

    /// Proč se anotace nepovedly. `nil` = není co hlásit.
    func annotationFailure(for pr: PRIdentifier) -> String? { annotationFailures[pr] }

    /// V jakém stavu je ovladač `Popsat změny` v liště nad diffem.
    func annotationControl(for pr: PRIdentifier) -> Policy.AnnotationControl {
        Policy.annotationControl(isRunning: isAnnotating(pr), failure: annotationFailures[pr])
    }

    /// Dá se popis změn nabídnout? `false` = tlačítko v liště nad diffem se **nekreslí**.
    ///
    /// Zašedlé by slibovalo akci, která se zapíná jinde — tatáž úvaha jako u `Otevřít v editoru`
    /// (#530). Podmínky jsou dvě: session musí být zapojená a hlavu PR musíme znát, protože bez ní
    /// není co anotovat ani čím to klíčovat.
    func canAnnotate(_ pr: PRIdentifier) -> Bool {
        annotator != nil && head(of: pr) != nil
    }

    /// Načte anotace z disku — volá se při otevření PR, jako značky `Prošlo` (#500).
    ///
    /// **Nečte se při startu**: anotace jsou vidět jedině v diffu, takže by se při každém spuštění
    /// dekódovalo všechno, co kdy někdo popsal, kvůli obrazovce, na kterou se ten den nemusí přijít
    /// podívat. Chybějící klíč v mapě znamená „ještě se nečetlo“.
    func loadAnnotations(for pr: PRIdentifier) async {
        guard let annotationStore, hunkAnnotations[pr] == nil else { return }
        do {
            guard let stored = try await annotationStore.load(for: pr) else { return }
            hunkAnnotations[pr] = stored
        } catch {
            // Nečitelný soubor **se hlásí**: tichá nula by znamenala, že se zaplacená session tváří
            // jako neproběhlá, a příští kliknutí by ji zaplatilo znovu.
            annotationFailures[pr] = "Uložené anotace se nepodařilo přečíst. \(error.localizedDescription)"
        }
    }

    /// Spustí popis změn. Opakované zmáčknutí, dokud běží, nic nedělá.
    ///
    /// **Ruční spuštění bránu `annotatesHunks` nečte**, a je to tatáž dělba jako u routingu (#518)
    /// s `Pustit přesto`: brána rozhoduje o tom, co si vybírá aplikace, ne o tom, o co si člověk
    /// řekne kliknutím.
    func startAnnotating(for pr: PRIdentifier) {
        // Během zavírání se nic nespouští (#264) — tatáž brána jako u review. Tohle je **jediný
        // tichý návrat na téhle cestě**, a smí být tichý proto, že okno mizí: věta, kterou nikdo
        // nepřečte, je horší než žádná.
        guard !isTerminating else { return }
        // Běžící popis se druhým kliknutím **neopakuje ani nehlásí** — tlačítko v liště v té chvíli
        // nabízí zrušení, takže se sem druhý start dostat nemá.
        guard annotationTasks[pr] == nil else { return }
        annotationFailures[pr] = nil
        // **Nezapojená session se hlásí, nevrací se potichu.** Z lišty se sem dostat nedá
        // (`canAnnotate` tlačítko nekreslí), ale odjinud ano — a tichý návrat je přesně ten tvar,
        // kterým „tlačítko nic nedělá“ vzniká. Věta o tom, co chybí, je jediné, čím se to od
        // „nic se neděje“ liší.
        guard annotator != nil else {
            annotationFailures[pr] = Self.unwiredAnnotationFailure
            return
        }
        annotationTasks[pr] = Task { [weak self] in await self?.annotate(pr) }
    }

    /// Zrušení uživatelem. Session dostane `SIGKILL` a **neuloží se nic**.
    func cancelAnnotating(for pr: PRIdentifier) {
        annotationTasks[pr]?.cancel()
    }

    /// Popis změn po automatickém review (#524).
    ///
    /// **Jen za zapnutou bránou a jen po automatu.** Ruční `Spustit review` anotace nespouští:
    /// je to session navíc a kdo si o ni řekne, má na to tlačítko v liště nad diffem. Je to
    /// tatáž úvaha jako u odkladu do tichých hodin (#519), který taky platí jedině na automat.
    func annotateAfterAutomaticReview(of pr: PRIdentifier) {
        guard automaticReviews.contains(pr), resolved(for: pr.repo).annotatesHunks else { return }
        startAnnotating(for: pr)
    }

    private func annotate(_ pr: PRIdentifier) async {
        defer {
            annotationTasks[pr] = nil
            // Rozdělaný průběh se po zrušení **nenechává ležet**: dráha, která navěky „běží“, je
            // horší než žádná. Doběhlý průběh si `annotate` zapsal sám, takže se tady nic neztrácí.
            if annotationProgress[pr]?.isFinished == false { annotationProgress[pr] = nil }
        }
        // **Druhá polovina téhož**, a nesmí se slít s tou první: pracovní kopie a úložiště se
        // z `startAnnotating` nekontrolují, takže by tenhle `guard … else { return }` zůstal tichý
        // i po opravě. Byl tichý a projevilo se to tak, jak se taková věc projevit musí: tlačítko
        // šlo zmáčknout a nestalo se nic.
        guard let annotator, let checkout, let annotationStore else {
            annotationFailures[pr] = Self.unwiredAnnotationFailure
            return
        }

        do {
            // Hlava se bere **znovu**, ne z paměti — tatáž úvaha jako u kontroly nálezů (#150):
            // mezi nakreslením nabídky a kliknutím mohl přijít commit, a anotace klíčovaná starou
            // hlavou by se posadila k diffu, který už neplatí.
            let detail = try await gateway.fetchDetail(id: pr)

            checkoutStates[pr.repo] = .preparing
            let worktree = try await checkout.worktree(for: pr, at: detail.headSha)
            await syncCheckoutState(for: pr.repo, using: checkout)
            try Task.checkCancellation()

            annotationProgress[pr] = AnnotationPass(
                worktree: worktree,
                headSha: detail.headSha,
                startedAt: time.now
            )
            let run = try await annotator.annotate(
                AnnotationRequest(
                    pullRequest: pr,
                    headSha: detail.headSha,
                    worktree: worktree,
                    baseSha: detail.baseSha,
                    // Jazyk vět (#592) — **`findingsLanguage` toho repa**, ne vlastní volba: je to
                    // tatáž otázka jako u nálezů, tedy v jakém jazyce je próza v okně. Čte se
                    // **teď**, jako u překladu nálezů, takže se přepnutí projeví na dalším běhu
                    // a **uložené anotace zpětně nepřepisuje** — přeložit je nemá co (žádná druhá
                    // session) a zastarají s hlavou, jako všechno ostatní u anotací.
                    language: resolved(for: pr.repo).findingsLanguage,
                    // **Tentýž limit jako review** (#320) — proč, je u `AnnotationRequest.timeout`.
                    timeout: resolved(for: pr.repo).reviewTimeout
                ),
                progress: { [weak self] progress in
                    Task { @MainActor [weak self] in self?.record(progress, for: pr) }
                }
            )
            // Útrata se zapisuje **před** kontrolou zrušení, jako u review a u kontroly nálezů:
            // session, která doběhla, peníze stála, ať se její výsledek uloží, nebo ne.
            //
            // **Denní limit automatických běhů (`AutoRunLedger`) se tím nekrátí**, přesně jako
            // u kontroly nálezů: ten limit hlídá, kolik **review** se pustí samo, a anotace se
            // pouští jedině po review, které se do něj už započetlo, nebo na kliknutí.
            await recordSpend(run.usage)
            annotationProgress[pr]?.finish(run, at: time.now)
            try Task.checkCancellation()

            let stored = StoredAnnotations(
                pullRequest: pr,
                headSha: detail.headSha,
                hunks: run.hunks,
                files: run.files,
                outcome: run.outcome,
                sessionID: run.sessionID,
                answered: run.answered,
                dropped: run.dropped,
                finishedAt: time.now,
                usage: run.usage
            )
            try await annotationStore.save(stored)
            hunkAnnotations[pr] = stored
        } catch is CancellationError {
            // Zrušení není selhání a **neukládá se z něj nic**: věty, které si nikdo nevyžádal, by
            // po zrušení zůstaly ležet nad hunky.
            await syncCheckoutState(for: pr.repo, using: checkout)
        } catch let error as CheckoutError {
            checkoutStates[pr.repo] = .failed(error.userDescription)
            annotationFailures[pr] = "Popis změn neproběhl — pracovní kopii se nepodařilo připravit."
            annotationProgress[pr]?.finish(.failed(detail: error.userDescription), at: time.now)
        } catch let error as GitHubError {
            annotationFailures[pr] = "Popis změn neproběhl. \(error.userDescription)"
            annotationProgress[pr]?.finish(.failed(detail: error.userDescription), at: time.now)
        } catch {
            annotationFailures[pr] = "Popis změn neproběhl. \(error.localizedDescription)"
            annotationProgress[pr]?.finish(.failed(detail: error.localizedDescription), at: time.now)
        }
    }

    /// Zapíše jednu událost průběhu. `internal`, ne `private`, ze stejného důvodu jako
    /// `record(_:of:for:in:)` u review: měření má sypat do storu **tou samou cestou**, jakou to
    /// dělá běh.
    func record(_ progress: AnnotationProgress, for pr: PRIdentifier) {
        annotationProgress[pr]?.record(progress)
    }
}
