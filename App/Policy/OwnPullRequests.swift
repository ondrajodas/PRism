import Foundation

extension Policy {
    /// Seznam zúžený na jednu stranu — moje PR, nebo cizí (#331).
    ///
    /// **Další zúžení nad tím, co seznam už má**, ne nový zdroj pravdy. Od #332 na něm stojí obě
    /// fronty: `.mine` je sekce `Moje PR` a její blok, `.theirs` je fronta, karty `Čeká na mě`
    /// a `Blokuje`, souhrn ve stavovém řádku, automat a notifikace.
    ///
    /// **Co na něm viset nesmí, je úklid** (`forget(whatIsNotIn:)`, `CacheEviction`,
    /// `ReviewStore.cleanUp`) **a okno nastavení** (`knownRepositories`) — ty čtou plný seznam
    /// (viz `AppStore.pullRequests`). Klon vlastního PR zabírá místo stejně jako cizí, takže
    /// navázat úklid na zúženou množinu znamená cache, která tiše roste; a přihlášení jiným účtem
    /// by z ní naráz udělalo „cizí“ všechno.
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

    /// Kolik vlastních PR **čeká na můj tah** (#331, otázka změněná #334) — obsah odznaku
    /// u sekce `Moje PR`.
    ///
    /// **Ne počet otevřených PR.** Šest PR, ze kterých pět čeká na CI, není šest věcí k práci,
    /// a odznak na railu znamená „je co dělat“.
    ///
    /// **Od #334 se ptá „zbývá tu ještě něco, co jsem nepředal?“, ne „je tu něco?“** Rozhoduje
    /// `Policy.handoff(_:record:conversation:head:commits:)`, tedy tatáž funkce, ze které čte
    /// pilulka `N k předání` v řádku i panel `Zadání` — jinak by odznak svítil nad řádkem, který
    /// tvrdí, že je hotovo. Do #334 to bylo „nezpracovaný nález nebo nevyřešené cizí vlákno“,
    /// takže odznak svítil pořád stejně i deset minut po zkopírování promptu.
    ///
    /// **Je to spodní hranice, ne přesný počet, a je to vidět z parametrů.** Nálezy jsou v paměti
    /// vždycky (záznamy se čtou při startu), kdežto konverzace a hlava PR jsou jen u PR, které se
    /// **načetly** — a ty se tahají při výběru řádku, ne pollingem (jinak by byl jeden tik N
    /// podprocesů). PR, do kterého se ještě nekliklo, tedy vláknem nepřispěje a o pushnutém commitu
    /// se odsud neví. Neúplnost je schválně **v tomhle směru**: odznak, který napočítá víc práce,
    /// než jí je, se přestane čítat, kdežto tenhle o práci nelže — jen o části z ní ještě neví.
    /// Cizí aktivitu na vlastních PR dotáhne #335.
    ///
    /// Konverzace, razítka i hlavy se berou **uzávěry, ne slovníky**, a je to kvůli tomu, odkud se
    /// to volá: odznak v railu čte SwiftUI při **každém překreslení okna**, takže složit pro něj
    /// mapu všech načtených konverzací by bylo kopírování celé diskuze za odpověď, která se ptá jen
    /// na vlastní PR. Uzávěr sáhne na ty, kterých se to týká.
    static func ownPullRequestsAwaitingMove(
        _ pullRequests: [PullRequestSummary],
        records: [PRIdentifier: ReviewRecord],
        conversation: (PRIdentifier) -> Conversation? = { _ in nil },
        handoff: (PRIdentifier) -> Handoff? = { _ in nil },
        head: (PRIdentifier) -> String? = { _ in nil }
    ) -> Int {
        pullRequests.count { summary in
            Policy.handoff(
                handoff(summary.id),
                record: records[summary.id],
                conversation: conversation(summary.id),
                head: head(summary.id)
            )
            .awaitsMove
        }
    }
}
