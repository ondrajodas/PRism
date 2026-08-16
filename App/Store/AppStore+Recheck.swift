import Foundation

/// Kontrola nálezů z minula (#150) — „co jsem hlásil a spravily to nové commity?“.
///
/// Je to **vlastní druh běhu**, ne review s jiným promptem: ptá se na vyjmenované nálezy,
/// ukládá se vedle nich (`ReviewRecord.recheck`) a do `runs` se nedostane, takže si nepřidá
/// chip ani nálezy. Cesta je jinak tatáž jako u review — detail, pracovní kopie na hlavě PR,
/// jedna `claude` session přes `ReviewRunning` —, protože kontrola musí **číst kód**: bez
/// pracovního stromu by odpovídala z hlavy.
extension AppStore {
    /// Nálezy, které jde nechat prověřit. `nil` = tlačítko se nenabízí.
    ///
    /// Podmínky jsou tři a každá zavírá jinou nesmyslnou session:
    ///
    /// - **je uložený záznam s platnými nálezy** — bez nich se kontrola nemá na co ptát;
    ///   chybějící vstup nesmí skončit během, který hádá;
    /// - **hlavu PR známe** (detail se načetl) — jinak není proti čemu kontrolovat;
    /// - **záznam patří jinému commitu, než na kterém PR stojí** — nad tou samou hlavou se
    ///   „spravily to nové commity“ nemá koho ptát, žádné nové commity nejsou.
    ///
    /// Bere se **ten záznam, který je v okně** (`reviewRecords`), tedy nejbližší předchozí —
    /// ne celá historie po commitech. Je to schválně: otázka zní „co se změnilo od minula“,
    /// takže starší kola nepřidávají odpověď, ale cenu (delší prompt, dražší session) — a hlavně
    /// by odznaky nešlo kam ukázat, protože v okně visí nálezy z tohohle jednoho záznamu.
    func recheckMaterial(for pr: PRIdentifier) -> RecheckMaterial? {
        recheckMaterial(for: pr, head: head(of: pr))
    }

    /// Materiál proti **vyjmenované** hlavě, ne proti té z načteného detailu.
    ///
    /// Potřebuje to spuštění kontroly: to si hlavu dotahuje **znovu** (`fetchDetail`) a do cache
    /// detailu ji nezapisuje, takže `head(of:)` by v tu chvíli vracel starší hodnotu. Rozhodovat
    /// podle ní znamená, že by **force push zpátky na commit nálezů** kontrolu pustil — hlava
    /// z cache se od záznamu pořád liší, kdežto čerstvá už ne. Session by pak porovnávala commit
    /// sama se sebou a stála peníze; nálezem Copilota na #271.
    func recheckMaterial(for pr: PRIdentifier, head: String?) -> RecheckMaterial? {
        guard let record = reviewRecords[pr], let head, record.headSha != head else {
            return nil
        }
        let findings = record.activeFindings
        guard !findings.isEmpty else { return nil }
        return RecheckMaterial(headSha: record.headSha, findings: findings)
    }

    /// Běží nad PR kontrola nálezů?
    func isRechecking(_ pr: PRIdentifier) -> Bool { recheckTasks[pr] != nil }

    /// Kdy kontrola začala — hodiny u tlačítka. `nil` = neběží.
    func recheckStartedAt(for pr: PRIdentifier) -> Date? { recheckTasks[pr]?.startedAt }

    /// Co o uložených nálezech říká poslední kontrola. Skládá to `Policy` proti hlavě, kterou
    /// PR má **teď** — kontrola proti staršímu commitu odznaky nerozsvítí (tvrdá podmínka č. 5).
    func recheckReport(for pr: PRIdentifier) -> Policy.RecheckReport {
        Policy.recheck(of: reviewRecords[pr], head: head(of: pr))
    }

    /// Spustí kontrolu nálezů. Opakované zmáčknutí, dokud běží, nic nedělá.
    func startRecheck(for pr: PRIdentifier) {
        // Během zavírání se nic nespouští (#264) — tatáž brána jako u review.
        guard !isTerminating, reviewer != nil, recheckTasks[pr] == nil else { return }
        guard recheckMaterial(for: pr) != nil else { return }
        recheckFailures[pr] = nil
        recheckTasks[pr] = RunningRecheck(
            task: Task { [weak self] in await self?.recheck(pr) },
            startedAt: time.now
        )
    }

    /// Zrušení uživatelem. Session dostane `SIGKILL` a nic se neuloží.
    func cancelRecheck(for pr: PRIdentifier) {
        recheckTasks[pr]?.task.cancel()
    }

