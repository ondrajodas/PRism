import Foundation

/// Kde má aplikace svoje pracovní kopie.
///
/// Tvrdá podmínka: **nikdy nesahat na uživatelovy klony.** Ty mohou být rozdělané, na jiné
/// branchi nebo mít vlastní worktrees. Všechno, co si aplikace naklonuje, leží pod jedním
/// kořenem, který si drží sama — a `root` je injektovatelný, aby testy nikdy nesáhly do
/// toho skutečného.
struct CacheLayout: Sendable, Equatable {
    let root: URL

    static let applicationSupport = CacheLayout(
        root: URL.applicationSupportDirectory.appending(path: "PRism")
    )

    /// Bare klon repa: `repos/<owner>/<repo>.git`.
    func bareClone(for repo: RepoID) -> URL {
        root
            .appending(path: "repos")
            .appending(path: repo.owner)
            .appending(path: "\(repo.name).git")
    }
}
