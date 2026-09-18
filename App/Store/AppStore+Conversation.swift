import Foundation

/// Cizí konverzace pod PR (#63) a odpovídání do vláken (#73).
///
/// Dohromady schválně: odpověď se zapisuje do **načtené** konverzace (`Policy.inserting`),
/// takže obojí sahá na tentýž stav a rozdělit to by znamenalo hledat půlku pravidla jinde.
extension AppStore {
    func conversationState(for pr: PRIdentifier) -> ConversationState? { conversationStates[pr] }

    func conversation(for pr: PRIdentifier) -> Conversation? {
        guard case .loaded(let conversation, _) = conversationStates[pr] else { return nil }
        return conversation
    }

    /// Načte konverzaci vybraného PR. Cache stejná jako u diffu — na GitHub se sáhne znovu,
    /// teprve když se změní `updatedAt`.
    ///
    /// **Netahá se při pollingu.** Konverzace pro všech N PR je tatáž N+1 past, kvůli které
    /// se netahá ani detail: jeden tik by byl N podprocesů. Načítá se při výběru řádku.
    func loadConversation(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard !hasCurrentConversation(for: pullRequest) else { return }
        conversationStates[id] = .loading

        do {
            let conversation = try await gateway.fetchConversation(id: id)
            conversationStates[id] = .loaded(conversation, updatedAt: pullRequest.updatedAt)
            // Vzorek hlasu pro osmou session (#521). **Sbírá se čtením**: co je na GitHubu, je to,
            // co jsem doopravdy odeslal — a tohle je jediné místo, kam konverzace dorazí.
            await recordReviewVoice(from: conversation)
        } catch is CancellationError {
            // Maže se **jen** rozdělaný stav: mezitím spuštěné načtení už mohlo doběhnout
            // a to se přepsat nesmí. Stejné pravidlo jako u diffu.
            if conversationStates[id] == .loading { conversationStates[id] = nil }
        } catch let error as GitHubError {
            conversationStates[id] = .failed(error.userDescription)
        } catch {
            conversationStates[id] = .failed(error.localizedDescription)
        }
    }

    /// Ruční obnovení konverzace — zahodí uložený stav a načte znovu.
    ///
    /// Kotví se na to, že konverzace **zastarává jinak než diff**: kolega odpoví za minutu
    /// a `updatedAt` se tím sice změní, ale seznam se obnovuje po minutách. Tlačítko je
    /// levnější než čekat na tik.
    func refreshConversation(for pullRequest: PullRequestSummary) async {
        conversationStates[pullRequest.id] = nil
        await loadConversation(for: pullRequest)
    }

    /// Rozdělané načítání se za platnou konverzaci **nepovažuje** — stejný důvod jako
    /// u diffu: přeskočit to jediné, které běží, znamená prázdno v okně.
    private func hasCurrentConversation(for pullRequest: PullRequestSummary) -> Bool {
        guard case .loaded(_, let updatedAt) = conversationStates[pullRequest.id] else { return false }
        return updatedAt == pullRequest.updatedAt
    }

    /// Co patří do tabu `Přehled` — konverzace, která se neváže k řádku v aktuálním diffu.
    ///
    /// Prázdné, dokud konverzace nedorazí. Že se **načítá** nebo že to **selhalo**, se pozná
    /// z `conversationState(for:)`; prázdný seznam sám o sobě neznamená „nikdo nic nenapsal“.
    func overview(for pr: PRIdentifier) -> [ConversationEntry] {
        guard let conversation = conversation(for: pr) else { return [] }
        return Policy.overview(of: conversation, renderedIn: loadedDiff(for: pr))
    }

    /// Vlákna, která se v diffu dají zakotvit — ta se kreslí jako bubliny.
    func anchoredThreads(for pr: PRIdentifier) -> [ReviewThread] {
        guard let conversation = conversation(for: pr) else { return [] }
        return Policy.threadsInTheDiff(conversation.threads.items, renderedIn: loadedDiff(for: pr))
    }

    func isThreadExpanded(_ thread: ReviewThread, in pr: PRIdentifier) -> Bool {
        Policy.isThreadExpanded(thread, toggled: toggledThreads[pr] ?? [])
    }

    func threadReply(for threadID: String, in pr: PRIdentifier) -> String {
        threadReplies[ThreadKey(pullRequest: pr, threadID: threadID)] ?? ""
    }

