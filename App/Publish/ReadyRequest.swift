import Foundation

/// Dotaz, kterým se vlastní draft přepne na *ready for review* (#482). Čistá funkce, žádné I/O.
///
/// **`gh pr ready`, ne `gh api` — a je to jediná cesta ven, která nejde přes `gh api`.** Vybráno
/// měřením na `ondrajodas/prism-review-sandbox#11`, ne pohodlím; ostatní dvě možnosti se změřily
/// a zamítly:
///
/// - **REST `PATCH /pulls/{n}` s `draft=false` vrátí `200` a přepnutí tiše zahodí.** V odpovědi na
///   ten samý dotaz stojí `"draft": true`. Je to **tatáž past**, jakou tenhle repo zná od
///   `POST /requested_reviewers` s Copilotem (`docs/github-cli.md`): úspěšné volání, po kterém se
///   nestalo nic — tedy to nejhorší, co se dá pod tlačítko schovat. REST na tuhle věc endpoint
///   **nemá**.
/// - **GraphQL mutace `markPullRequestReadyForReview` funguje, ale chce node ID pull requestu**,
///   které aplikace nemá odkud vzít: `PullRequest` je `Codable` a persistovaný, takže by to bylo
///   další volitelné pole a s ním další „nevím“, které musí blokovat — a to všechno pro jednu
///   hodnotu použitou na jednom místě. Přitěžující okolnost je změřená: mutace hlásí chybu textem
///   `Could not resolve to a node with the global id`, na kterém `PublishError.init(failure:)`
///   vydá **`threadNotFound`** — tedy věta o vlákně nad přepnutím draftu.
///
/// Co se u `gh pr ready --repo` změřilo:
///
/// | Situace | Kód | stdout | stderr |
/// |---|---|---|---|
/// | draft, z `/` i z git worktree | 0 | prázdno | `✓ … is marked as "ready for review"` |
/// | PR, který draft **není** | 0 | prázdno | `! … is already "ready for review"` |
/// | neexistující číslo PR | 1 | prázdno | `GraphQL: Could not resolve to a PullRequest with the number of …` |
/// | neplatný token | 1 | prázdno | `HTTP 401: Bad credentials` |
///
/// **`--repo` je povinné, ne úsporné.** Bez něj si `gh` repozitář hádá z pracovní složky procesu,
/// a tu aplikace nenastavuje — GUI aplikace ze `/Applications` stojí v `/`. Změřeno je i to, že
/// s `--repo` **funguje z git worktree**, tedy že tohle není `gh pr merge` (ten z pracovního stromu
/// skončí nenulově, viz `docs/github-cli.md`): `gh pr ready` do lokálního repa nesahá vůbec.
enum ReadyRequest {
    /// Argumenty pro `gh pr ready`.
    ///
    /// **Číslo jde jako argument, ne přes `--json`** — je to příkaz, ne API dotaz. Nic dalšího se
    /// neposílá: payload téhle akce je jeden bit a ten je v samotném příkazu.
    static func arguments(for pr: PRIdentifier) -> [String] {
        ["pr", "ready", String(pr.number), "--repo", pr.repo.description]
    }
}
