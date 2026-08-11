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

    /// Checky na PR (#209) — jak dopadly joby z GitHub Actions a další statusy.
    ///
    /// **Čtení, jako všechno ostatní tady**: restart workflow do aplikace nepatří (tvrdá
    /// podmínka č. 1). PR bez checků vrací prázdno, ne chybu — je to normální stav.
    func fetchChecks(id: PRIdentifier) async throws -> [PullRequestCheck]

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

    /// Anotace check-runu (#214) — `soubor:řádek` a věta od CI.
    ///
    /// `checkRunID` je **totéž číslo jako job ID** z odkazu na check (ověřeno na živém API),
    /// takže se pro něj nechodí zvlášť. Prázdno je běžný stav: anotace emituje jen workflow, které
    /// si o to řekne (problem matcher, reporter), a u běžného `phpunit`/`phpstan` často nejsou.
    func fetchAnnotations(repo: RepoID, checkRunID: Int) async throws -> CheckAnnotations

    /// Kolik má log jobu bajtů, **bez jeho stažení** (#214).
    ///
    /// `HEAD` na `…/actions/jobs/{id}/logs` je levný a **konstantně** levný — změřeno ~1,2 s
    /// u 33 kB i u 8,78 MB. Na tom stojí strop: věta „log má 8,4 MB“ není odhad, protože se
    /// napíše dřív, než by se stahovalo.
    func fetchJobLogSize(repo: RepoID, jobID: Int) async throws -> Int

    /// Log jednoho jobu (#214).
    ///
    /// **Přímé API, ne `gh run view --job --log`**: změřeno 1,50 s / 237 kB proti 4,77 s / 430 kB
    /// za tentýž obsah — `gh run view` k němu jde oklikou a každý řádek prefixuje jménem jobu.
    ///
    /// Vrací **celý** log jedním requestem, takže ořez na konec je věc zobrazení, ne úspory
    /// stahování. Volá se **jen na vyžádání a jen na jeden job** — log celého běhu je log všech
    /// jeho jobů (u změřeného PR 23), tedy N+1 past o tři řády dražší.
    ///
    /// Desátá **čtecí** metoda; tvrdá podmínka č. 1 platí dál — restart workflow tady není.
    func fetchJobLog(repo: RepoID, jobID: Int) async throws -> String
}
