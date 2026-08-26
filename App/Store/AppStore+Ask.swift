import Foundation

/// Rozhovor s Claudem nad pull requestem (#452) — tab `Zeptat se`.
///
/// Je to **vlastní druh běhu**, ne review s jiným promptem: má užší sadu nástrojů
/// (`AskCommand`), neukládá nálezy a nedostane se do `runs`, takže si nepřidá chip ani odznak.
/// Cesta je jinak tatáž jako u kontroly nálezů (#150) — detail, pracovní kopie na hlavě PR, jedna
/// `claude` session —, protože odpověď musí **číst kód**: bez pracovního stromu by odpovídala
/// z hlavy.
extension AppStore {
    /// Rozhovor, jak ho zná okno. `nil` = z disku se ještě nečetl.
    func askConversation(for pr: PRIdentifier) -> AskConversation? { askConversations[pr] }

    /// Rozepsaná otázka.
    func askDraft(for pr: PRIdentifier) -> String { askDrafts[pr] ?? "" }

    func setAskDraft(_ text: String, for pr: PRIdentifier) { askDrafts[pr] = text }

    /// Běží nad PR odpověď?
    func isAnswering(_ pr: PRIdentifier) -> Bool { askTasks[pr] != nil }

    /// Co session zrovna dělá — řádek u prstýnku. Prázdný, dokud neřekla nic.
    func askActivityLine(for pr: PRIdentifier) -> String {
        askActivity[pr] ?? Policy.askStartingActivity
    }

    /// Proč se zeptat nedá. `nil` = dá se.
    ///
    /// Tlačítko z toho bude **zakázané s důvodem**, ne schované: chybějící tlačítko vypadá jako
    /// rozbitá aplikace, kdežto zakázané s větou řekne, co chybí.
    func askBlock(for pr: PRIdentifier) -> String? {
        guard asker != nil else {
            return "Rozhovor nejde spustit — aplikace nenašla `claude`."
        }
        guard checkout != nil else {
            return "Rozhovor nejde spustit — pracovní kopii se nemá kdo připravit."
        }
        return nil
    }

    /// Načte rozhovor z disku. Volá se při otevření tabu — co v mapě už je, se nečte znovu.
    ///
    /// **Chyba se ukáže a mapa zůstane prázdná**, ne aby se založil prázdný rozhovor: prázdný
    /// v mapě znamená „na disku nic není“, a nad rozbitým souborem by to bylo tvrzení, které
    /// data neunesou — příští otázka by začala novou session a zaplatila kontext znovu.
    func loadAskConversation(for pr: PRIdentifier) async {
        guard let asks, askConversations[pr] == nil else { return }
        do {
            askConversations[pr] = try await asks.load(for: pr) ?? AskConversation(pullRequest: pr)
        } catch {
            askFailure = "Rozhovor pro \(pr) se nepodařilo přečíst. \(error.localizedDescription)"
        }
    }

    /// Předvyplní pole otázkou k odpíchnutí. **Jen předvyplní** — text se dá přepsat, takže se
    /// z nápovědy nestane sada příkazů.
    func useAskTip(_ tip: String, for pr: PRIdentifier) {
        askDrafts[pr] = tip
    }

    /// Zeptá se na to, co je rozepsané v poli.
    ///
    /// **Text si bere store, ne volající**, jako u komentáře pod PR (#216): jinak by šlo odeslat
    /// něco jiného, než co je vidět. Otázka se do rozhovoru zapíše **hned**, ještě než session
    /// naběhne — bublina má být vidět ve chvíli, kdy se klikne, a prstýnek pod ní říká, že se na
    /// odpověď čeká.
    func askQuestion(about pr: PRIdentifier) {
        // Během zavírání se nic nespouští (#264) — tatáž brána jako u review a kontroly nálezů.
        guard !isTerminating, asker != nil, askTasks[pr] == nil, askBlock(for: pr) == nil else {
            return
        }
        let question = askDraft(for: pr).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        askDrafts[pr] = ""
        askActivity[pr] = nil
        // Hláška se maže **novou otázkou**, ne úspěšným zápisem (viz `writeAsk`): platí k jedné
        // výměně a nová otázka je ta chvíle, kdy přestává být aktuální.
        askFailure = nil
        append(AskMessage(speaker: .mine, text: question, at: time.now), to: pr)
        askTasks[pr] = Task { [weak self] in await self?.answer(question, about: pr) }
    }

