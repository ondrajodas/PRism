import Foundation

/// Jeden řádek z `gh pr checks --json` (#209).
///
/// Vlastní typ, ne dekódování rovnou do `PullRequestCheck`: tvar odpovědi patří `gh`, kdežto
/// model patří aplikaci — tatáž hranice jako u `GhSearchItem` a `GhPullRequestDetail`.
struct GhCheck: Decodable, Sendable {
    let name: String
    /// `pass` / `fail` / `pending` / `skipping` / `cancel`. **Kbelík, ne `state`**: `state` má
    /// zvlášť hodnoty pro checks a pro statusy (`SUCCESS` versus `COMPLETED`), kdežto kbelík je
    /// právě to zobecnění, které `gh` počítá sám.
    let bucket: String
    let link: String?
    let startedAt: Date?
    let completedAt: Date?

    var check: PullRequestCheck {
        PullRequestCheck(
            name: name,
            outcome: .init(bucket: bucket),
            link: link.flatMap(URL.init(string:)),
            startedAt: startedAt,
            completedAt: completedAt
        )
    }
}
