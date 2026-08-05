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

    /// Obsah souboru na hlavě pull requestu — kvůli rozbalení kontextu mimo hunky.
    ///
    /// Diff sám okolní řádky nenese a pracovní kopie v tu chvíli existovat nemusí, takže
    /// se soubor čte přímo z GitHubu.
    func fetchFile(id: PRIdentifier, path: String) async throws -> String

    /// Konverzace pod PR — review ostatních, vlákna u řádků a komentáře.
    ///
    /// Jedním GraphQL dotazem, protože REST `isResolved` u vláken nemá vůbec a byly by to
    /// tři podprocesy. Pořád **jen pro čtení**: odpovídat do vláken umí až #73, a i pak to
    /// půjde přes `ReviewPublisher`, ne odsud.
    func fetchConversation(id: PRIdentifier) async throws -> Conversation

    /// Vydání vlastního repa aplikace — co je v okně s novinkami (#127).
    ///
    /// **Celá historie stojí jedno volání**: tělo releasu je rovnou v seznamu, takže se na
    /// jednotlivou verzi nechodí zvlášť. Změřeno nad 69 releasy — jedna stránka, ~1 s.
    ///
    /// Repozitář se **nepředává**: je to `Release.repository`, tedy vlastní repo aplikace.
    /// Parametr by sliboval, že se dá ptát i jinam, což tahle metoda neumí a nemá umět.
    ///
    /// Sedmá **čtecí** metoda protokolu, takže tvrdá podmínka č. 1 platí dál: gateway pořád
    /// nemá nic, čím by šlo něco odeslat.
    func fetchReleases() async throws -> [Release]
}
