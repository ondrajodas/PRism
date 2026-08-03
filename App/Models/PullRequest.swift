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

    /// Jak se stav píše v okně.
    ///
    /// Patří k modelu, ne do view, které ho zrovna potřebuje: `rawValue` je **anglický**
    /// a jde do JSONu na disk, takže interpolovat ho do české věty znamená ukázat
    /// uživateli `closed` uprostřed češtiny. Chytilo se to v hlášce `PublishError`.
    var czechLabel: String {
        switch self {
        case .open: "otevřený"
        case .draft: "rozpracovaný"
        case .merged: "mergnutý"
        case .closed: "zavřený"
        }
    }
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