    /// Zrušení uživatelem. Session dostane `SIGKILL` a odpověď se neuloží — otázka v rozhovoru
    /// **zůstane**, protože se na ni doopravdy zeptal.
    ///
    /// **Musí to jít odsud, ne až zavřením aplikace**: jedna odpověď stojí kolem dolaru a běží
    /// minuty, takže „rozmyslel jsem si to“ nesmí znamenat čekat na konec. Zkratku `⌘.` si to
    /// **nebere** — `WindowShortcut.cancelReview` má u sebe napsané, proč jedna klávesa nesmí podle
    /// stavu zastavit jednou review a jindy něco jiného; tady je to pojmenované tlačítko v tom
    /// composeru, ze kterého se otázka posílala.
    func cancelAsk(for pr: PRIdentifier) {
        askTasks[pr]?.cancel()
    }

    private func answer(_ question: String, about pr: PRIdentifier) async {
        defer {
            askTasks[pr] = nil
            askActivity[pr] = nil
        }
        guard let asker, let checkout else { return }

        do {
            // Hlava se bere **znovu**, ne z paměti — tatáž úvaha jako u kontroly nálezů: mezi
            // nakreslením tlačítka a kliknutím mohl přijít commit a odpověď se má ptát na kód,
            // který na PR doopravdy je.
            let detail = try await gateway.fetchDetail(id: pr)

            checkoutStates[pr.repo] = .preparing
            let worktree = try await checkout.worktree(for: pr, at: detail.headSha)
            await syncCheckoutState(for: pr.repo, using: checkout)
            try Task.checkCancellation()

            let resuming = askConversations[pr]?.sessionID
            // Materiál se přepisuje **před každou otázkou**, ne jen před první. Zápis do cache je
            // zdarma, kdežto zastaralý snímek stojí pravdivost pruhu `ví o tomhle PR:` — ten se
            // počítá živě, takže by nad navazující otázkou tvrdil `3 nálezy` o session, která o nich
            // neslyšela.
            let contextFile = saveAskContext(for: pr, detail: detail)

            let answer = try await asker.ask(
                AskRequest(
                    pullRequest: pr,
                    prompt: Policy.askPrompt(
                        question: question,
                        contextFile: contextFile,
                        baseSha: detail.baseSha,
                        isFollowUp: resuming != nil
                    ),
                    worktree: worktree,
                    resuming: resuming
                ),
                progress: { [weak self] progress in
                    Task { @MainActor in self?.note(progress, about: pr, worktree: worktree) }
                }
            )
            // Útrata se zapisuje **před** kontrolou zrušení, jako u review: session, která
            // doběhla, peníze stála, ať se její odpověď uloží, nebo ne.
            await recordSpend(answer.usage)
            try Task.checkCancellation()

            record(answer, about: pr)
        } catch is CancellationError {
            // Zrušení není selhání a **neukládá se z něj nic** — kromě toho, co už v rozhovoru je.
            await syncCheckoutState(for: pr.repo, using: checkout)
        } catch let error as CheckoutError {
            checkoutStates[pr.repo] = .failed(error.userDescription)
            fail(about: pr, with: "Pracovní kopii se nepodařilo připravit, takže se nebylo kde ptát.")
        } catch let error as GitHubError {
            fail(about: pr, with: "Nepovedlo se. \(error.userDescription)")
        } catch {
            fail(about: pr, with: "Nepovedlo se. \(error.localizedDescription)")
        }
    }

