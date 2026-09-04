import Foundation

/// Odpověď `gh api repos/{owner}/{repo}` v té části, která mluví o mergi (#556).
///
/// **Vlastní typ vedle doménového `RepositoryMergeSettings`**, ze stejného důvodu jako
/// `GhRepositoryItem` vedle `OrganizationRepository`: tenhle popisuje tvar výstupu `gh`
/// (`snake_case`, `null` u repa bez práva zápisu), ten druhý to, s čím pracuje okno.
///
/// **Všechna pole jsou optional a je to změřené, ne opatrnost.** Nad `cli/cli` (bez práva zápisu)
/// přijdou všechny tři příznaky i oba zdroje těla jako `null`; nad `ondrajodas/PRism` přijdou
/// `true`/`true`/`true` a `COMMIT_MESSAGES`/`PR_TITLE`; nad `keboola/job-queue-daemon` je
/// `allow_rebase_merge: false`. Chybějící pole tedy **není porucha**, je to odpověď „nevím“.
struct GhRepositoryMergeSettings: Decodable {
    let allowMergeCommit: Bool?
    let allowSquashMerge: Bool?
    let allowRebaseMerge: Bool?
    let squashMergeCommitMessage: String?
    let mergeCommitMessage: String?

    enum CodingKeys: String, CodingKey {
        case allowMergeCommit = "allow_merge_commit"
        case allowSquashMerge = "allow_squash_merge"
        case allowRebaseMerge = "allow_rebase_merge"
        case squashMergeCommitMessage = "squash_merge_commit_message"
        case mergeCommitMessage = "merge_commit_message"
    }

    /// Doménová podoba. **Neznámý řetězec ve zdroji těla se bere jako „nevím“**, ne jako chyba:
    /// GitHub tam smí přidat další hodnotu a věta „složí GitHub podle nastavení repozitáře“ je
    /// pravdivá pořád, kdežto položený merge kvůli neznámému enumu by byl porucha vyrobená z pole,
    /// na kterém nic nestojí.
    var settings: RepositoryMergeSettings {
        RepositoryMergeSettings(
            allowsMergeCommit: allowMergeCommit,
            allowsSquash: allowSquashMerge,
            allowsRebase: allowRebaseMerge,
            squashBody: squashMergeCommitMessage.flatMap(MergeBodySource.init(rawValue:)),
            mergeCommitBody: mergeCommitMessage.flatMap(MergeBodySource.init(rawValue:))
        )
    }
}
