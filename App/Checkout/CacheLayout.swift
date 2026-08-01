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

    /// Kde leží klony a stromy — eviction je potřebuje projít, ne jen skládat cesty.
    var repositories: URL { root.appending(path: "repos") }
    var worktrees: URL { root.appending(path: "worktrees") }

    /// Bare klon repa: `repos/<owner>/<repo>.git`.
    func bareClone(for repo: RepoID) -> URL {
        repositories
            .appending(path: repo.owner)
            .appending(path: "\(repo.name).git")
    }

    /// Pracovní strom jednoho review: `worktrees/<owner>-<repo>-<pr>-<sha>`.
    ///
    /// `headSha` je v názvu schválně — nálezy na něm visí, takže dva běhy nad různými
    /// commity téhož PR si nesmí sáhnout na stejný strom.
    func worktree(for pr: PRIdentifier, at headSha: String) -> URL {
        // Celý sha, ne zkrácený: cesta je zároveň klíč koordinátoru, takže shoda prefixu
        // dvou commitů by dva běhy poslala na tentýž strom.
        worktrees(of: pr.repo).appending(path: "\(pr.number)-\(headSha)")
    }

    /// Stromy jsou zanořené pod repo, ne slepené do jednoho jména.
    ///
    /// Ploché `owner-repo-pr-sha` se nedá spolehlivě filtrovat podle prefixu: `keboola-kbc-`
    /// sedí i na `keboola-kbc-stacks-42-…`, takže úklid jednoho repa by sahal na stromy
    /// jiného — a to i takového, ve kterém zrovna běží review.
    func worktrees(of repo: RepoID) -> URL {
        worktrees.appending(path: repo.owner).appending(path: repo.name)
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

    /// Kdy se s repem naposledy pracovalo — podle toho se rozhoduje, co z cache odejde
    /// první.
    ///
    /// **Vedle** klonu, ne uvnitř: zapisuje se ještě před klonováním (jinak by rozklonované
    /// repo nemělo razítko a eviction by ho v LRU vzala jako první), a `git clone` odmítne
    /// klonovat do složky, ve které už něco leží. Eviction ho maže spolu s klonem.
    func lastUsedMarker(for repo: RepoID) -> URL {
        repositories.appending(path: repo.owner).appending(path: "\(repo.name).last-used")
    }
}
