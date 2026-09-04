import Foundation

/// Odpověď `gh api repos/{owner}/{repo}` v té části, která mluví o mergi (#556).
///
/// **Vlastní typ vedle doménového `RepositoryMergeSettings`**, ze stejného důvodu jako
/// `GhRepositoryItem` vedle `OrganizationRepository`: tenhle popisuje tvar výstupu `gh`
/// (`snake_case`, **chybějící klíče** u repa bez práva zápisu), ten druhý to, s čím pracuje okno.
///
/// **Všechna pole jsou optional a je to změřené, ne opatrnost.** Nad `cli/cli` (bez práva zápisu)
/// GitHub všech pět polí **vůbec nepošle** — klíče v odpovědi nejsou (ověřeno nad syrovým JSONem;
/// `gh api --jq .allow_merge_commit` na tom vypíše `null`, protože `jq` chybějící klíč vydá jako
/// `null`, takže se z něj ten rozdíl nepozná). Nad `ondrajodas/PRism` přijdou `true`/`true`/`true`
/// a `COMMIT_MESSAGES`/`PR_TITLE`; nad `keboola/job-queue-daemon` je `allow_rebase_merge: false`.
///
/// **Chybějící klíč a explicitní `null` jsou pro nás jedna a tatáž odpověď** („nevím“), a je to
/// vlastnost synteticky generovaného dekódování: `decodeIfPresent` vydá `nil` na obojí. Rozlišovat
/// je nemá smysl — otázka je „ví se, co repo pustí“, ne „jakým způsobem to GitHub neřekl“.
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
