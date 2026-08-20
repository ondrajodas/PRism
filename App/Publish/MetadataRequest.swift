import Foundation

/// Dotazy, kterými se mění labely a vyžádají reviewery (#392). Čisté funkce, žádné I/O.
///
/// **REST, ne GraphQL**, a ze stejného důvodu jako u komentáře pod PR (#216): obojí se adresuje
/// číslem PR a repem, tedy tím, co `PRIdentifier` má. GraphQL mutace by chtěly node ID pull
/// requestu i labelů, které se dnes netahá nikde.
///
/// **Label je z pohledu API vlastnost issue, ne pull requestu** (`/issues/{n}/labels`) — pull
/// request je issue s diffem a `/pulls/` pro labely nic nemá. Reviewer naopak `/pulls/` má, protože
/// review na issue neexistuje.
enum MetadataRequest {
    /// Tělo `PUT /issues/{n}/labels`. **Nahrazuje celou sadu**, takže se posílá celá.
    struct LabelsPayload: Encodable, Equatable {
        let labels: [String]
    }

    /// Argumenty pro `gh api`.
    ///
    /// Sada jde **souborem**, ne přes `-f 'labels[]=…'`, a je to kvůli jediné hodnotě, která se
    /// jinak poslat nedá: **prázdná sada**. Sundání posledního labelu je `{"labels": []}`, kdežto
    /// `gh api` bez jediného `-f` neposílá tělo vůbec. Jedna cesta pro obojí je lepší než dvě,
    /// z nichž se jedna použije jen při sundávání posledního štítku — tedy zrovna ta, kterou
    /// nikdo nezkouší.
    static func labelArguments(for pr: PRIdentifier, payload file: URL) -> [String] {
        [
            "api", "repos/\(pr.repo)/issues/\(pr.number)/labels",
            "-X", "PUT",
            "--input", file.path(percentEncoded: false),
        ]
    }

    static func encoded(_ payload: LabelsPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    /// Argumenty pro `POST /pulls/{n}/requested_reviewers`.
    ///
    /// Loginy jdou přes `-f 'reviewers[]=…'`, ne souborem: seznam je vždycky neprázdný (vyžádat
    /// nikoho není akce), takže past s prázdným tělem tady není. `-f`, ne `-F`, ze stejného důvodu
    /// jako u komentáře: `--field` hodnotu **typuje** (číslo pošle jako číslo), takže login
    /// z číslic by v payloadu skončil jako `123` místo `"123"`.
    static func reviewerArguments(
        for pr: PRIdentifier,
        logins: [String],
        teams: [String]
    ) -> [String] {
        [
            "api", "repos/\(pr.repo)/pulls/\(pr.number)/requested_reviewers",
            "-X", "POST",
        ]
            + logins.flatMap { ["-f", "reviewers[]=\($0)"] }
            // Týmy jdou **týmž voláním**, jen druhým polem — GitHub je bere spolu, takže se to
            // nedělí na dvě žádosti (a tedy ani na dva částečně odeslané stavy).
            + teams.flatMap { ["-f", "team_reviewers[]=\($0)"] }
    }
}

/// Odpověď `POST /pulls/{n}/requested_reviewers` — pull request, ze kterého nás zajímají **jen**
/// dva seznamy vyžádaných.
///
/// Odpověď nese celý PR (a tedy i jeho popis a hlavu), ale odpovědi reviewerů v ní nejsou —
/// `requested_reviewers` a `requested_teams` je právě to, na koho se čeká. Zbytek se do modelu
/// nepřepisuje, protože tohle není čtení detailu.
///
/// **Obojí je optional**: GitHub `requested_teams` u repa bez týmů vynechá a chybějící pole nemá
/// položit odpověď na akci, která prošla.
struct GhRequestedReviewersResponse: Decodable {
    struct Reviewer: Decodable {
        let login: String
    }

    let requestedReviewers: [Reviewer]?
    let requestedTeams: [GhTeam]?

    enum CodingKeys: String, CodingKey {
        case requestedReviewers = "requested_reviewers"
        case requestedTeams = "requested_teams"
    }

    func logins() -> [String] {
        (requestedReviewers ?? []).map(\.login).filter { !$0.isEmpty }
    }

    /// Slugy týmů. **Bez předpony organizace už z API** (změřeno), ale sjednocuje se to stejnou
    /// funkcí jako u čtení, aby se obě cesty nemohly rozejít.
    func teamSlugs() -> [String] {
        Policy.requestedTeams((requestedTeams ?? []).map(\.slug))
    }
}

/// Na koho se po vyžádání čeká — lidé a týmy zvlášť, jako je má GitHub (#392).
///
/// **Vlastní typ, ne dvojice v návratu**: volající z toho skládá dvě různá pole snímku a tuple by
/// u volání nesl jen pořadí, ne význam.
struct RequestedReview: Hashable, Sendable {
    let reviewers: [RequestedReviewer]
    let teams: [String]
}
