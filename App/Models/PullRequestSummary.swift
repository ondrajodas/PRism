import Foundation

/// Pull request tak, jak ho vrací vyhledávání — bez `headSha` a `baseSha`.
///
/// Existuje proto, že `gh search prs` SHA neumí; ta jsou až v `gh pr view`. Ze searchu se
/// tedy `PullRequest` postavit nedá a předstírat opak by znamenalo buď prázdné SHA
/// v modelu, kde jsou klíčové, nebo detailní dotaz na každý nalezený PR při každém pollu.
/// Kdy se detail dotáhne, rozhoduje polling — ne gateway.
struct PullRequestSummary: Hashable, Codable, Sendable {
    let id: PRIdentifier
    let title: String
    let author: String
    let url: URL
    let updatedAt: Date
    let state: PullRequestState

    var repo: RepoID { id.repo }
    var number: Int { id.number }
}

extension PullRequestSummary {
    /// Shrnutí z dotaženého detailu (#531).
    ///
    /// Obráceně, než jak to chodí obvykle: shrnutí přichází z vyhledávání a detail se dotahuje
    /// z něj. U pull requestu **mimo zdroje** ale žádné vyhledávání neproběhlo — jediné, co
    /// o něm aplikace má, je odpověď `gh pr view`, takže se shrnutí skládá z ní.
    ///
    /// **Není to druhý model téhož, jen užší pohled**: `PullRequestSummary` je to, co umí každý
    /// řádek a každá záložka, kdežto `PullRequest` má navíc hlavu, základ a větve. Kdyby se
    /// z detailu bralo jen `headSha` a zbytek se vymýšlel, měla by hlavička u těchhle PR jiná
    /// data než u ostatních — a to je přesně ten rozdíl, který se v okně nepozná.
    init(_ detail: PullRequest) {
        self.init(
            id: detail.id,
            title: detail.title,
            author: detail.author,
            url: detail.url,
            updatedAt: detail.updatedAt,
            state: detail.state
        )
    }
}
