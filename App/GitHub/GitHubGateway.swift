import Foundation

/// Jediná cesta aplikace k GitHubu.
///
/// Za protokolem, aby šla v testech nahradit fake implementací. **Vůči GitHubu jen pro
/// čtení** — protokol schválně nemá nic, čím by šlo něco odeslat.
protocol GitHubGateway: Sendable {
    /// Průběžná kontrola přihlášení. Nevrací chybu: „nepřihlášen" je normální stav, který
    /// aplikace ukazuje, ne selhání volání.
    func checkAuth() async -> GhAuthState

    /// Vyhledá PR podle search dotazu (jeden zdroj = jeden dotaz).
    func searchPullRequests(query: String) async throws -> [PullRequestSummary]

    /// Doplní metadata, která vyhledávání nedává — hlavně `headSha` a `baseSha`.
    func fetchDetail(id: PRIdentifier) async throws -> PullRequest

    /// Diff pull requestu jako **syrový text** unified diffu.
    ///
    /// Nerozparsovaný schválně: tvar diffu není nic, co by `gh` definoval (na rozdíl od
    /// `--json` polí), takže mu rozumí až `DiffParser`. Diff je **jen k zobrazení** —
    /// reviewery čtou skutečné soubory v pracovním stromě.
    func fetchDiff(id: PRIdentifier) async throws -> String
}
