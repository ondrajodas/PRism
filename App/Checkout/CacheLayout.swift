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

    /// Značka „klon doběhl celý“, zapsaná až po úspěšném `git clone`.
    ///
    /// Vlastní soubor schválně, ne odvozování z toho, co je uvnitř klonu. `git` zakládá
    /// `HEAD`, `config` i `refs/` **hned na začátku**, takže po zabitém klonu složka
    /// vypadá jako hotový repozitář — ověřeno. Fetch nad ní pak projde, ale `HEAD`
    /// zůstane `ref: refs/heads/.invalid` a hlavně chybí `remote.origin.promisor`:
    /// klon tiše přestane být partial a od té chvíle tahá všechny bloby.
    func cloneMarker(for repo: RepoID) -> URL {
        bareClone(for: repo).appending(path: "prism-clone-complete")
    }
}
