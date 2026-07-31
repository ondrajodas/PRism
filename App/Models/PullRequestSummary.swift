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
