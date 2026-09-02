import Foundation

/// Jedna položka `gh repo list <org> --json …` (#532).
///
/// Vlastní typ vedle doménového `OrganizationRepository` ze stejného důvodu jako `GhSearchItem`
/// vedle `PullRequestSummary`: tenhle popisuje **tvar výstupu `gh`**, ten druhý to, co leží
/// v cache aplikace. Kdyby se dekódoval rovnou doménový model, propsalo by se do souboru na disku
/// `nameWithOwner` i zanořený `pullRequests.totalCount`, a změna `gh` by nám měnila formát cache.
struct GhRepositoryItem: Decodable {
    /// GitHub počty vrací zanořené v objektu s jediným polem — i tady, kde je to jedno číslo.
    struct Count: Decodable {
        let totalCount: Int
    }

    let nameWithOwner: String
    /// **Otevřené** pull requesty; ověřeno na živém API (viz `OrganizationRepository`).
    let pullRequests: Count
    /// Prázdné repo `pushedAt` nemá, proto optional.
    let pushedAt: Date?

    static let jsonFields = "nameWithOwner,pullRequests,pushedAt"

    /// `nil` u položky, ze které se nedá udělat `RepoID`.
    ///
    /// **Zahazuje se položka, ne celý výpis** — na rozdíl od `GhSearchItem`, kde neplatné jméno
    /// položí celé vyhledávání. Rozdíl je v tom, co na tom stojí: tam se ze `summary` klíčují
    /// nálezy, tady je to řádek v nabídce. Jedno nepřečtené jméno mezi tisícem nemá důvod vzít
    /// organizaci celou.
    var repository: OrganizationRepository? {
        guard let repo = RepoID(nameWithOwner) else { return nil }
        return OrganizationRepository(
            repo: repo,
            // Záporný počet by `gh` vydat neměl; kdyby přece, srazí se na nulu — v okně by z něj
            // jinak bylo `−3 otevřených PR`.
            openPullRequests: max(0, pullRequests.totalCount),
            lastPushedAt: pushedAt
        )
    }
}
