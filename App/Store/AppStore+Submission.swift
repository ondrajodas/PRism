import Foundation

/// Odeslání review na GitHub (#67, #68) — jediná cesta ven ze storu.
///
/// **Publisher tady není a nesmí být.** Store si podle tvrdé podmínky č. 1 drží jen cestu
/// ke `gh`; `ReviewPublishing` se skládá až uvnitř `ReviewSubmission.send()` a zaniká s ním.
extension AppStore {
    /// Proč se rozdělané review nedá odeslat. `nil` = dá se.
    ///
    /// Věta z toho jde do okna: zakázané tlačítko bez důvodu vypadá jako rozbitá aplikace.
    ///
    /// **Proč hlavu neznáme, doplňuje store**, ne `Policy`: ta dostane jen `String?` a z něj
    /// nepozná rozdíl mezi „načítá se“ a „nepovedlo se to“. Slíbit „hned to bude“ nad chybou,
    /// která sama nezmizí, je přitom horší než mlčet.
    func draftSendBlock(for pr: PRIdentifier) -> DraftSendBlock? {
        let block = Policy.sendBlock(
            for: drafts[pr],
            head: head(of: pr),
            scope: publishScope,
            // Návrh z nálezů verdikt zastoupí (#114), takže `noVerdict` nesmí hlásit nic, co
            // by panel v tu chvíli ukazoval jako předvyplněné.
            suggestion: prefillableSuggestion(for: pr)
        )
        guard case .headUnknown = block, case .failed(let detail) = detailStates[pr] else {
            return block
        }
        return .headUnknown(detail: detail)
    }

    /// Návrh verdiktu z nálezů. `nil` = není z čeho soudit.
    ///
    /// V potvrzení odeslání stojí **vedle** odesílaného verdiktu, aby se dalo porovnat. Čím se
    /// předvyplňuje, říká `prefillableSuggestion(for:)` — na vlastním PR se návrh nenabízí,
    /// ale tady zůstává, protože „nálezy říkají approve“ je pravda i tam.
    func suggestedVerdict(for pr: PRIdentifier) -> ReviewVerdict? {
        guard let record = reviewRecords[pr] else { return nil }
        return Policy.suggestedVerdict(
            for: record,
            categories: resolved(for: pr.repo).blockingCategories
        )
    }

    /// Verdikt, který na PR **platí** — moje volba, jinak návrh z nálezů (#114).
    ///
    /// Panel z něj kreslí třetí stav („návrh z nálezů“, obtažený), odeslání ho doplní do
    /// snímku. **Nikam se neukládá**: draft na disku zůstává bez verdiktu, dokud na něj někdo
    /// neklikne, jinak by draft vznikl ze samotného otevření PR.
    func effectiveVerdict(for pr: PRIdentifier) -> EffectiveVerdict? {
        Policy.effectiveVerdict(of: drafts[pr], suggestion: prefillableSuggestion(for: pr))
    }

    /// Návrh, kterým se smí předvyplnit — na vlastním PR žádný.
    private func prefillableSuggestion(for pr: PRIdentifier) -> ReviewVerdict? {
        Policy.prefillableSuggestion(
            suggestedVerdict(for: pr),
            author: author(of: pr),
            viewer: conversation(for: pr)?.viewer
        )
    }

    /// Je to můj vlastní PR? `false`, dokud se nenačetla konverzace — kdo se dívá, je jen v ní.
    ///
    /// Panel z toho skládá větu o tom, že tam GitHub bere jedině `Jen komentář`; bez ní by
    /// nepředvyplněný verdikt vypadal jako chybějící návrh.
    ///
    /// Ptá se na **konverzaci**, ne na `viewer` z `gh` (#330): tady jde o to, co GitHub udělá
    /// s odeslaným review, a `Conversation.viewer` je tentýž login, jakým se v ní pozná „to jsem
    /// napsal já“. Rozřazení seznamu i brána na zakládání draftu jdou naopak přes
    /// `ownership(of:)` — ta odpověď musí být hotová dřív, než se stihne načíst konverzace.
    func isOwnPullRequest(_ pr: PRIdentifier) -> Bool {
        Policy.isOwn(author: author(of: pr), viewer: conversation(for: pr)?.viewer)
    }

