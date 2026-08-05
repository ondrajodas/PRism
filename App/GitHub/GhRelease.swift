import Foundation

/// Tvar jedné položky `GET /repos/{owner}/{repo}/releases`.
///
/// Vlastní `CodingKeys` proto, že tohle je **REST**, ne `gh --json`: pole se jmenují
/// `tag_name`, `published_at`, `html_url`. Tatáž úvaha jako u `GhSubmittedReview` —
/// `GhOutput.decoder` snake case nepřevádí a zapínat mu ho globálně by změnilo dekódování
/// všem ostatním DTO.
struct GhRelease: Decodable {
    let tagName: String
    /// GitHub ho vrací jako `null` u vydání bez názvu.
    let name: String?
    /// `null` u rozdělaného (`draft`) vydání — to ještě publikované není.
    let publishedAt: Date?
    let body: String?
    let htmlUrl: URL
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case name, body, draft
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case htmlUrl = "html_url"
    }

    /// `nil` u rozdělaného vydání.
    ///
    /// Draft **není vydaný**, takže o něm okno „co je nového“ nemá co říkat — a je vidět jen
    /// tomu, kdo má do repa právo zápisu, což jsem v tomhle repu zrovna já. Kdyby prošel,
    /// stal by se z něj „nejnovější release“ a značka naposledy viděného vydání by se posunula
    /// na něco, co nikdy nevyšlo. Datum se testuje spolu s ním, protože draft ho nemá.
    func release() -> Release? {
        guard !draft, let publishedAt else { return nil }
        // Název bez tagu je pro člověka k ničemu, takže se vydání bez názvu jmenuje svým
        // tagem — prázdný řádek v seznamu vypadá jako rozbitá aplikace.
        let title = name.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return Release(
            tag: tagName,
            name: title.isEmpty ? tagName : title,
            publishedAt: publishedAt,
            body: body ?? "",
            url: htmlUrl
        )
    }
}
