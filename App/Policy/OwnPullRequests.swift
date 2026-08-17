import Foundation

extension Policy {
    /// Seznam zúžený na jednu stranu — moje PR, nebo cizí (#331).
    ///
    /// **Další zúžení nad tím, co seznam už má**, ne nový zdroj pravdy: čte to jedině sekce
    /// `Moje PR` a blok na dashboardu, tedy tatáž místa, která smí sahat na zúžený seznam
    /// (viz `AppStore.pullRequests`). Kdyby na rozřazení viselo cokoli z úklidu, přihlášení
    /// jiným účtem by zahodilo cache.
    ///
    /// **Nesahá na řazení** — jako `filtered(_:by:)`: pořadí je od naposledy změněného
    /// a rozhodnutí o něm patří jinam.
    static func pullRequests(
        _ pullRequests: [PullRequestSummary],
        ownedBy ownership: PullRequestOwnership,
        mine: Set<String>
    ) -> [PullRequestSummary] {
        pullRequests.filter { self.ownership(of: $0, mine: mine) == ownership }
    }

    /// Proč je sekce `Moje PR` prázdná (#331).
    ///
    /// Vlastní funkce vedle `listEmptyReason(poll:visible:hidden:)`, protože se rozhoduje mezi
    /// **třemi různými prázdny navíc**: nenastavený zdroj, nenačtený login a „nic otevřeného
    /// nemáš“. Věta „nic tu není“ nad aplikací, která vlastní PR vůbec nestahuje, je ta nejhorší
    /// možná odpověď — vypadá jako hotová práce.
    ///
    /// Pořadí důvodů (od nejsilnějšího):
    ///
    /// 1. **Chyba nebo rozdělané načtení od pollingu** — nad daty, která nedorazila, se o zdrojích
    ///    ani o loginu nedá tvrdit nic; tatáž úvaha jako u `listEmptyReason`.
    /// 2. **Chybějící zdroj** (`tracksOwnPullRequests == false`) — vlastní PR nemají kudy přijít,
    ///    takže je to vysvětlení i tehdy, když tik nevrátil vůbec nic.
    /// 3. **Nenačtený login** — bez něj je podle `ownership(ofAuthor:mine:)` všechno cizí, takže
    ///    prázdná sekce neznamená „nic nemám“, ale „nevím, kdo jsem“.
    /// 4. **Filtr**, který moje PR schoval — ať je z toho stavu vidět cesta zpátky.
    /// 5. **Nic otevřeného**, tedy ten dobrý stav.
    ///
    /// Případ `poll(.noPullRequests)` odsud **nevypadne nikdy**: prázdný seznam je pro tuhle sekci
    /// otázka zdroje, loginu a autora, ne pollingu — a „Žádné PR k review“ o vlastních PR nemluví.
    static func ownListEmptyReason(
        poll: PollEmptyReason?,
        tracksOwnSource: Bool,
        knowsViewer: Bool,
        visible: Int,
        hidden: Int
    ) -> ListEmptyReason? {
        if let poll, poll != .noPullRequests { return .poll(poll) }
        guard visible == 0 else { return nil }
        if !tracksOwnSource { return .ownSourceMissing }
        if !knowsViewer { return .unknownViewer }
        if hidden > 0 { return .filtered(hidden: hidden) }
        return .noOwnPullRequests
    }

    /// Kolik vlastních PR **čeká na můj tah** (#331) — obsah odznaku u sekce `Moje PR`.
    ///
    /// **Ne počet otevřených PR.** Šest PR, ze kterých pět čeká na CI, není šest věcí k práci,
    /// a odznak na railu znamená „je co dělat“. Počítá se tedy PR, na kterém leží **nezpracovaný
    /// nález** nebo **nevyřešené cizí vlákno**.
    ///
    /// **Je to spodní hranice, ne přesný počet, a je to vidět z parametru.** Nálezy jsou
    /// v paměti vždycky (záznamy se čtou při startu), kdežto konverzace jsou jen u PR, které se
    /// **načetly** — a ty se tahají při výběru řádku, ne při pollingu (jinak by byl jeden tik
    /// N podprocesů). PR, do kterého se ještě nekliklo, tedy vláknem nepřispěje. Neúplnost je
    /// schválně **v tomhle směru**: odznak, který napočítá víc práce, než jí je, se přestane čítat,
    /// kdežto tenhle o práci nelže — jen o části z ní ještě neví. Cizí aktivitu na vlastních PR
    /// dotáhne #335.
    ///
    /// Konverzace se berou **uzávěrem, ne slovníkem**, a je to kvůli tomu, odkud se to volá: odznak
    /// v railu čte SwiftUI při **každém překreslení okna**, takže složit pro něj mapu všech
    /// načtených konverzací by bylo kopírování celé diskuze za odpověď, která se ptá jen na vlastní
    /// PR. Uzávěr sáhne na ty, kterých se to týká.
    static func ownPullRequestsAwaitingMove(
        _ pullRequests: [PullRequestSummary],
        records: [PRIdentifier: ReviewRecord],
        conversation: (PRIdentifier) -> Conversation? = { _ in nil }
    ) -> Int {
        pullRequests.count {
            awaitsMyMove(records[$0.id], conversation: conversation($0.id))
        }
    }

    /// Čeká na tomhle vlastním PR můj tah?
    ///
    /// **Nezpracovaný nález** je nález, který platí — tedy `activeFindings`, bez odmítnutých
    /// (#113). Razítko předání zatím neexistuje, takže „nezpracovaný“ dneska znamená „nikdo ho
    /// neodmítl“; jak přijde předání agentovi (#333) a jeho razítko (#334), zúží se to tady,
    /// na jednom místě.
    ///
    /// **Cizí vlákno** je vlákno, ve kterém je aspoň jeden komentář někoho jiného, a **není
    /// vyřešené**. Ne „vlákno, které někdo jiný založil“: vlákno, do kterého kolega odpověděl,
    /// po mně chce odpověď stejně jako to, které začal. **Zastaralá vlákna se počítají** —
    /// zmizelá kotva je věc dnešního diffu, ne diskuze, a nevyřešená diskuze zůstává nevyřešená.
    static func awaitsMyMove(_ record: ReviewRecord?, conversation: Conversation?) -> Bool {
        if let record, !record.activeFindings.isEmpty { return true }
        guard let conversation else { return false }
        return conversation.threads.items.contains { thread in
            !thread.isResolved && thread.comments.items.contains { !conversation.isMine($0) }
        }
    }
}