    /// Zapíše rozepsaný text. Prázdný se **maže**, ať mapa nedrží záznam po každém vlákně,
    /// do kterého někdo klikl a rozmyslel si to — tentýž vzor jako prázdný draft.
    func setThreadReply(_ text: String, for threadID: String, in pr: PRIdentifier) {
        let key = ThreadKey(pullRequest: pr, threadID: threadID)
        threadReplies[key] = text.isEmpty ? nil : text
    }

    func threadState(for threadID: String, in pr: PRIdentifier) -> ThreadActionState? {
        threadStates[ThreadKey(pullRequest: pr, threadID: threadID)]
    }

    /// Smí se do vláken tohohle repa odesílat?
    ///
    /// Tatáž brána jako u review (`PublishScope`), takže se okno neptá dvakrát jinak. Okno na
    /// ni ale nereaguje schováním tlačítka — nechá ho **zakázané s důvodem**, jinak by
    /// chybějící tlačítko vypadalo jako rozbitá aplikace.
    func canPublishToThreads(in repo: RepoID) -> Bool {
        gh != nil && publishScope.allows(repo)
    }

    /// Odešle rozepsanou odpověď do vlákna a vloží ji do konverzace.
    ///
    /// Text se po úspěchu maže, po selhání **zůstává** — je to zadání #73 a jediná pojistka
    /// proti tomu, aby se rozepsaná věta ztratila kvůli chvilkovému výpadku.
    func sendThreadReply(to thread: ReviewThread, in pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        let key = ThreadKey(pullRequest: id, threadID: thread.id)
        let body = threadReplies[key] ?? ""
        guard let submission = threadSubmission(for: thread.id, in: id) else { return }
        // Dvojklik: druhé odeslání by bylo druhý komentář, ne oprava prvního. Kontrola leží
        // **před** prvním `await`, takže mezi nimi není mezera, do které by se závod vešel.
        guard threadStates[key]?.isBusy != true else { return }
        threadStates[key] = .replying

        do {
            let comment = try await submission.reply(body)
            threadStates[key] = nil
            threadReplies[key] = nil
            insert(comment, intoThread: thread.id, of: pullRequest)
        } catch let error as PublishError {
            threadStates[key] = .replyFailed(error)
        } catch {
            threadStates[key] = .replyFailed(.unknown(error.localizedDescription))
        }
    }

    /// Přepne vyřešení vlákna a zapíše, co GitHub potvrdil.
    func setThreadResolved(
        _ resolved: Bool,
        of thread: ReviewThread,
        in pullRequest: PullRequestSummary
    ) async {
        let id = pullRequest.id
        let key = ThreadKey(pullRequest: id, threadID: thread.id)
        guard let submission = threadSubmission(for: thread.id, in: id) else { return }
        guard threadStates[key]?.isBusy != true else { return }
        threadStates[key] = .resolving(to: resolved)

        do {
            let resolution = try await submission.setResolved(resolved)
            threadStates[key] = nil
            apply(resolution, of: pullRequest)
        } catch let error as PublishError {
            threadStates[key] = .resolutionFailed(error)
        } catch {
            threadStates[key] = .resolutionFailed(.unknown(error.localizedDescription))
        }
    }

    // MARK: - Komentář pod PR (#216)

    func pullRequestComment(for pr: PRIdentifier) -> String {
        pullRequestComments[pr] ?? ""
    }

    /// Zapíše rozepsaný text. Prázdný se **maže**, ať mapa nedrží záznam po každém PR, do
    /// jehož composeru někdo klikl a rozmyslel si to — tentýž vzor jako u odpovědí.
    func setPullRequestComment(_ text: String, for pr: PRIdentifier) {
        pullRequestComments[pr] = text.isEmpty ? nil : text
    }

    func pullRequestCommentState(for pr: PRIdentifier) -> CommentActionState? {
        pullRequestCommentStates[pr]
    }

