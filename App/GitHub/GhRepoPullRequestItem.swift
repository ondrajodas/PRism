import Foundation

/// Jedna položka `gh pr list --repo <owner/name> --json …` (#533).
///
/// **Vlastní typ vedle `GhSearchItem`, ne jeho znovupoužití**, a je to kvůli jednomu chybějícímu
/// poli: `gh pr list` se ptá **jednoho repa**, takže `repository` v odpovědi vůbec není — repo se
/// ví z dotazu, stejně jako u `GhPullRequestDetail`. Kdyby se dekódoval `GhSearchItem`, padalo by
/// to na `keyNotFound`, nebo by se pole muselo zoptionalizovat a tím by přestalo hlídat odpovědi
/// z vyhledávání.
///
/// Ověřeno na živém API (`cli/cli`, 50 otevřených PR): `number`, `title`, `author.login`, `url`,
/// `updatedAt`, `state`, `isDraft` chodí u všech položek. `author` nese u botů `is_bot`, což se
/// nedekóduje — `GhAuthor` bere jen `login`.
struct GhRepoPullRequestItem: Decodable {
    let number: Int
    let title: String
    let author: GhAuthor
    let url: URL
    let updatedAt: Date
    let state: String
    let isDraft: Bool

    static let jsonFields = "number,title,author,url,updatedAt,state,isDraft"

    /// Shrnutí pro paletu. Repo se bere **z dotazu**, protože ho `gh pr list` neříká.
    ///
    /// **Neplatné číslo položí celý výpis**, na rozdíl od `GhRepositoryItem`, kde se zahazuje jen
    /// řádek: z tohohle shrnutí se po `↵` otevře záložka a klíčují se nálezy, takže tiché
    /// přiřazení k cizímu PR je zrovna to, čemu má klíčování bránit. Je to tatáž hranice jako
    /// u `GhSearchItem`.
    func summary(in repo: RepoID) throws -> PullRequestSummary {
        guard number > 0 else {
            throw GitHubError.malformedOutput("Neplatné číslo PR \(number).")
        }
        return PullRequestSummary(
            id: PRIdentifier(repo: repo, number: number),
            title: title,
            author: author.login,
            url: url,
            updatedAt: updatedAt,
            state: try GhOutput.state(raw: state, isDraft: isDraft)
        )
    }
}
