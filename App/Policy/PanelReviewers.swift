import Foundation

/// Kdo na pull requestu stojí a jak odpověděl (#392).
///
/// Je to **rozhodnutí, ne tvar odpovědi**, a proto to bydlí tady: GitHub dává dvě různá pole
/// (`reviewRequests` = komu to leží na stole teď, `latestReviews` = kdo už se vyjádřil) a sekce
/// v panelu je jejich sloučení do jednoho seznamu tří hodnot.
extension Policy {
    /// Jeden odeslaný verdikt, jak přišel z GitHubu.
    ///
    /// `state` je optional ze stejného důvodu jako u `SubmittedReview`: neznámou hodnotu se
    /// nehádáme a nepokládáme kvůli ní celou sekci.
    struct ReviewerVerdict: Hashable, Sendable {
        let login: String
        let state: SubmittedReview.State?

        init(login: String, state: SubmittedReview.State?) {
            self.login = login
            self.state = state
        }
    }

    /// Sekce `Reviewery`: kdo se v ní kreslí a s jakou odpovědí.
    ///
    /// Tři pravidla, a každé z nich je rozhodnutí:
    ///
    /// 1. **Vyžádání přebíjí starší verdikt.** Když GitHub review znovu vyžádá (typicky po
    ///    pushnutí opravy), je ten člověk zpátky v `reviewRequests` a jeho `CHANGES_REQUESTED`
    ///    z minula je odpověď na kód, který už tam není. Na otázku „na kom to stojí“ je správná
    ///    odpověď `čeká`.
    /// 2. **Kdo jen komentoval a vyžádaný není, v seznamu není.** `latestReviews` nese i review
    ///    bez verdiktu (`COMMENTED`, `DISMISSED`) a přijdou tam i od lidí, které nikdo nevyžádal —
    ///    typicky od review bota. Nakreslit je jako `čeká` by tvrdilo, že se na ně čeká, což není
    ///    pravda: neřekli ani ano, ani ne, a nikdo je nežádal. Rozhoduje `SubmittedReview.isVerdict`,
    ///    tedy tatáž funkce, podle které se verdikt počítá i na ose konverzace.
    /// 3. **Pořadí je podle odpovědi, ne podle toho, co přišlo první** (`schválil`, `chce změny`,
    ///    `čeká`), a při shodě podle loginu. Bez toho by se seznam přeskládal při každém načtení,
    ///    protože GitHub pořadí `latestReviews` nezaručuje — a přeskládaný seznam se nedá přečíst
    ///    dvakrát stejně.
    ///
    /// Prázdný výsledek je platná odpověď: PR bez vyžádaných reviewerů a bez verdiktů je běžný
    /// a sekce se pak nekreslí.
    static func reviewers(
        requested: [String],
        verdicts: [ReviewerVerdict]
    ) -> [RequestedReviewer] {
        // **Prázdný login se zahazuje.** Autora review může GitHub vynechat (smazaný účet) a řádek
        // bez jména se v panelu nedá odlišit od chyby kresby — a hlavně se nedá vyžádat.
        let waiting = Set(requested.filter { !$0.isEmpty })
        var answers: [String: ReviewerAnswer] = [:]

        for verdict in verdicts where !waiting.contains(verdict.login) && !verdict.login.isEmpty {
            switch verdict.state {
            case .approved: answers[verdict.login] = .approved
            case .changesRequested: answers[verdict.login] = .changesRequested
            // Bez verdiktu se do seznamu nedostane — viz pravidlo 2.
            case .commented, .dismissed, .pending, nil: continue
            }
        }
        for login in waiting {
            answers[login] = .waiting
        }

        let order = Dictionary(
            uniqueKeysWithValues: ReviewerAnswer.allCases.enumerated().map { ($1, $0) }
        )
        return answers
            .map { RequestedReviewer(login: $0.key, answer: $0.value) }
            .sorted {
                let left = order[$0.answer] ?? 0
                let right = order[$1.answer] ?? 0
                return left == right ? $0.login < $1.login : left < right
            }
    }

    /// Vyžádané týmy, srovnané do podoby, kterou chce zápis (#392).
    ///
    /// **Slug se zbavuje předpony organizace**, protože `gh pr view` ho dává jako
    /// `keboola/ajda-swimlane`, kdežto REST i `orgs/{org}/teams` jako `ajda-swimlane` — a `team_reviewers`
    /// chce tu druhou podobu (změřeno na `keboola/platform-architecture-and-concepts#278`). Kdyby se
    /// obě podoby potkaly v panelu, vypadal by týž tým jako dva.
    ///
    /// Řadí se abecedně a duplikáty padají: pořadí z API nezaručuje nic a přeskládaný seznam se nedá
    /// přečíst dvakrát stejně.
    static func requestedTeams(_ slugs: [String]) -> [String] {
        Set(slugs.compactMap { slug in
            // `omittingEmptySubsequences: false` schválně: s výchozím `true` by z `keboola/`
            // vyšlo `keboola`, tedy **jméno organizace vydávané za slug týmu**. Chytil to test
            // na prázdný slug.
            let bare = slug.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init)
            return (bare?.isEmpty ?? true) ? nil : bare
        }).sorted()
    }

    /// Sekce po vyžádání review (#392): GitHub potvrdil, na koho se čeká, a odpovědi ostatních
    /// zůstávají tak, jak je okno zná.
    ///
    /// **Skládá se tou samou funkcí**, jen se vstupem odjinud: odpověď `requested_reviewers`
    /// verdikty nenese, kdežto okno je má z posledního čtení. Bez tohohle by se po vyžádání muselo
    /// znovu volat `fetchMetadata` — tedy kolo po síti za údaj, který už známe — nebo by se ten
    /// merge napsal podruhé, a druhé místo by se s prvním rozešlo (typicky zrovna v pravidle, že
    /// vyžádání přebíjí starší verdikt).
    static func reviewers(
        requested: [String],
        keeping known: [RequestedReviewer]
    ) -> [RequestedReviewer] {
        reviewers(
            requested: requested,
            verdicts: known.compactMap { reviewer in
                switch reviewer.answer {
                case .approved: ReviewerVerdict(login: reviewer.login, state: .approved)
                case .changesRequested: ReviewerVerdict(login: reviewer.login, state: .changesRequested)
                // `čeká` není verdikt, takže se nemá čím přenést — a kdyby se přeneslo, dostal by
                // se do seznamu i ten, koho GitHub v odpovědi nevyjmenoval.
                case .waiting: nil
                }
            }
        )
    }
}
