import Foundation

/// Co se stane při `Rebase` (#466) — **snímek z dat pull requestu**, ne z toho, co leží
/// v cache.
///
/// Celý plán se skládá z odpovědi GitHubu (`Policy.branchSyncPlan`), a je to první polovina
/// prvního guardu z tvrdé podmínky č. 1: cílem přetlačení smí být **hlava pull requestu, jehož
/// autorem jsem já**, ne větev, která se náhodou tak jmenuje. Jméno větve si nastaví kdokoli,
/// kdežto `headRefName` a `headRefOid` patří k pull requestu a k jeho autorovi.
struct BranchSyncPlan: Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Jméno větve **z dat pull requestu** (`headRefName`). Zároveň to, co se přetlačuje.
    let branch: String
    /// Cílová větev, nad kterou se commity přehrají.
    let base: String
    /// Hlava, kterou má remote nést, **než se sáhne na `push`**.
    ///
    /// Jde do `--force-with-lease=<větev>:<sha>` — tedy do podmínky, kterou vyhodnocuje server.
    /// Když se remote mezitím pohnul, push **selže** a nic se nepřepíše (změřeno, viz
    /// `GitBranchPush`).
    let expectedRemoteSha: String
    /// Kolik commitů větev nese nad základem — tedy kolik se jich přehraje. Z `compare` (#466),
    /// takže je to počet proti **aktuálnímu** základu, ne počet commitů pull requestu.
    let replaying: Int
    /// O kolik commitů je větev za základem. `0` znamená, že není co srovnávat.
    let behind: Int
}

/// Co se má přetlačit do remote (#466) — payload **jediné cesty ven přes `git`**.
///
/// **Vlastní typ vedle `BranchSyncPlan`**, ne tentýž: plán je snímek toho, co se chystá, kdežto
/// tohle vzniká až po rebasu a nese to, co z něj vypadlo — hlavu, která se má na remote dostat,
/// a strom, ze kterého se pushuje. Kdyby to bylo jedno pole v plánu, dal by se plán složit
/// i **bez** rebasu, a tím i pushnout něco, co nikdo nepřehrál.
struct BranchPushPlan: Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Větev na remote, do které se píše. Z dat pull requestu, viz `BranchSyncPlan.branch`.
    let branch: String
    /// Co má na remote ležet — lease. Z dat pull requestu.
    let expectedRemoteSha: String
    /// Co se tam má dostat — hlava po rebasu.
    let sha: String
    /// Odkud se pushuje. **Musí ležet v cache aplikace** (tvrdá podmínka č. 3); ověřuje to
    /// `GitBranchPush` toutéž kontrolou, kterou má úklid a úložiště (`CacheLayout.contains`).
    let worktree: URL
}

/// Jak dopadlo přehrání commitů nad základem (#466).
///
/// **Konflikt je stav, ne chyba**, a proto je v návratové hodnotě, ne v `throw`: z konfliktu
/// plyne jiný další krok (zahodit rebase, otevřít terminál) než z toho, že se nedá spustit `git`.
enum RebaseOutcome: Equatable, Sendable {
    case rebased(RebasedBranch)
    /// Commity se přehrát nedaly. `aborted` říká, jestli se povedlo strom vrátit tam, kde byl —
    /// když ne, **leží v cache rozdělaný rebase** a musí to být vidět v okně.
    case conflicted(files: [String], aborted: Bool)
}

/// Výsledek přehrání commitů (#466).
struct RebasedBranch: Hashable, Sendable {
    /// Pracovní strom v cache, ve kterém výsledek leží. Odsud se pushuje.
    let worktree: URL
    /// Hlava po rebasu.
    let headSha: String
    /// **Ze které hlavy se přehrávalo** — hlava pull requestu ve chvíli rebase.
    ///
    /// Vzniklo to rozdělením akce na dva kroky (rebase a přetlačení zvlášť) a **je to pojistka, ne
    /// údaj**. Mezi rebasem a potvrzením přetlačení může být libovolně dlouhá pauza — okno se dá
    /// zavřít a přijít znovu —, takže se hlava PR mezitím může pohnout (push z jiného stroje,
    /// z terminálu, z GitHubu). Kdyby se lease skládal z **aktuální** hlavy, prošel by a přepsal
    /// by ten nový commit; s touhle hodnotou narazí pre-flight na `headMoved` a nepřetlačí nic.
    /// Rebase se pak musí spustit znovu.
    let rebasedFrom: String
    /// Kolik commitů se přehrálo. **Spočítané po rebasu z výsledku**, ne převzaté z plánu:
    /// plán mluví o tom, co se čekalo, tohle o tom, co vzniklo.
    let replayed: Int
}

/// Co leží ve stromě pro srovnání větve (#466).
///
/// **Tři stavy, ne boolean „běží rebase“.** Rozdělením akce na dva kroky vznikl mezistav
/// *přerovnáno, nepřetlačeno* — a ten je stejně důležitý jako rozdělaný rebase: v obou případech
/// leží v kopii repa práce, o které má rozhodnout člověk, a v obou by o ní okno po restartu
/// aplikace mlčelo, kdyby se nehledala. Tichý stav v cache je horší než chyba.
enum SyncWorktreeState: Equatable, Sendable {
    /// Strom není, nebo v něm stojí přesně hlava pull requestu — tedy nic rozdělaného.
    case empty
    /// Leží tam rozdělaný rebase (`rebase-merge` / `rebase-apply`).
    case unfinishedRebase
    /// Rebase doběhl a výsledek **neodešel**.
    case rebased(RebasedBranch)
}
