import Foundation

/// Výstup `gh pr view --json labels,reviewRequests,latestReviews` (#392).
///
/// **Vlastní dotaz vedle `GhPullRequestDetail`, ne pole navíc v něm.** `fetchDetail` volá i
/// pre-flight publisheru před **každým** odesláním, a `latestReviews` nese celá těla review —
/// přidat je do detailu znamená platit tu velikost při každém odeslání za údaj, který odesílání
/// nezajímá. Změřeno na `cli/cli`: jedno review od bota mělo v `body` 1,5 kB.
struct GhPullRequestMetadata: Decodable {
    let labels: [GhLabel]
    let reviewRequests: [GhReviewRequest]
    let latestReviews: [GhLatestReview]

    static let jsonFields = "labels,reviewRequests,latestReviews"

    /// Sloučení do jednoho snímku. **Rozhoduje `Policy`**, ne tenhle typ: kdo se v sekci kreslí
    /// a s jakou odpovědí, je rozhodnutí (viz `Policy.reviewers`), kdežto tady se jen převádí tvar.
    func metadata() -> PullRequestMetadata {
        PullRequestMetadata(
            labels: labels.map(\.label),
            reviewers: Policy.reviewers(
                // Týmy se **zahazují**: vyžádat se z okna dají jen lidé (`assignableUsers`), takže
                // tým v seznamu by byl řádek, se kterým se nedá nic udělat — a login by mu chyběl.
                requested: reviewRequests.compactMap(\.login),
                verdicts: latestReviews.map(\.verdict)
            )
        )
    }
}

/// Label tak, jak ho `gh` vrací u PR i u repozitáře — týž tvar na obou koncích.
struct GhLabel: Decodable {
    let name: String
    /// Šestimístný hex bez `#`. Optional schválně: chybějící barva nemá položit celou sekci,
    /// puntík se pak nakreslí neutrální.
    let color: String?

    var label: PullRequestLabel { PullRequestLabel(name: name, color: color ?? "") }
}

/// Jedno vyžádané review. **Uživatel má `login`, tým ne** — proto optional a proto se týmy
/// zahazují (ověřeno na živém API: `{"__typename":"User","login":"BagToad"}`).
struct GhReviewRequest: Decodable {
    let login: String?
}

/// Poslední review jednoho člověka. Z celé odpovědi se čte **jen autor a stav** — tělo tady
/// nikoho nezajímá, kreslí ho osa konverzace.
struct GhLatestReview: Decodable {
    let author: GhAuthor?
    let state: String?

    var verdict: Policy.ReviewerVerdict {
        Policy.ReviewerVerdict(
            login: author?.login ?? "",
            state: state.flatMap(SubmittedReview.State.init(rawValue:))
        )
    }
}

/// Odpověď GraphQL dotazu na lidi, kteří na repo smí (#392).
///
/// **GraphQL, ne `GET /repos/{o}/{r}/collaborators`**: seznam spolupracovníků chce push právo na
/// repo, takže by u repa, kam se dá jen číst, spadl na 403 — a tohle je nabídka, která se otevírá
/// na vlastním PR, tedy typicky tam, kde práva jsou, ale ne vždycky. `assignableUsers` je navíc
/// přesně ta množina, ze které GitHub sám dovolí vyžádat review.
struct GhAssignableUsersResponse: Decodable {
    struct Payload: Decodable {
        struct Repository: Decodable {
            struct Users: Decodable {
                let nodes: [GhAuthor?]
            }

            let assignableUsers: Users
        }

        let repository: Repository?
    }

    let data: Payload

    /// Loginy, prázdné a chybějící se zahazují — účet bez loginu se vyžádat nedá.
    func logins() -> [String] {
        (data.repository?.assignableUsers.nodes ?? [])
            .compactMap { $0?.login }
            .filter { !$0.isEmpty }
    }
}
