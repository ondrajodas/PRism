import Foundation

/// Stav pull requestu na GitHubu.
///
/// Jeden plochý výčet, ne `state` + `isDraft`. GitHub to sice vrací jako dvě pole, ale
/// v aplikaci je z toho jeden odznak v řádku a kombinace, které by dvě pole navíc
/// dovolila (mergnutý draft), reálně nevzniknou. Mapování ze `gh` je mechanické:
/// otevřený a `isDraft` → `draft`.
enum PullRequestState: String, Codable, Sendable, CaseIterable {
    case open
    case draft
    case merged
    case closed
}

/// Pull request tak, jak ho aplikace potřebuje — metadata z `gh`, žádný diff a žádné nálezy.
///
/// `headSha` je klíčové pole, ne jen údaj: nálezy se klíčují jím, takže nové commity
/// předchozí review zneplatní místo aby se tiše ukazovalo proti kódu, který už neexistuje.
struct PullRequest: Hashable, Codable, Sendable {
    let id: PRIdentifier
    let title: String
    let author: String
    let headSha: String
    let baseSha: String
    let url: URL
    let updatedAt: Date
    let state: PullRequestState

    var repo: RepoID { id.repo }
    var number: Int { id.number }
}
