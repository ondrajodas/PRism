import Foundation

/// Tvar JSONu, který vrací `gh` — schválně oddělený od doménových modelů.
///
/// `PullRequest` a `PullRequestSummary` se kódují na disk (`ReviewStore`), takže jejich
/// `Codable` popisuje uložený tvar. Kdyby dekódovaly rovnou výstup `gh`, propsaly by se do
/// něj `author.login`, `repository.nameWithOwner` i velikost písmen ve `state` — a změna
/// `gh` by nám měnila formát dat na disku.
enum GhOutput {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Autor tak, jak ho `gh` vrací u obou příkazů.
struct GhAuthor: Decodable {
    let login: String
}

/// Jedna položka `gh search prs --json …`.
struct GhSearchItem: Decodable {
    struct Repository: Decodable {
        let nameWithOwner: String
    }

    let number: Int
    let repository: Repository
    let title: String
    let author: GhAuthor
    let url: URL
    let updatedAt: Date
    let state: String
    let isDraft: Bool

    static let jsonFields = "number,repository,title,author,url,updatedAt,state,isDraft"

    func summary() throws -> PullRequestSummary {
        PullRequestSummary(
            id: try identifier(),
            title: title,
            author: author.login,
            url: url,
            updatedAt: updatedAt,
            state: try GhOutput.state(raw: state, isDraft: isDraft)
        )
    }

    private func identifier() throws -> PRIdentifier {
        guard let repo = RepoID(repository.nameWithOwner) else {
            throw GitHubError.malformedOutput("Neplatné jméno repozitáře „\(repository.nameWithOwner)“.")
        }
        guard number > 0 else {
            throw GitHubError.malformedOutput("Neplatné číslo PR \(number).")
        }
        return PRIdentifier(repo: repo, number: number)
    }
}

/// Výstup `gh pr view --json …`.
struct GhPullRequestDetail: Decodable {
    let number: Int
    let title: String
    let author: GhAuthor
    let headRefOid: String
    let baseRefOid: String
    let url: URL
    let updatedAt: Date
    let state: String
    let isDraft: Bool

    static let jsonFields = "number,title,author,headRefOid,baseRefOid,url,updatedAt,state,isDraft"

    /// Identifikátor se bere z dotazu — `gh pr view` neříká, ze kterého repa PR je, protože
    /// jsme mu ho zadali. Číslo se přesto ověřuje: nálezy se klíčují `headSha` konkrétního
    /// PR a tiché přiřazení k cizímu je přesně to, čemu má klíčování bránit.
    func pullRequest(id: PRIdentifier) throws -> PullRequest {
        guard number == id.number else {
            throw GitHubError.malformedOutput("gh vrátil PR číslo \(number), ptali jsme se na \(id).")
        }
        return PullRequest(
            id: id,
            title: title,
            author: author.login,
            headSha: headRefOid,
            baseSha: baseRefOid,
            url: url,
            updatedAt: updatedAt,
            state: try GhOutput.state(raw: state, isDraft: isDraft)
        )
    }
}

extension GhOutput {
    static func state(raw: String, isDraft: Bool) throws -> PullRequestState {
        guard let state = PullRequestState(ghState: raw, isDraft: isDraft) else {
            throw GitHubError.malformedOutput("Neznámý stav PR „\(raw)“.")
        }
        return state
    }
}
