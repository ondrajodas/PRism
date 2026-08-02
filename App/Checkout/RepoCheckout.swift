import Foundation

/// Vlastní pracovní kopie aplikace.
///
/// Za protokolem, aby šla v testech nahradit fake implementací — a aby bylo z jednoho
/// místa vidět, že aplikace pracuje jen ve své cache.
protocol RepoCheckout: Sendable {
    /// Zajistí, že v cache je bare klon repa s aktuálními refy, a vrátí cestu k němu.
    ///
    /// Idempotentní: první volání klonuje, každé další jen dotahuje.
    func prepare(_ repo: RepoID) async throws -> URL

    /// Odpojený pracovní strom pro jedno review, na konkrétním commitu.
    ///
    /// Každý běh dostane vlastní, aby si paralelní reviewery nelezly do cesty.
    /// Idempotentní: existující strom pro stejné `(PR, sha)` se použije znovu.
    func worktree(for pr: PRIdentifier, at headSha: String) async throws -> URL

    /// Cesty souborů, které repo verzuje — podklad pro odhad jazyka projektu.
    ///
    /// Ptá se `gitu`, ne `FileManageru`: ignorované složky (`vendor/`, `node_modules/`,
    /// buildy) jsou zrovna ty, kterých je nejvíc, takže by odhad převážily.
    func trackedFiles(in worktree: URL) async throws -> [String]

    /// Uklidí pracovní strom. Chybějící strom není chyba.
    func removeWorktree(for pr: PRIdentifier, at headSha: String) async throws

    /// Zahodí ref, kterým si aplikace držela commity daného PR. Chybějící ref není chyba.
    func forgetPullRequest(_ pr: PRIdentifier) async throws

    /// Čísla PR, ke kterým si aplikace v tomhle repu drží ref.
    func trackedPullRequests(in repo: RepoID) async throws -> [Int]

    /// Zahodí záznamy o stromech, které už na disku nejsou.
    func pruneWorktrees(in repo: RepoID) async throws

    /// Cesta k **hotovému** klonu, pokud v cache je. Nic nestahuje ani nezakládá.
    func existingClone(for repo: RepoID) async -> URL?
}
