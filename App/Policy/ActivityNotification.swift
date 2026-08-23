import Foundation

extension Policy {
    /// Notifikace o cizí aktivitě na **vlastním** PR (#335). `nil` = není o čem dát vědět.
    ///
    /// **Vlastní cesta, ne oživení `reviewNotification`** (#332): ta odpovídá na review request
    /// a o vlastním PR schválně nehlásí nic. Tohle je opačný směr — na mém PR se ozval někdo jiný —
    /// takže má vlastní text, vlastní přepínač v nastavení a vlastní `replacementGroup`: že mi
    /// kolega odpověděl, nemá přebít výsledek review a naopak.
    ///
    /// Rozvržení je **titulek → detail → PR** jako u ostatních (#200): banner se čte odshora a dolní
    /// řádek se ořízne, takže nahoře stojí to, podle čeho se člověk rozhoduje, jestli jít
    /// k počítači (kolik a čeho), pod tím ta nejnovější věta a teprve na třetím řádku identifikace.
    ///
    /// **Že se hlásí jedině vlastní PR, tady bránu nemá** — a je to schválně: „cizí aktivita“ se
    /// pozná z toho, čí je PR, a to ví jedině store (`ownership(of:)`), který tuhle funkci volá.
    /// Druhá kontrola nad `PullRequestOwnership` by znamenala parametr, který se dá zapomenout,
    /// za bránu, kterou drží už rozhlídka (`Policy.activitySweep` sahá jen na `.mine`).
    static func activityNotification(
        for pr: PRIdentifier,
        activity: ForeignActivity
    ) -> PullRequestNotification? {
        guard let title = activityHeadline(activity) else { return nil }
        return PullRequestNotification(
            pullRequest: pr,
            title: title,
            body: [activityDetail(activity), pr.description].compactMap { $0 }.joined(separator: "\n"),
            event: .activity
        )
    }

    /// `2 nové komentáře`, `1 nové review`, `2 nové komentáře a 1 review`. `nil` = nic nepřibylo.
    ///
    /// **Jedno místo pro banner i pro řádek seznamu.** Řádek si za to připíše `od minule`
    /// (`PullRequestRow.activityLine`), ale počet a slovo jsou tatáž věta — dvě implementace by se
    /// rozešly, jako se to stalo u skloňování blokujících nálezů (nález Copilota na #131).
    ///
    /// U review se **přídavné jméno v druhé půlce vynechává** (`a 1 review`, ne `a 1 nové review`):
    /// „nové“ platí pro obojí a dvakrát v jedné větě se čte jako dvě různá tvrzení. Slovo `review`
    /// se v češtině neskloňuje, takže jsou všechny tři tvary shodné záměrně — `Plural` se přesto
    /// použije, protože formátuje číslo přes locale.
    static func activityHeadline(_ activity: ForeignActivity) -> String? {
        let comments = activity.comments.count
        let reviews = activity.reviews.count
        switch (comments, reviews) {
        case (0, 0):
            return nil
        case (_, 0):
            return commentCount(comments)
        case (0, _):
            return Plural.czech(reviews, one: "nové review", few: "nová review", many: "nových review")
        default:
            let listed = Plural.czech(reviews, one: "review", few: "review", many: "review")
            return "\(commentCount(comments)) a \(listed)"
        }
    }

    private static func commentCount(_ count: Int) -> String {
        Plural.czech(count, one: "nový komentář", few: "nové komentáře", many: "nových komentářů")
    }

    /// Druhý řádek: **ta nejnovější věta**, ne souhrn. `nil` = není co dodat.
    ///
    /// Rozhoduje datum, ne druh — jinak by u PR, kde kolega odpověděl **po** Copilotovi, stálo
    /// v banneru starší review a novější odpověď by se nikde neukázala.
    ///
    /// Krátí se **tímtéž řezem jako nález** (`Policy.shortenedForBanner`): banner má čtyři řádky těla po
    /// zhruba 43 znacích (změřeno u #200) a na tom čtvrtém musí zbýt PR. Dvě různé délky by
    /// znamenaly, že u jedné z hlášek zmizí identifikace.
    ///
    /// **Není `private`, protože ho bere i řádek v dění** (#414) — tam je to naopak headline, protože
    /// v seznamu se řádek pozná podle věty, kdežto banner se čte odshora a nahoru patří počet.
    static func activityDetail(_ activity: ForeignActivity) -> String? {
        let newestComment = activity.comments.max { $0.createdAt < $1.createdAt }
        let newestReview = activity.reviews.max {
            ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast)
        }
        guard let comment = newestComment else { return newestReview.map(reviewLine) }
        guard let review = newestReview, let submitted = review.submittedAt else {
            return commentLine(comment)
        }
        return submitted > comment.createdAt ? reviewLine(review) : commentLine(comment)
    }

    /// `odinuv: opravdu to potřebuje ten mutex?` — autor před dvojtečkou, protože kdo to napsal,
    /// rozhoduje o naléhavosti stejně jako obsah.
    ///
    /// Prázdné tělo (komentář jen s obrázkem) nechá **samotného autora**: visící dvojtečka vypadá
    /// jako uříznutý text.
    private static func commentLine(_ comment: ThreadComment) -> String {
        let text = comment.body.singleLine
        return text.isEmpty ? comment.author : shortenedForBanner("\(comment.author): \(text)")
    }

    /// `Copilot vyžádal změny` — u review nese větu **verdikt**, ne próza: ta je v okně
    /// a rozhodnutí, jestli jít k počítači, plyne z verdiktu.
    private static func reviewLine(_ review: SubmittedReview) -> String {
        "\(review.author) \(reviewVerb(review.state))"
    }

    /// Sloveso do věty. Bere se z **modelu** (`SubmittedReview.State.czechLabel`) tam, kde slovesem
    /// je — druhá tabulka týchž slov by se s tou první rozešla. `dismissed` a neznámý stav se
    /// srážejí na `napsal review`, protože „zamítnuté review“ **sloveso není** a věta by zněla
    /// `odinuv zamítnuté review`.
    private static func reviewVerb(_ state: SubmittedReview.State?) -> String {
        guard let state else { return "napsal review" }
        switch state {
        case .approved, .changesRequested, .commented: return state.czechLabel
        case .dismissed, .pending: return "napsal review"
        }
    }
}
