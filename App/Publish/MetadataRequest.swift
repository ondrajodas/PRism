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
    static func reviewerArguments(for pr: PRIdentifier, logins: [String]) -> [String] {
        [
            "api", "repos/\(pr.repo)/pulls/\(pr.number)/requested_reviewers",
            "-X", "POST",
        ] + logins.flatMap { ["-f", "reviewers[]=\($0)"] }
    }
}

/// Odpověď `POST /pulls/{n}/requested_reviewers` — pull request, ze kterého nás zajímá **jen**
/// seznam vyžádaných.
///
/// Odpověď nese celý PR (a tedy i jeho popis a hlavu), ale odpovědi reviewerů v ní nejsou —
/// `requested_reviewers` je právě to, na koho se čeká. Zbytek se do modelu nepřepisuje, protože
/// tohle není čtení detailu.
struct GhRequestedReviewersResponse: Decodable {
    struct Reviewer: Decodable {
        let login: String
    }

    let requestedReviewers: [Reviewer]

    enum CodingKeys: String, CodingKey {
        case requestedReviewers = "requested_reviewers"
    }

    func logins() -> [String] {
        requestedReviewers.map(\.login).filter { !$0.isEmpty }
    }
}
