import Foundation

/// Odkud se bere **můj hlas** pro osmou session (#521). Čisté funkce, žádné I/O.
extension Policy {
    /// Kolik posledních těl review se pamatuje a posílá do zadání. **Deset**, jak je v zadání
    /// #521 — a je to strop na obojí naráz, tedy i na to, co leží v cache.
    ///
    /// Že je to totéž číslo, je rozhodnutí: pamatovat si víc, než se posílá, by znamenalo držet
    /// v cache text, na který se nikdo nikdy nepodívá.
    static let reviewVoiceLimit = 10

    /// Nejkratší tělo, které se ještě bere jako vzorek hlasu.
    ///
    /// **Schválení bez komentáře je čtvrtina vzorku** (`cli/cli#11451`, viz `SubmittedReview.body`),
    /// takže by prázdná a jednoslovná těla vytlačila z desítky ta, ze kterých se hlas doopravdy dá
    /// přečíst — a session by dostala deset vzorků, ve kterých není co napodobit. `LGTM` se navíc
    /// jako vzor **odeslat nedá**: tělo, které jen odsouhlasí, nad třemi nálezy neplatí.
    static let reviewVoiceMinimum = 40

    /// Moje odeslaná review z načtené konverzace — vzorky hlasu, nic jiného (#521).
    ///
    /// **Filtruje se to na třech věcech a každá z nich je vlastní tvrzení:**
    ///
    /// 1. **Je to moje** (`Conversation.isMine`). Cizí prózou se hlas napodobit nedá a vzorek od
    ///    kolegy by z návrhu udělal text, který jsem nikdy nenapsal.
    /// 2. **Je odeslané** (`submittedAt != nil`). Rozdělané (`pending`) review je moje rozepsaná
    ///    věta, ne hotový text — a hlavně se ještě může celé změnit.
    /// 3. **Má co ukázat** (`reviewVoiceMinimum`). Viz ta konstanta.
    ///
    /// Stav review se **nefiltruje**: `APPROVED`, `CHANGES_REQUESTED` i `COMMENTED` jsou pořád
    /// moje próza a hlas je v nich týž. Zamítnuté (`DISMISSED`) taky — pozbylo verdikt, ne styl.
    static func reviewVoiceSamples(in conversation: Conversation) -> [ReviewVoiceSample] {
        conversation.reviews.items.compactMap { review in
            guard conversation.isMine(review), let at = review.submittedAt else { return nil }
            let body = review.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard body.count >= reviewVoiceMinimum else { return nil }
            return ReviewVoiceSample(id: review.id, at: at, body: body)
        }
    }

    /// Slije, co leží v cache, s tím, co právě dorazilo — **nejnovějších `limit`**.
    ///
    /// **Deduplikuje se podle `id`, ne podle textu**: totéž review přijde v konverzaci pokaždé,
    /// když se PR otevře. Novější zápis přebíjí starší, protože tělo review se dá na GitHubu
    /// **editovat** — a vzorek z doby před opravou by byl text, který už nikde nestojí.
    ///
    /// **Řadí se od nejnovějšího.** Pořadí je součástí odpovědi: session má v zadání číst nejdřív
    /// to, co jsem napsal naposled, protože hlas se v čase mění a nejnovější vzorek je ten
    /// nejpravdivější.
    static func mergedReviewVoice(
        _ stored: [ReviewVoiceSample],
        adding fresh: [ReviewVoiceSample],
        limit: Int = reviewVoiceLimit
    ) -> [ReviewVoiceSample] {
        var merged = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        for sample in fresh { merged[sample.id] = sample }
        return merged.values
            // Sekundárně podle `id`, aby dvě review odeslaná v tomtéž okamžiku (týž `submittedAt`
            // přijde u review odeslaných dávkou) vyšla pokaždé stejně — jinak by se desítka po
            // každém načtení přeskládala a zadání by se měnilo bez důvodu.
            .sorted { $0.at == $1.at ? $0.id > $1.id : $0.at > $1.at }
            .prefix(limit)
            .map { $0 }
    }
}