    /// Složí jedno odeslání — snímek toho, co je teď v draftu.
    ///
    /// `nil` znamená „odeslat teď nejde“ a tlačítko, které to volá, je v takovém stavu
    /// zakázané; kontrola je tady podruhé proto, že sheet se nad zastaralým draftem **nemá
    /// otevřít vůbec** a spoléhat se na to, že si to view pohlídá, je o jedno místo k
    /// zapomenutí víc.
    ///
    /// Publisher se tu **nevyrábí** — jen se předá `gh` a read-only gateway. Vzniká až
    /// v `ReviewSubmission.send()`, viz tvrdá podmínka č. 1.
    func submission(for pullRequest: PullRequestSummary) -> ReviewSubmission? {
        let id = pullRequest.id
        guard let gh, let draft = drafts[id] else { return nil }
        // Zastaralý draft se **smí** otevřít, když je proti čemu ho zkontrolovat (#69): okno pak
        // začne kontrolou kotev a odeslání se odemkne až po přenesení. Zastarání je totiž jediný
        // důvod, se kterým se dá něco udělat právě tady — u chybějícího verdiktu nebo prázdného
        // komentáře patří oprava do panelu.
        let transfer = canTransferDraft(for: id)
        guard draftSendBlock(for: id) == nil || (transfer && draftSendBlock(for: id)?.isStale == true) else {
            return nil
        }
        // Verdikt, který odejde, může být **návrh** (#114). Do snímku se proto doplní tady:
        // „co je v potvrzení vidět, to se odešle“ platí dál, jen ta hodnota nepochází z disku.
        // Uložený draft ho nedostane — návrh se neukládá.
        let effective = effectiveVerdict(for: id)
        var snapshot = draft
        // Vlastní volba přebíjí návrh, takže `effective` nikdy neruší vybraný verdikt; `??` je
        // pojistka proti tomu, aby snímek o hodnotu přišel, kdyby se to rozešlo.
        snapshot.verdict = effective?.verdict ?? draft.verdict
        return ReviewSubmission(
            pullRequest: pullRequest,
            draft: snapshot,
            suggestion: suggestedVerdict(for: id),
            verdictOrigin: effective?.origin,
            anchors: transfer ? draftAnchorStates(for: id) : [],
            needsTransfer: transfer,
            targetHead: transfer ? head(of: id) : nil,
            gh: gh,
            gateway: gateway,
            scope: publishScope,
            afterSuccess: { [weak self] in await self?.draftWasSubmitted(for: pullRequest) },
            applyTransfer: { [weak self] choices in self?.transferDraft(for: id, choices: choices) }
        )
    }

    /// Brána na odesílání, složená **z aktuální konfigurace**.
    ///
    /// Čte se při použití, ne při startu — jako limit souběhu nebo rozpočet cache — takže
    /// přepnutí v okně nastavení platí bez restartu. Je to počítaná vlastnost schválně:
    /// uložený snímek by se s konfigurací rozešel.
    var publishScope: PublishScope { PublishScope(configuration: configuration) }

    /// Úklid po odeslaném review: draft je pryč a konverzace se načte znovu.
    ///
    /// Draft se maže **až tady**, tedy po potvrzené odpovědi GitHubu — selhání ho nechává
    /// netknutý, aby se dalo zkusit znovu bez psaní nanovo.
    ///
    /// Konverzace se obnovuje proto, že v ní od téhle chvíle leží moje vlastní review; bez
    /// toho by v tabu `Přehled` chybělo až do dalšího přepnutí PR. Cache jde podle
    /// `updatedAt`, které se odesláním review na GitHubu měnit nemusí, takže se zahazuje
    /// ručně (`refreshConversation`).
    func draftWasSubmitted(for pullRequest: PullRequestSummary) async {
        discardDraft(for: pullRequest.id)
        await refreshConversation(for: pullRequest)
    }

    /// Zahodí celé rozdělané review. Idempotentní — na tlačítko se dá zmáčknout dvakrát.
    func discardDraft(for pr: PRIdentifier) {
        guard drafts[pr] != nil else { return }
        drafts[pr] = nil
        persistDraft(for: pr)
    }

    /// Uloží draft na disk.
    ///
    /// Hodnota se čte **až v tasku**, ne teď: dvě rychlé úpravy za sebou tak zapíšou tentýž
    /// konečný stav a nezáleží na tom, v jakém pořadí se tasky provedou. Kdyby se draft
    /// zachytil do closure, pozdější task by mohl zapsat starší podobu.
    func persistDraft(for pr: PRIdentifier) {
        guard draftStore != nil else { return }
        Task { [weak self] in await self?.writeDraft(for: pr) }
    }

    private func writeDraft(for pr: PRIdentifier) async {
        guard let draftStore else { return }
        do {
            if let draft = drafts[pr] {
                try await draftStore.save(draft)
            } else {
                // Prázdný draft `save` maže sám, ale tady už v paměti není co uložit.
                try await draftStore.delete(for: pr)
            }
            draftFailure = nil
        } catch {
            draftFailure = "Rozdělané review se nepodařilo uložit. \(error.localizedDescription)"
        }
    }

}
