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

        if visitSnapshots[pullRequest] == nil {
            // `Date.distantPast` u PR, který jsem nikdy neviděl, **nepoužíváme** — `nil` z
            // ledgeru propadne do snapshotu jako „nevím“ a změny pak vyjdou prázdné.
            // Ukázat při prvním otevření celou historii PR by nebylo „co je nového“.
            visitSnapshots[pullRequest] = visits.lastVisit(to: pullRequest) ?? time.now
        }
        visits.record(pullRequest, at: time.now)
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
        visitSnapshots[previous] = time.now
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
        visitSnapshots[pullRequest] = time.now
        visits.record(pullRequest, at: time.now)
    }
}