    /// Odešle rozepsaný komentář do diskuze pod PR a připíše ho do konverzace.
    ///
    /// Text se po úspěchu maže, po selhání **zůstává** — tatáž pojistka jako u odpovědi do
    /// vlákna: rozepsaná věta se nesmí ztratit kvůli chvilkovému výpadku.
    ///
    /// **Není to review** a nesmí se s ním splést: nejde tudy verdikt, nic se nepotvrzuje
    /// a v panelu `Moje review` se nic neobjeví. Odesílá se tou samou jedinou cestou ven
    /// (`ReviewPublishing`), jen jinou metodou.
    func sendPullRequestComment(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        let body = pullRequestComments[id] ?? ""
        guard let submission = commentSubmission(for: id) else { return }
        // Dvojklik: druhé odeslání by bylo druhý komentář, ne oprava prvního. Kontrola leží
        // **před** prvním `await`, takže mezi nimi není mezera, do které by se závod vešel.
        guard pullRequestCommentStates[id]?.isBusy != true else { return }
        pullRequestCommentStates[id] = .sending

        do {
            let comment = try await submission.send(body)
            pullRequestCommentStates[id] = nil
            pullRequestComments[id] = nil
            append(comment, to: pullRequest)
        } catch let error as PublishError {
            pullRequestCommentStates[id] = .failed(error)
        } catch {
            pullRequestCommentStates[id] = .failed(.unknown(error.localizedDescription))
        }
    }

    /// Připíše odeslaný komentář do načtené konverzace, ať je vidět bez kola po síti.
    ///
    /// Když konverzace načtená **není** (composer je vidět i nad prázdnou osou), načte se —
    /// odeslaný komentář, který se nemá kde ukázat, vypadá jako neodeslaný.
    private func append(_ comment: ThreadComment, to pullRequest: PullRequestSummary) {
        let id = pullRequest.id
        guard case .loaded(let conversation, let updatedAt) = conversationStates[id] else {
            Task { await refreshConversation(for: pullRequest) }
            return
        }
        conversationStates[id] = .loaded(
            Policy.appending(comment, to: conversation),
            updatedAt: updatedAt
        )
    }

    /// Publisher se tu **nevyrábí** — jen se předá `gh`, read-only gateway a brána. Vzniká až
    /// uvnitř `CommentSubmission`, viz tvrdá podmínka č. 1.
    private func commentSubmission(for pr: PRIdentifier) -> CommentSubmission? {
        guard let gh else { return nil }
        return CommentSubmission(pullRequest: pr, gh: gh, gateway: gateway, scope: publishScope)
    }

    /// Publisher se tu **nevyrábí** — jen se předá `gh`, read-only gateway a brána. Vzniká až
    /// uvnitř `ThreadSubmission`, viz tvrdá podmínka č. 1.
    private func threadSubmission(
        for threadID: String,
        in pr: PRIdentifier
    ) -> ThreadSubmission? {
        guard let gh else { return nil }
        return ThreadSubmission(
            target: ThreadTarget(pullRequest: pr, threadID: threadID),
            gh: gh,
            gateway: gateway,
            scope: publishScope
        )
    }

    /// Vloží odeslanou odpověď do načtené konverzace, ať je vidět bez kola po síti.
    ///
    /// Když vlákno v konverzaci **není** (mezitím se obnovila, nebo ho někdo smazal), konverzace
    /// se načte znovu: odeslaný komentář, který se nemá kde ukázat, vypadá jako neodeslaný.
    private func insert(
        _ comment: ThreadComment,
        intoThread threadID: String,
        of pullRequest: PullRequestSummary
    ) {
        let id = pullRequest.id
        guard case .loaded(let conversation, let updatedAt) = conversationStates[id],
              let updated = Policy.inserting(comment, intoThread: threadID, of: conversation)
        else {
            Task { await refreshConversation(for: pullRequest) }
            return
        }
        conversationStates[id] = .loaded(updated, updatedAt: updatedAt)
    }

    private func apply(_ resolution: ThreadResolution, of pullRequest: PullRequestSummary) {
        let id = pullRequest.id
        guard case .loaded(let conversation, let updatedAt) = conversationStates[id],
              let updated = Policy.applying(resolution, to: conversation)
        else {
            Task { await refreshConversation(for: pullRequest) }
            return
        }
        conversationStates[id] = .loaded(updated, updatedAt: updatedAt)
    }

    func toggleThread(_ thread: ReviewThread, in pr: PRIdentifier) {
        var toggled = toggledThreads[pr] ?? []
        if toggled.contains(thread.id) {
            toggled.remove(thread.id)
        } else {
            toggled.insert(thread.id)
        }
        // Prázdná množina se maže, ať v mapě nezůstávají klíče bez obsahu.
        toggledThreads[pr] = toggled.isEmpty ? nil : toggled
    }
}
