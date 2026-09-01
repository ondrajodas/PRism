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
    ///
    /// **`keepingConflict` rozhoduje, co se stane s rozdělaným rebasem** (#467). `false` je chování
    /// do #466: konflikt se zahodí (`rebase --abort`) a v cache po něm nic nezůstane. `true`
    /// znamená „nech ho stát“ — je to jediný stav, ve kterém může session konflikt slít, protože
    /// zahozený rebase žádné značky v souborech nemá. Není to volba pohodlí: zahodit rebase, na
    /// kterém má hned pracovat session, a pak ho spustit znovu, by znamenalo dvakrát tahat základ
    /// a dvakrát přehrávat commity.
    func rebase(
        _ pr: PRIdentifier,
        at headSha: String,
        onto base: String,
        keepingConflict: Bool
    ) async throws -> RebaseOutcome

    /// Zapíše do indexu soubory, které session slila, a vrátí **diff toho, co z nich vzniklo**
    /// (#467).
    ///
    /// **Diff je doklad z `gitu`, ne popis od session** (zadání #467) — proto ho vydává tenhle
    /// modul a ne runner. Bere se před zápisem do indexu (`git diff HEAD -- <soubory>`), takže
    /// obsahuje **jen kolidující soubory**, ne zbytek přehrávaného commitu.
    ///
    /// **Soubor, ve kterém zůstaly konfliktní značky, se do indexu nezapíše** a vrátí se
    /// v `unresolved`. Je to jediná kontrola, která nestojí na tvrzení modelu: zapsat značky do
    /// commitu je ta nejhorší podoba „uhádaného slití“, protože projde a rozbije build.
    func stageResolution(in worktree: URL, paths: [String]) async throws -> ConflictStaging

    /// Dokončí přerušený rebase (`git rebase --continue`) a řekne, jak to dopadlo (#467).
    ///
    /// **Commituje aplikace, ne session** (zadání #467) — dvě věci, které commitují, se rozejdou.
    /// Návratová hodnota je tatáž jako u `rebase`, protože dopadnout to může stejně: doběhne,
    /// nebo se zastaví na dalším kolizním commitu.
    func continueRebase(
        _ pr: PRIdentifier,
        at headSha: String,
        onto base: String,
        keepingConflict: Bool
    ) async throws -> RebaseOutcome

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
