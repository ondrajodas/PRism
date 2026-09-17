import Foundation

/// Druhé kolo na obrazovce (#523) — karta `Odpověď na tvoje review`, předepsané schválení
/// a hláška o tom, co autor s mými komentáři udělal.
///
/// **Nic se tudy neodesílá.** `prescribeReplyApproval(for:)` sáhne na `ReviewDraft`, tedy na
/// soubor v cache, a otevření potvrzení zůstává na view — odeslat smí dál jedině
/// `ReviewPublishing` na výslovný pokyn a s potvrzením (tvrdá podmínka č. 1).
extension AppStore {
    /// Co se nakreslí na kartě druhého kola. `nil` = nekreslí se.
    ///
    /// Skládá se **při čtení, ne při běhu kontroly**: osa „odpovězeno“ je živá konverzace (#522),
    /// takže uložená karta by od posledního běhu lhala o tom, na co mezitím kolega odpověděl.
    func replyCard(for pr: PRIdentifier) -> ReviewReplyCard? {
        Policy.replyCard(
            reviewReplyReport(for: pr),
            ownership: ownership(of: pr),
            reviewedAt: Policy.lastOwnReviewDate(in: conversation(for: pr))
        )
    }

    /// Předepíše schválení do rozdělaného review (#523). **Neodesílá nic.**
    ///
    /// Dělá právě dvě věci a obě jsou zápis do draftu, tedy do souboru v cache: doplní verdikt
    /// `APPROVE` a — **jen když je tělo prázdné** — předepsanou větu. Potvrzení otevírá volající
    /// (`ReviewSubmission` ze `submission(for:)`), takže cesta ven zůstává tatáž jako u tlačítka
    /// `Odeslat` v panelu: sheet s celým payloadem a dvě kliknutí.
    ///
    /// **Rozepsaná věta má přednost** (`Policy.prescribedBody`): kdyby ji předpis přepsal, ztratil
    /// by se text, který je jediný svého druhu — nálezy se dají spustit znovu, moje próza ne.
    ///
    /// Bez karty se nestane nic: na vlastním PR se schválení nenabízí vůbec (GitHub ho odmítne),
    /// takže by to byl zápis do draftu za tlačítko, které tam není.
    func prescribeReplyApproval(for pr: PRIdentifier) {
        guard let card = replyCard(for: pr) else { return }
        mutateDraft(for: pr) { draft in
            draft.body = Policy.prescribedBody(existing: draft.body, prescribed: card.approvalBody)
            draft.verdict = .approve
        }
        // Ať je vidět, co se předepsalo, **dřív** než se otevře potvrzení — po jeho zavření
        // (zrušením i odesláním) zůstane člověk v tabu, kde ten text je.
        revealDraft(in: pr)
    }

    /// Otevře vlákno, které v druhém kole zbývá (#523).
    ///
    /// **Přepne do `Konverzace` a vlákno rozbalí** — cíl, na kterém není co přečíst, je
    /// k nerozeznání od skoku, který se nepovedl (tatáž úvaha jako u `revealFinding`). Vyřešené
    /// vlákno je sbalené ve výchozím stavu, takže se rozbaluje tím samým přepínačem, kterým se
    /// sbaluje nevyřešené — rozhoduje `Policy.isThreadExpanded`.
    func revealReplyThread(_ threadID: String, in pr: PRIdentifier) {
        setDetailTab(.conversation, for: pr)
        guard let thread = conversation(for: pr)?.threads.items.first(where: { $0.id == threadID })
        else { return }
        guard !isThreadExpanded(thread, in: pr) else { return }
        toggleThread(thread, in: pr)
    }

    /// Dá vědět, co autor s mými komentáři udělal (#523).
    ///
    /// Volá se **tam, kde kontrola končí**: dřív se osa `opraveno` nemá odkud vzít a později by to
    /// znamenalo druhý spouštěč nad týmiž daty. Kdy se nehlásí nic, rozhoduje `Policy` — vlastní
    /// PR, žádné moje vlákno, nebo běh, po kterém se nic nepohnulo.
    ///
    /// **Guard na notifikační centrum je až dole** (#414): do dění se zapisuje i tehdy, když se
    /// odsud neposílá nebo když je hláška vypnutá — přepínače rozhodují o vyrušení, ne o záznamu.
    /// Odložený PR nezazvoní (#512) a řádek přesto dostane, jako u doběhlého review.
    func notifyAboutReplyRound(on pr: PRIdentifier) async {
        let ownership = ownership(of: pr)
        let author = author(of: pr)
        let report = reviewReplyReport(for: pr)
        let notification = Policy.replyRoundNotification(
            for: pr,
            ownership: ownership,
            author: author,
            report: report
        )
        var delivery: NotificationDelivery?
        if let notification, !isSnoozed(pr) { delivery = await notify(notification) }
        await recordActivity(Policy.replyRoundActivity(
            for: pr,
            ownership: ownership,
            author: author,
            report: report,
            at: time.now,
            announced: delivery?.isDelivered == true
        ))
    }
}
