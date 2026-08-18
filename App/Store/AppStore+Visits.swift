import Foundation

extension AppStore {
    /// Zaznamená, že se na PR zrovna dívám (#173).
    ///
    /// Volá se při zobrazení detailu a dělá tři věci:
    ///
    /// 1. **Uzavře předchozí PR.** Odejít jinam a vrátit se je nová návštěva, takže se banner
    ///    podruhé neukazuje — během té první jsem ho měl na obrazovce. Uvnitř jednoho PR se
    ///    ale snapshot nemění, takže odskok do `Změněných souborů` a zpátky o něj nepřipraví.
    /// 2. **Snapshot** — proti čemu se počítá „od minule“. Nastaví se jen **poprvé** za sezení
    ///    u toho PR; je to tentýž vzor jako odznaky `nové` u novinek (#127).
    /// 3. **Zápis návštěvy** — hned, ne až při odchodu. Zavření okna ani pád aplikace se
    ///    nedají odchytit spolehlivě, takže odložený zápis by znamenal, že se návštěva někdy
    ///    ztratí a banner ukáže totéž znovu.
    func noteVisit(to pullRequest: PRIdentifier) {
        closeVisit(leaving: pullRequest)
        openedPullRequest = pullRequest
        seedVisitBaseline(for: pullRequest)
        visits.record(pullRequest, at: time.now)
    }

    /// Založí značku „od minule“, aniž by zapsala návštěvu (#335).
    ///
    /// Dvě volání: `noteVisit` (a tam je zápis návštěvy hned za tím) a **rozhlídka po cizí
    /// aktivitě**, která si o konverzaci vlastních PR řekne sama na pozadí. Dotažení konverzace
    /// návštěva **není** — kdyby se zapsala, značka by se posunula na „teď“ a řádek by o komentáři
    /// kolegy mlčel, protože by vyšel jako starší než ta návštěva.
    ///
    /// Nastavuje se jen **poprvé** za sezení u toho PR; je to tentýž vzor jako odznaky `nové`
    /// u novinek (#127) a drží ho podmínka `visitSnapshots[pullRequest] == nil`.
    func seedVisitBaseline(for pullRequest: PRIdentifier) {
        guard visitSnapshots[pullRequest] == nil else { return }
        let previous = visits.lastVisit(to: pullRequest)
        // `Date.distantPast` u PR, který jsem nikdy neviděl, **nepoužíváme** — `nil` z
        // ledgeru propadne do snapshotu jako „nevím“ a změny pak vyjdou prázdné.
        // Ukázat při prvním otevření celou historii PR by nebylo „co je nového“.
        visitSnapshots[pullRequest] = previous?.at ?? time.now
        // Klíč se zakládá, jen když hlavu **známe** — viz `seenHeads`.
        if let head = previous?.head { seenHeads[pullRequest] = head }
    }

    /// Doplní hlavu, kterou jsem u PR viděl (#173).
    ///
    /// Volá se, až když se načte detail — `noteVisit` běží dřív a `headSha` v tu chvíli není.
    /// Ukládá se proto, že **datum commitu nestačí**: `TimelineEvent.at` je u commitu
    /// `committedDate`, ne čas pushnutí (`pushedDate` GitHub neplní, změřeno u #171), takže po
    /// rebase nebo cherry-picku je starší než moje návštěva a commit by z „od minule“ vypadl.
    /// Porovnání sha na to nesáhne — buď se hlava posunula, nebo ne.
    func noteHead(_ head: String, for pullRequest: PRIdentifier) {
        visits.record(pullRequest, at: time.now, head: head)
    }

    /// Posunula se od minule hlava PR? Vrací **novou** hlavu, jinak `nil`.
    ///
    /// `nil` i tehdy, když jsem minulou hlavu neviděl (stará návštěva bez `head`, nebo první
    /// otevření): tvrdit „posunulo se“ proti něčemu, co neznám, by byla výmluva, ne informace.
    func movedHead(for pullRequest: PRIdentifier) -> String? {
        guard
            let seen = seenHeads[pullRequest],
            case .loaded(let detail, _) = detailState(for: pullRequest),
            detail.headSha != seen
        else { return nil }
        return detail.headSha
    }

    /// Posune značku u PR, ze kterého jsem právě odešel — ale **jen když se konverzace stihla
    /// načíst**.
    ///
    /// Bez té podmínky by seznam projetý šipkami spotřeboval bannery všech PR, přes které jsem
    /// přejel: každý se na okamžik zobrazí, a kdyby to stačilo, „viděl jsem to“ by byla lež.
    /// Načtená konverzace je jediný signál, který o tom aplikace má — bez ní se banner nemá
    /// z čeho vykreslit, takže na obrazovce nebyl.
    private func closeVisit(leaving pullRequest: PRIdentifier) {
        guard
            let previous = openedPullRequest,
            previous != pullRequest,
            conversation(for: previous) != nil
        else { return }
        moveBaseline(for: previous)
    }

    /// Posune **obě** baseline naráz — čas i hlavu — a zapíše je i na disk.
    ///
    /// Kdekoli se posouvá jedna, musí se posunout druhá. Banner totiž stojí na obou (`changes`
    /// z času, „hlava se posunula“ ze sha), takže po posunutí jen jedné z nich zůstane viset
    /// kvůli té zapomenuté — a „přečteno“ nebo „návrat je nová návštěva“ přestane platit
    /// v přesně tom případě, kvůli kterému sha vůbec existuje: po rebase, kde časová osa mlčí.
    ///
    /// Hlava se posouvá jen tehdy, když je **detail načtený**: bez něj se nedá zapsat nic
    /// pravdivého a přepsat ji na `nil` by znamenalo zahodit, co víme.
    private func moveBaseline(for pullRequest: PRIdentifier) {
        visitSnapshots[pullRequest] = time.now

        guard case .loaded(let detail, _) = detailState(for: pullRequest) else {
            visits.record(pullRequest, at: time.now)
            return
        }
        seenHeads[pullRequest] = detail.headSha
        visits.record(pullRequest, at: time.now, head: detail.headSha)
    }

    /// Co na PR přibylo od poslední návštěvy. Prázdné, dokud se nenačte konverzace — banner
    /// se do té doby nemá o co opřít a „nic nového“ by nad nenačtenými daty bylo tvrzení,
    /// které data neunesou.
    func changesSinceLastVisit(for pullRequest: PRIdentifier) -> VisitChanges {
        Policy.changes(
            in: conversation(for: pullRequest),
            since: visitSnapshots[pullRequest]
        )
    }

    /// „Přečteno“ — posune značku, proti které se počítá, na teď (#173).
    ///
    /// Bez toho by banner visel celou dobu, co je aplikace spuštěná: snapshot se schválně
    /// nemění sám, aby informace nezmizela dřív, než ji stihnu přečíst. To je správně napoprvé
    /// a špatně napopáté — při třetím návratu na tentýž PR už jenom ubírá místo a „od tvé
    /// poslední návštěvy“ v něm přestává být pravda, protože jsem tu mezitím byl.
    ///
    /// Zavření je proto **rozhodnutí člověka**, ne časovač. Nic se tím nezahazuje: co přibude
    /// potom, se objeví znovu.
    func markChangesAsSeen(for pullRequest: PRIdentifier) {
        moveBaseline(for: pullRequest)
    }
}
