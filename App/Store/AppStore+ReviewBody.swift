import Foundation

/// Tělo návrhu review v mém hlasu (#521) — **osmá session**, a třetí bez jediného nástroje.
///
/// **Stojí na #520, nepřidává vlastní bránu.** Návrh review se skládá jedině tam, kde je zapnuté
/// `autoDraft` (globálně i per repo, **ve výchozím stavu vypnuto**), a tělo je jeho část — ne
/// samostatná funkce, kterou by se dalo zapnout zvlášť. Druhá volba by znamenala stav „návrh ano,
/// tělo ne“, o kterém by v okně nebylo poznat, že je úmyslný: pruh by nad složeným návrhem mlčel
/// o tom, proč je composer prázdný.
///
/// **Nic z toho nikam neodesílá.** Odstavec končí v `ReviewDraft.body`, tedy tam, kde končí i to,
/// co napíšu sám — odejít umí jedině přes `ReviewPublishing.submit`, z potvrzení s celým payloadem
/// (tvrdá podmínka č. 1). Tělo je **text v composeru**, editovatelný, nic víc.
///
/// **Denní rozpočet (`autoRunsPerDay`) se tu nečerpá, a je to rozhodnutí** — tatáž úvaha jako
/// u briefu (#516): ten limit je pojistka proti řadě **patnáctiminutových** review a agentů, kdežto
/// tohle je jeden odstavec bez nástrojů, navíc jedině za během, který ten rozpočet už jednou
/// ukrojil. Co tělo stálo, je vidět na jeho dráze v `Průběhu` i v `Dneska stálo` — účet tedy nikde
/// nemlčí.
extension AppStore {
    // MARK: - Spuštění

    /// Píše se na tomhle PR právě tělo?
    func isWritingReviewBody(_ pr: PRIdentifier) -> Bool { reviewBodyTasks[pr] != nil }

    /// Po složení návrhu (#520): napiš k němu tělo.
    ///
    /// Volá se z `materializeAutoDraft`, tedy **z jednoho místa a až za složeným draftem** —
    /// odstavec, který mluví o převzatých nálezech, nemá vzniknout dřív, než ty nálezy v panelu
    /// leží.
    ///
    /// **Nečeká se na to** (vlastní task, jako u anotací): `materializeAutoDraft` běží uvnitř
    /// načítání diffu, takže minuta čekání na session by zdržela otevření pull requestu.
    ///
    /// **Pět bran, a každá z nich znamená „takhle ne“:**
    ///
    /// 1. **Zapojená session.** `nil` = stav před #521, ve kterém se tělo nepsalo vůbec; tak jsou
    ///    na tom testy, které o osmou session nestojí.
    /// 2. **Zavírá se aplikace** (#264). Pouštět session, která ji přežije, je zrovna to, co se tím
    ///    zavíráním zastavuje.
    /// 3. **Neběží už jedna.** Tudy se chodí při každém načtení diffu, takže bez tohohle by dvě
    ///    otevření PR za sebou znamenala dvě session za tytéž peníze.
    /// 4. **Razítko o těle ještě nemluví.** Zapsané razítko — **i to, které nese selhání** — je to,
    ///    co drží cenu: bez něj by se session po každém dalším otevření PR pustila znovu.
    /// 5. **Draft se doopravdy složil.** Návrh ze samých sporných nálezů žádný draft nezakládá
    ///    (#520) a **tohle to nemá měnit**: tělo by byl jediný obsah rozdělaného review, takže by
    ///    v řádku fronty přibylo „je co poslat“ nad návrhem, který schválně nic nepřevzal. Nad
    ///    prázdným panelem mluví pruh, a to stačí.
    func startReviewBody(for pr: PRIdentifier, plan: AutoDraftPlan) {
        guard let reviewBodyWriter, !isTerminating else { return }
        guard reviewBodyTasks[pr] == nil else { return }
        guard let stamp = reviewRecords[pr]?.autoDraft, stamp.body == nil else { return }
        guard !plan.adopt.isEmpty, drafts[pr] != nil else { return }
        // **Co je v composeru teď**, aby se poznalo, že jsem do něj mezitím začal psát sám. Bere se
        // **před** během, ne po něm: po běhu už není s čím srovnávat.
        let composed = drafts[pr]?.body ?? ""

        reviewBodyTasks[pr] = Task { [weak self] in
            await self?.writeReviewBody(for: pr, plan: plan, composed: composed, with: reviewBodyWriter)
            self?.reviewBodyTasks[pr] = nil
        }
    }