    /// Uloží materiál vedle pracovního stromu a vrátí cestu do promptu.
    ///
    /// `nil` znamená **materiál se nepřipravil** — a prompt pak na žádný soubor neukazuje, protože
    /// prompt nesmí ukazovat na soubor, který neexistuje (#120). Selhání zápisu se **hlásí**:
    /// odpověď bez materiálu vypadá v okně stejně jako odpověď s ním, takže by se z okna nedalo
    /// poznat, proč session o nálezech nic neví.
    private func saveAskContext(for pr: PRIdentifier, detail: PullRequest) -> URL? {
        guard let askContexts else { return nil }
        do {
            return try askContexts.save(Policy.askBrief(of: pr, material: material(for: pr, detail: detail)), for: pr)
        } catch {
            askFailure = "Materiál pro rozhovor nad \(pr) se nepodařilo uložit, takže session"
                + " nálezy ani diskuzi nevidí. \(error.localizedDescription)"
            return nil
        }
    }

    /// Co aplikace o PR ví — z toho, co má **načtené**. Nic se kvůli tomu nedotahuje: rozhovor
    /// stojí peníze i bez toho, aby si k němu aplikace stáhla celou konverzaci, a co v okně není,
    /// o tom materiál poctivě mlčí (sekce zůstanou, jen v nich stojí, že se nenačetlo).
    func material(for pr: PRIdentifier, detail: PullRequest) -> AskMaterial {
        AskMaterial(
            title: detail.title,
            branch: detail.headRef,
            baseSha: detail.baseSha,
            description: detail.body,
            findings: reviewRecords[pr]?.activeFindings ?? [],
            blockingCategories: resolved(for: pr.repo).blockingCategories,
            conversation: conversation(for: pr),
            checks: checks[pr] ?? []
        )
    }

    /// Chipy `ví o tomhle PR:` — ze **stejných hodnot**, ze kterých se skládá materiál, aby pruh
    /// nemohl tvrdit něco jiného než soubor.
    func askContextChips(for pr: PRIdentifier) -> [AskContextChip] {
        let findings = reviewRecords[pr]?.activeFindings ?? []
        let blocking = Set(resolved(for: pr.repo).blockingCategories)
        let conversation = conversation(for: pr)
        return Policy.askContextChips(
            diffFiles: loadedDiffFileCount(for: pr),
            findings: findings.count,
            blockingFindings: findings.count { blocking.contains($0.category ?? "") },
            comments: (conversation?.comments.items.count ?? 0)
                + (conversation?.threads.items.count ?? 0)
                + (conversation?.reviews.items.count ?? 0),
            checks: (checks[pr] ?? []).count
        )
    }

    private func loadedDiffFileCount(for pr: PRIdentifier) -> Int {
        guard case .loaded(let diff, _) = diffState(for: pr) else { return 0 }
        return diff.files.count
    }

    /// Co session právě dělá, do řádku u prstýnku.
    private func note(_ progress: AskProgress, about pr: PRIdentifier, worktree: URL?) {
        // Došlá událost z běhu, který mezitím skončil, se zahazuje — jinak by po doběhnutí
        // zůstal viset řádek o kroku, který se hlásil naposled.
        guard askTasks[pr] != nil else { return }
        switch progress {
        case .started: askActivity[pr] = Policy.askStartingActivity
        case .attemptedTool(let tool): askActivity[pr] = Policy.askActivity(of: tool, inside: worktree)
        }
    }