    private func recheck(_ pr: PRIdentifier) async {
        defer { recheckTasks[pr] = nil }
        guard let reviewer, let checkout, let reviews else { return }

        do {
            // SHA umí dát jen detail — a bere se **znovu**, ne z paměti: mezi nakreslením
            // tlačítka a kliknutím mohl přijít commit, a kontrola proti hlavě, která už není,
            // by tvrdila „vyřešeno“ o kódu, na který se nikdo nekoukal.
            let detail = try await gateway.fetchDetail(id: pr)
            try await reviews.markCurrent(detail.headSha, of: pr)
            markStaleInMemory(for: pr, current: detail.headSha)

            // Materiál se skládá **až po dotažení detailu, a proti němu** — ne proti hlavě
            // z cache detailu, kterou `fetchDetail` výš nepřepisuje. Když se hlava mezitím
            // posunula na commit nálezů (force push zpátky), není co kontrolovat — a je to stav,
            // ne chyba.
            guard let material = recheckMaterial(for: pr, head: detail.headSha) else {
                recheckFailures[pr] = "Nálezy platí pro hlavu, na které PR stojí — kontrolovat"
                    + " není co. Pusť rovnou review."
                return
            }

            checkoutStates[pr.repo] = .preparing
            let worktree = try await checkout.worktree(for: pr, at: detail.headSha)
            await syncCheckoutState(for: pr.repo, using: checkout)
            try Task.checkCancellation()

            let run = try await reviewer.run(
                ReviewRequest.recheck(
                    of: pr,
                    at: detail.headSha,
                    worktree: worktree,
                    baseSha: detail.baseSha,
                    material: material,
                    // **Tentýž limit jako review** (#320), ne vlastní. Je to tatáž session, tentýž
                    // pracovní strom a tytéž peníze — a kdo u pomalého repa limit zvedá, zvedá ho
                    // kvůli tomu repu, ne kvůli jednomu ze dvou druhů běhu. Že je kontrola v praxi
                    // kratší, na tom nic nemění: strop, který se nevyčerpá, nic nestojí, kdežto
                    // vlastní kratší strop by z pomalé kontroly udělal `timedOut`.
                    timeout: resolved(for: pr.repo).reviewTimeout
                )
            )
            // Útrata se zapisuje **před** kontrolou zrušení, jako u review: session, která
            // doběhla, peníze stála, ať se její výsledek uloží, nebo ne.
            await recordSpend(run.summary.usage)
            try Task.checkCancellation()

            reviewRecords[pr] = try await reviews.saveRecheck(
                stored(run, against: detail.headSha, of: material),
                for: pr,
                at: material.headSha
            )
        } catch is CancellationError {
            // Zrušení není selhání a **neukládá se z něj nic**: verdikty, které si nikdo
            // nevyžádal, by po zrušení zůstaly ležet u nálezů.
            await syncCheckoutState(for: pr.repo, using: checkout)
        } catch let error as CheckoutError {
            checkoutStates[pr.repo] = .failed(error.userDescription)
            recheckFailures[pr] = "Kontrola nálezů neproběhla — pracovní kopii se nepodařilo"
                + " připravit."
        } catch let error as GitHubError {
            recheckFailures[pr] = "Kontrola nálezů neproběhla. \(error.userDescription)"
        } catch {
            recheckFailures[pr] = "Kontrola nálezů neproběhla. \(error.localizedDescription)"
        }
    }

    /// Přeloží doběhlý běh na to, co se ukládá.
    ///
    /// Odpověď je v **posledním sdělení** session (`result` event), ne v tool callu: verdikt
    /// o nálezu není nález, takže `ReportFindings` na něj nemá pole. Čte se defenzivně
    /// (`RecheckCommand.parse`) a co se přečíst nedá, se **nedopočítává** — nález bez odpovědi
    /// zůstane v okně jako nezodpovězený.
    ///
    /// Ukládá se i běh, který spadl nebo vytimeoutoval: odpovědi, které stihl poslat, platí a
    /// `outcome` v okně říká, že za zbytek nemluví. Tatáž úvaha jako u částečných nálezů.
    private func stored(
        _ run: ReviewRun,
        against headSha: String,
        of material: RecheckMaterial
    ) -> StoredRecheck {
        let answers = RecheckCommand.parse(
            run.summary.outcome?.text,
            count: material.findings.count
        )
        return StoredRecheck(
            againstHeadSha: headSha,
            outcome: run.outcome,
            sessionID: run.sessionID,
            statuses: Policy.recheckStatuses(answers, of: material.findings),
            finishedAt: time.now,
            usage: run.summary.usage
        )
    }
}
