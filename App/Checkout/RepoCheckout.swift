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

    /// Přehraje commity pull requestu nad základem (#466) — **ve vlastním stromě v cache**.
    ///
    /// **Nepushuje a nemá čím** (tvrdá podmínka č. 1): tenhle modul zůstává lokální, do remote
    /// zapisuje jedině `BranchPushing`. Výsledek nese cestu ke stromu, ze kterého se dá pushnout,
    /// a hlavu, která z rebasu vypadla.
    ///
    /// **Konflikt není chyba, ale návratová hodnota** — vede jinam než „nedá se spustit `git`“.
    /// Když se povede rebase zahodit, v cache po něm nic nezůstane; když ne, leží tam rozdělaný
    /// a musí to být vidět v okně.
    ///
    /// Základ se dotahuje pokaždé (`prepare`), protože rebase nad zastaralým `main`em by srovnal
    /// větev s něčím, co už není.
    func rebase(_ pr: PRIdentifier, at headSha: String, onto base: String) async throws -> RebaseOutcome

    /// Zahodí, co ve stromě pro srovnání větve leží — **rozdělaný rebase i přerovnanou větev, která
    /// neodešla** (#466). Chybějící strom není chyba: na remote se nesáhlo, takže není co vracet.
    ///
    /// **Maže celý strom, ne `rebase --abort`.** Od rozdělení akce na dva kroky se zahazují dvě různé
    /// věci a `--abort` umí jen jednu z nich — nad dokončeným rebasem by neudělal nic a v cache by
    /// zůstaly přehrané commity, přestože panel hlásí uklizeno. Smazání stromu je jedna operace
    /// s jedním významem a příští rebase si strom založí znovu.
    func discardSync(for pr: PRIdentifier) async throws

    /// Co leží ve stromě pro srovnání větve (#466) — **tři stavy, ne „běží rebase“**.
    ///
    /// Ptá se `gitu` (`rev-parse`), ne `FileManageru`: u pracovního stromu leží `rebase-merge`
    /// uvnitř klonu (`<klon>/worktrees/<jméno>/`), ne v něm samotném — změřeno.
    ///
    /// `headSha` je hlava pull requestu, `base` jméno jeho základní větve: podle prvního se pozná
    /// **přerovnaná** větev od nedotčené, podle druhého se dopočítá, kolik commitů nad základem leží.
    func syncWorktreeState(
        for pr: PRIdentifier,
        at headSha: String,
        onto base: String
    ) async -> SyncWorktreeState

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