    /// Jeden běh a jeho výsledek.
    private func writeReviewBody(
        for pr: PRIdentifier,
        plan: AutoDraftPlan,
        composed: String,
        with writer: any ReviewBodyWriting
    ) async {
        let voice = await reviewVoice?.samples() ?? []
        let material = Policy.reviewBodyInput(plan: plan, voice: voice)
        reviewBodySamples[pr] = material.samples

        let answer: ReviewBodyAnswer
        do {
            answer = try await writer.write(ReviewBodyRequest(input: material.text))
        } catch is CancellationError {
            // Zrušení (zavírání aplikace) **není selhání těla**: razítko se nechává prázdné, takže
            // se po příštím otevření PR zkusí znovu. Zapsané selhání by naopak znamenalo, že se
            // tělo k tomuhle návrhu nenapíše nikdy — a to o zavřené aplikaci neplatí.
            reviewBodySamples[pr] = nil
            return
        } catch {
            await finishReviewBody(
                for: pr,
                samples: material.samples,
                usage: nil,
                failure: .session(detail: "Session se nepovedlo spustit. \(error.localizedDescription)")
            )
            return
        }
        // **Cena jde do `SpendLedger` vždycky, i když text nedorazil** (jako u briefu): zabitá
        // session peníze stála taky, a útrata, která se ztratí právě u nepovedeného běhu, je
        // o účtu lež.
        await recordSpend(answer.usage)

        guard let text = answer.text else {
            await finishReviewBody(
                for: pr,
                samples: material.samples,
                usage: answer.usage,
                failure: .session(detail: answer.failure ?? "Session nevrátila žádný text.")
            )
            return
        }
        // **Draft mohl mezitím zmizet** (`Zahodit návrh`, `Zahodit review`, odeslané review) — pak
        // se nemá co doplňovat a razítko je taky pryč, takže se nezapisuje nic. Bez tohohle by
        // `prependDraftBody` přes `mutateDraft` **založil nový draft** ze samotného odstavce, tedy
        // rozdělané review, které jsem před minutou zahodil.
        guard let current = drafts[pr] else {
            reviewBodySamples[pr] = nil
            return
        }
        // **Co jsem začal psát já, se nepřepíše ani o odstavec** — tatáž věta, na které u #520 stojí
        // brána `draftExists`. Razítko to přizná (`handWritten`), aby se session nepustila znovu
        // a aby pruh nemlčel o tom, proč v composeru odstavec od automatu není.
        guard current.body == composed else {
            await finishReviewBody(
                for: pr,
                samples: material.samples,
                usage: answer.usage,
                failure: .handWritten
            )
            return
        }
        prependDraftBody(text, for: pr)
        await finishReviewBody(for: pr, samples: material.samples, usage: answer.usage, failure: nil)
    }

    /// Zapíše do razítka, jak to s tělem dopadlo.
    ///
    /// **Selhání zápisu se spolkne, a je to tatáž úvaha jako u razítka samotného** (#520): tělo
    /// v composeru leží (nebo neleží) tak jako tak a nejhorší následek je jeden běh navíc po
    /// restartu. Hlásit poruchu nad review, které doběhlo v pořádku, by to nezasloužilo.
    private func finishReviewBody(
        for pr: PRIdentifier,
        samples: Int,
        usage: RunUsage?,
        failure: AutoDraftBody.Failure?
    ) async {
        reviewBodySamples[pr] = nil
        guard let reviews, let record = reviewRecords[pr], var stamp = record.autoDraft else { return }
        stamp.body = AutoDraftBody(
            samples: samples,
            failure: failure,
            usage: usage,
            finishedAt: time.now
        )
        reviewRecords[pr]?.autoDraft = stamp
        reviewRecords[pr] = (try? await reviews.saveAutoDraft(stamp, for: pr, at: record.headSha))
            ?? reviewRecords[pr]
    }

    /// Postaví odstavec **nad** to, co v těle review už leží.
    ///
    /// **Nahoru, ne dolů, a nepřepisuje se.** V těle už můžou být odkazy na kód — nálezy, které
    /// GitHub u řádku nepustí, tam skládá `appendDraftBodyItem` (#62). Odstavec je souhrn, takže
    /// patří před ně; `setDraftBody` by je smazal, a to jsou převzaté nálezy, ne ozdoba.
    private func prependDraftBody(_ text: String, for pr: PRIdentifier) {
        mutateDraft(for: pr) { draft in
            draft.body = draft.body.isEmpty ? text : text + "\n\n" + draft.body
        }
    }

    // MARK: - Co je z těla vidět

    /// Druhá řádka pruhu nad panelem. `nil` = pruh o těle mlčí.
    func reviewBodyNote(for pr: PRIdentifier) -> String? {
        Policy.reviewBodyNote(autoDraftStamp(for: pr)?.body)
    }

    /// Dráha osmé session v tabu `Průběh`. `nil` = na tomhle PR se tělo nepsalo.
    ///
    /// **Razítko se bere přes `autoDraftStamp`**, tedy už po kontrole hlavy (#520) — tvrdá podmínka
    /// č. 5 tu platí přes razítko, ne vedle něj.
    func reviewBodyLane(for pr: PRIdentifier) -> ReviewerLane? {
        Policy.reviewBodyLane(
            isRunning: isWritingReviewBody(pr),
            body: autoDraftStamp(for: pr)?.body,
            samples: reviewBodySamples[pr] ?? 0
        )
    }

    // MARK: - Sběr hlasu

    /// Zapíše do ledgeru **moje** odeslaná těla review z načtené konverzace (#521).
    ///
    /// Volá se z `loadConversation`, tedy z toho jediného místa, kam konverzace dorazí. **Sbírá se
    /// čtením, ne zápisem**: co leží na GitHubu, je to, co jsem doopravdy odeslal — včetně review
    /// odeslaných odjinud než z téhle aplikace a včetně pozdějších editací.
    ///
    /// **Cizí nic.** Filtr je v `Policy.reviewVoiceSamples` a stojí na `Conversation.isMine`, tedy
    /// na přihlášeném účtu z odpovědi GitHubu — ne na jménu v konfiguraci.
    func recordReviewVoice(from conversation: Conversation) async {
        guard let reviewVoice else { return }
        let fresh = Policy.reviewVoiceSamples(in: conversation)
        guard !fresh.isEmpty else { return }
        await reviewVoice.record(fresh)
    }
}