    /// Zapíše odpověď do rozhovoru.
    ///
    /// **Bublina vznikne i pro odpověď, která nedoběhla** — nese pak `failure` a to, co session
    /// stihla říct. Zahodit text kvůli tomu, že u něj stojí hláška, by znamenalo zaplatit odpověď
    /// a nezobrazit ji.
    ///
    /// `sessionID` se přepisuje **vždycky, když dorazilo**: `claude --resume` id **může vrátit
    /// jiné**. V naměřeném běhu zůstalo totéž (`docs/claude-cli.md`), ale držet to první by
    /// znamenalo, že se změněné id ztratí a třetí otázka naváže na tu první.
    ///
    /// **A když nedorazilo, staré se zahodí.** Bez toho by rozhovor s nefunkčním navázáním
    /// (session vypršela, cache se uklidila, `claude` ji nezná) zůstal rozbitý **navždycky**:
    /// každá další otázka by se pokusila navázat na tentýž mrtvý identifikátor a v okně by nebylo
    /// nic, čím začít znovu. Zahozením se z příští otázky stane první — založí novou session
    /// a znovu složí materiál. Zprávy v rozhovoru zůstávají; ztrácí se jen to, co stejně nefunguje.
    private func record(_ answer: AskAnswer, about pr: PRIdentifier) {
        askConversations[pr, default: AskConversation(pullRequest: pr)].sessionID = answer.sessionID
        append(
            AskMessage(
                speaker: .claude,
                text: answer.text ?? "",
                at: time.now,
                readFiles: answer.readFiles,
                usage: answer.usage,
                // Odpověď bez textu a bez důvodu je pořád mezera, o které se musí mluvit: session
                // doběhla a neřekla nic, což se v okně nesmí tvářit jako prázdná bublina.
                failure: answer.failure
                    ?? (answer.text == nil ? "Session doběhla, ale neposlala žádnou odpověď." : nil)
            ),
            to: pr
        )
    }

    private func fail(about pr: PRIdentifier, with reason: String) {
        append(AskMessage(speaker: .claude, text: "", at: time.now, failure: reason), to: pr)
    }

    /// Přidá zprávu a uloží rozhovor.
    ///
    /// Ukládá se po **každé** zprávě, ne až na konci: otázka zapsaná před spuštěním session musí
    /// přežít i pád aplikace uprostřed odpovědi — jinak by po restartu chyběla otázka, za kterou
    /// se zaplatilo.
    private func append(_ message: AskMessage, to pr: PRIdentifier) {
        askConversations[pr, default: AskConversation(pullRequest: pr)].messages.append(message)
        persistAsk(for: pr)
    }

    /// Zapíše rozhovor na disk.
    ///
    /// **Hodnota se čte až v tasku**, ne v tomhle volání — tentýž vzor jako `persistDraft`
    /// (`AppStore+Submission`) a je to podmínka správnosti, ne styl: otázka a odpověď se zapisují
    /// každá zvlášť, takže dva tasky běží krátce po sobě a **pořadí jejich doběhnutí není
    /// zaručené**. Se snímkem v parametru by starší zápis mohl přebít novější, a v souboru by po
    /// restartu chyběla odpověď, za kterou se zaplatilo. Se čtením v tasku zapíšou obě volání týž
    /// konečný stav.
    private func persistAsk(for pr: PRIdentifier) {
        guard asks != nil else { return }
        Task { [weak self] in await self?.writeAsk(for: pr) }
    }

    /// **Úspěšný zápis hlášku nemaže**, a je to podmínka, ne opomenutí: `askFailure` nese
    /// i „materiál se nepodařilo uložit“, což je stav **té odpovědi**, která právě běží — a její
    /// uložení přijde vzápětí po ní. Mazat tady by tedy znamenalo, že hláška o session bez nálezů
    /// zmizí přesně ve chvíli, kdy ta odpověď dorazí. Maže ji **nová otázka** (`askQuestion`).
    private func writeAsk(for pr: PRIdentifier) async {
        guard let asks, let conversation = askConversations[pr] else { return }
        do {
            try await asks.save(conversation)
        } catch {
            askFailure = "Rozhovor pro \(pr) se nepodařilo uložit. \(error.localizedDescription)"
        }
    }
}
