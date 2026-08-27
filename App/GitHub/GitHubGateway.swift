import Foundation

/// Jediná cesta aplikace k GitHubu.
///
/// Za protokolem, aby šla v testech nahradit fake implementací. **Vůči GitHubu jen pro
/// čtení** — protokol schválně nemá nic, čím by šlo něco odeslat.
protocol GitHubGateway: Sendable {
    /// Průběžná kontrola přihlášení. Nevrací chybu: „nepřihlášen" je normální stav, který
    /// aplikace ukazuje, ne selhání volání.
    func checkAuth() async -> GhAuthState

    /// Login přihlášeného účtu (#330) — **kdo se dívá**.
    ///
    /// Na tom stojí rozřazení seznamu podle autora (`Policy.ownership`): bez něj jsou vlastní PR
    /// od cizích k nerozeznání. Volá se **jednou za spuštění**, ne na tik pollingu — není to údaj
    /// o PR a `gh` se mezi dvěma tiky nepřehlásí.
    ///
    /// **Přes `gh api user`, ne rozborem `gh auth status`.** Login je i v `auth status`, který se
    /// volá už dneska (`GhAuthCheck`), takže by to bylo zadarmo — je to ale výstup **pro člověka**,
    /// ne kontrakt. Až se ta věta v nějaké verzi `gh` přeformuluje, přestane fungovat **rozřazení
    /// seznamu**, ne kontrola přihlášení, a pozná se to podle toho, že vlastní PR zmizí z vlastní
    /// sekce. Změřeno na tomhle stroji: `gh api user` 0,55 s proti 0,42 s u `auth status`, a platí
    /// se to jednou za spuštění. `GhAuthState` se kvůli tomu **nerozšiřuje** — odpovídá na „jsem
    /// přihlášený“ a druhá hodnota v něm by znamenala, že se týž údaj bere ze dvou míst.
    ///
    /// **Prázdný login není platná odpověď**, proto se vyhazuje: „nevím, kdo jsem“ znamená podle
    /// `Policy.ownership` všechno cizí, a to se od skutečného loginu musí poznat.
    ///
    /// Šestnáctá **čtecí** metoda protokolu; tvrdá podmínka č. 1 platí dál — gateway pořád nemá
    /// nic, čím by šlo něco odeslat.
    func fetchViewer() async throws -> String

    /// Vyhledá PR podle search dotazu (jeden zdroj = jeden dotaz).
    func searchPullRequests(query: String) async throws -> [PullRequestSummary]

    /// Doplní metadata, která vyhledávání nedává — hlavně `headSha` a `baseSha`.
    func fetchDetail(id: PRIdentifier) async throws -> PullRequest

    /// Hlavy **víc pull requestů jedním voláním** (#420) — sha a kdy vznikla.
    ///
    /// Existuje proto, že `gh search prs` `headSha` nenese, takže se z tiku nedá poznat, že se
    /// hlava posunula pod uloženými nálezy (tvrdá podmínka č. 5). Jedinou další cestou je
    /// `fetchDetail(id:)` na každou PR, tedy `N+1` dotazů každou minutu — a to je ta past, kvůli
    /// které se pollingem netahá ani detail, ani konverzace.
    ///
    /// **Jedno volání na celou frontu, ne jedno na repozitář.** Skládá to `PullRequestHeadsQuery`
    /// z aliasovaných kořenových polí; změřeno na živém API, že 12 aliasů z 10 repozitářů stojí
    /// **1 bod z 5000/h** (24 aliasů taky) a odpověď má 1,9 kB. Prázdný seznam se **na nic
    /// neptá** — `query() { }` není platný dokument a nula PR nemá co vracet.
    ///
    /// **Částečná odpověď je odpověď.** PR, na kterou GitHub neodpoví (přejmenované repo, smazaný
    /// pull request, chybějící právo), v mapě prostě **není** — `gh` u toho skončí nenulově, ale
    /// data pošle, takže se jednou nedostupnou PR nemá proč zahodit zbytek fronty. „Nevíme“ se od
    /// „hlava se neposunula“ musí poznat, jinak by se z chybějící odpovědi stalo tvrzení.
    ///
    /// **Dvacátá první čtecí metoda** protokolu; tvrdá podmínka č. 1 platí dál — čtení je čtení
    /// a gateway pořád nemá nic, čím by šlo něco odeslat.
    func fetchHeads(of ids: [PRIdentifier]) async throws -> [PRIdentifier: PullRequestHead]

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

    /// Diff **mezi dvěma commity** — „co od minule přibylo“ (#284).
    ///
    /// Vlastní metoda, protože `fetchDiff(id:)` umí jedině celý PR (`baseSha...HEAD`) a rozsah
    /// z něj nijak nevyřízneme.
    ///
    /// **Přes GitHub, ne přes klon v cache**, a je to změřené rozhodnutí, ne pohodlí:
    /// `refs/prism/pr/<n>` v klonu vzniká teprve při checkoutu kvůli review a `forgetPullRequest`
    /// ho maže, takže u většiny PR by se tlačítko nenabídlo; klon je navíc `--filter=blob:none`,
    /// takže by si `git diff` musel obsah stejně dotáhnout ze sítě — jen oklikou přes cestu,
    /// která se lazy fetchi schválně brání. `gh api compare` je jedno volání, ~0,7 s.
    ///
    /// Jedenáctá **čtecí** metoda protokolu; tvrdá podmínka č. 1 platí dál — gateway pořád nemá
    /// nic, čím by šlo něco odeslat.
    func fetchDiff(repo: RepoID, from base: String, to head: String) async throws -> String

    /// Diff **jednoho commitu** (#317) — co přinesl tenhle krok.
    ///
    /// **Vlastní metoda vedle `fetchDiff(repo:from:to:)`, ne parametr navíc.** Obojí jde na
    /// `gh api` s `Accept: application/vnd.github.diff`, takže je pokušení mít jednu — jenže to
    /// nejsou dvě podoby téže otázky. `compare/<a>...<b>` odpovídá na „co je mezi dvěma hlavami“,
    /// `commits/<sha>` na „co přinesl tenhle commit“, tedy diff **proti prvnímu rodiči**. Napsat
    /// druhé přes první (`<sha>^...<sha>`) by u sloučení odpověď tiše změnilo: trojtečka počítá od
    /// společného předka, takže by ukázala i to, co přinesla přisloučená větev. Sdílené je proto
    /// jen to, co doopravdy sdílené je — složení příkazu, viz `GhGateway.diffText(at:)`.
    ///
    /// Počet souborů a `+X −Y` se počítají **z tohohle textu**, takže hlavička rozkliknutého
    /// commitu nestojí volání navíc. Změřeno 0,70–1,78 s na `keboola/job-queue#727`.
    ///
    /// **Prázdná odpověď je platný výsledek, ne porucha** — změřeno na témž PR: tři commity
    /// z `git commit --allow-empty` (přetočení CI) vrátily **nula bajtů** s nulovým návratovým
    /// kódem. Volající to musí umět říct větou, viz `Policy.commitDiffTab`.
    ///
    /// Třináctá **čtecí** metoda protokolu; tvrdá podmínka č. 1 platí dál — gateway pořád nemá
    /// nic, čím by šlo něco odeslat.
    func fetchDiff(repo: RepoID, commit sha: String) async throws -> String

    /// Obsah souboru na hlavě pull requestu — kvůli rozbalení kontextu mimo hunky.
    ///
    /// Diff sám okolní řádky nenese a pracovní kopie v tu chvíli existovat nemusí, takže
    /// se soubor čte přímo z GitHubu.
    func fetchFile(id: PRIdentifier, path: String) async throws -> String

    /// Obsah souboru **v konkrétním commitu** (#317) — kvůli rozbalení kontextu v diffu commitu.
    ///
    /// **Vlastní metoda vedle `fetchFile(id:path:)`, a gitová reference schválně není parametr.**
    /// „Soubor na hlavě PR“ a „soubor v tomhle commitu“ jsou dvě různé otázky s různou zárukou:
    /// první se posune s každým pushnutím, druhá je zmrazená. Kdyby se ref předával jako řetězec,
    /// věděl by o syntaxi gitových referencí `AppStore` a kterýkoli volající by si mohl říct
    /// o cokoli; takhle je z podpisu vidět, na co se dá zeptat.
    ///
    /// Bez ní by rozbalený kontext u staršího commitu ukazoval řádky z **dnešní** hlavy, tedy
    /// posunuté o všechno, co mezitím přibylo — a to potichu, protože kód okolo hunku vypadá
    /// stejně věrohodně, ať je z kteréhokoli commitu.
    ///
    /// Čtrnáctá **čtecí** metoda protokolu; tvrdá podmínka č. 1 platí dál.
    func fetchFile(repo: RepoID, path: String, at commit: String) async throws -> String

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

    /// Kolik má log jobu bajtů, **bez jeho stažení** (#214). `nil` = nevíme.
    ///
    /// `HEAD` na `…/actions/jobs/{id}/logs` je levný a **konstantně** levný — změřeno ~1,2 s
    /// u 33 kB i u 8,78 MB. Na tom stojí strop: věta „log má 8,4 MB“ není odhad, protože se
    /// napíše dřív, než by se stahovalo.
    ///
    /// **`nil` je odpověď, ne selhání** (#292). Velikost stojí na rozboru hlaviček, a ten se dá
    /// minout snáz než dotaz sám — u #292 na něm skončil konec logu u všech checků. Volající si
    /// proto strop uplatní na stažený text: `HEAD` je **ochrana proti osmimegovému logu, ne
    /// podmínka toho, že se log ukáže**.
    func fetchJobLogSize(repo: RepoID, jobID: Int) async throws -> Int?

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

    /// Labely a vyžádaní reviewery pull requestu (#392) — dvě sekce v pravém panelu.
    ///
    /// **Vlastní volání vedle `fetchDetail`, ne pole navíc v něm.** Detail si tahá i pre-flight
    /// publisheru před **každým** odesláním, a odpověď reviewera se skládá z `latestReviews`, tedy
    /// z pole, které nese celá těla review (změřeno na `cli/cli`: 1,5 kB za jedno review od bota).
    /// Platit tu velikost při každém odeslání za údaj, který odesílání nezajímá, nemá důvod.
    ///
    /// Prázdný snímek je **platný výsledek**, ne porucha: PR bez labelů i bez vyžádaných reviewerů
    /// je běžný. Že se to nepodařilo zjistit, si volající drží zvlášť (`MetadataState`) — „nic tu
    /// není“ a „nevím“ se u téhle sekce nesmí slít, protože podle prvního se kreslí prázdno a podle
    /// druhého se nesmí dát měnit sada, kterou aplikace nezná.
    ///
    /// **Sedmnáctá čtecí metoda** protokolu; tvrdá podmínka č. 1 platí dál — gateway pořád nemá
    /// nic, čím by šlo něco odeslat. Změnit label umí `ReviewPublishing`, a jedině on.
    func fetchMetadata(id: PRIdentifier) async throws -> PullRequestMetadata

    /// Labely, které **zná repozitář** (#392) — uzavřená množina, ze které se vybírá.
    ///
    /// Na tom stojí rozhodnutí, že `+ label` není volný text: z volného textu se dá omylem vyrobit
    /// nový label, a ten už z repozitáře sám nezmizí. Nabídka proto nesmí mít jiný zdroj než tenhle.
    ///
    /// **Osmnáctá čtecí metoda**; čtení je čtení, tvrdá podmínka č. 1 platí dál.
    func fetchRepositoryLabels(repo: RepoID) async throws -> [PullRequestLabel]

    /// Loginy lidí, kteří na repo smí (#392) — nabídka k `Vyžádat review od …`.
    ///
    /// **Devatenáctá čtecí metoda**; čtení je čtení. Vyžádání samo jde přes `ReviewPublishing`.
    func fetchAssignableUsers(repo: RepoID) async throws -> [String]

    /// Slugy týmů, které jde na repu vyžádat (#392) — druhá polovina nabídky k `+ reviewer`.
    ///
    /// **Přes `orgs/{org}/teams`, ne `repos/{o}/{r}/teams`**, a je to změřené: repozitářová varianta
    /// vrátila **404** i na repu, kam se dá normálně číst a psát PR (`keboola/platform-architecture-and-concepts`),
    /// protože chce admin práva. Organizační seznam prošel (34 týmů, 0,63 s).
    ///
    /// **Prázdno u účtu bez organizace je odpověď, ne porucha.** Osobní repo týmy nemá a `orgs/…`
    /// na něj vrací 404 — vyhodit kvůli tomu chybu by znamenalo, že nabídka reviewerů hlásí poruchu
    /// u každého repa mimo organizaci.
    ///
    /// **Dvacátá čtecí metoda**; čtení je čtení, tvrdá podmínka č. 1 platí dál.
    func fetchAssignableTeams(repo: RepoID) async throws -> [String]

    /// Commity pull requestu (#316) — seznam do tabu `Commity`.
    ///
    /// **Jedno volání na celý seznam**: sha, zpráva, jméno a datum autora i adresa jeho obrázku
    /// jsou v téže odpovědi. Změřeno 1,20 s pro sedm commitů.
    ///
    /// **Ne přes klon v cache.** `RepoCheckout` fetchuje `refs/pull/<n>/head` do `refs/prism/pr/<n>`,
    /// ale jen když proběhl checkout kvůli review, a `forgetPullRequest` ten ref maže — ověřeno,
    /// takže by tab u poloviny PR neměl data.
    ///
    /// Vrací je **v pořadí, v jakém přišly** (GitHub je dává od nejstaršího); pořadí, ve kterém se
    /// kreslí, je **rozhodnutí, ne tvar odpovědi** — otáčí ho `Policy.commitsNewestFirst`. Tatáž
    /// hranice jako u `fetchReleases` a `Policy.sortedReleases`.
    ///
    /// **Dvanáctá** čtecí metoda (jedenáctá, než se vedle přidal `fetchDiff(repo:from:to:)` z #284);
    /// tvrdá podmínka č. 1 platí dál — gateway pořád nemá nic, čím by šlo něco odeslat.
    func fetchCommits(id: PRIdentifier) async throws -> [PullRequestCommit]

    /// Jestli se dá větev mergnout a co tomu podle pravidel repozitáře brání (#465) — sekce
    /// `Větev` v panelu.
    ///
    /// **Ptá se opakovaně, a je to celý smysl téhle metody.** `mergeable` i `mergeStateStatus`
    /// jsou u GitHubu **líná pole**: první dotaz po pushi (a po založení PR) vrátí `UNKNOWN`
    /// a teprve tím dotazem se výpočet spustí. Kdo se zeptá jednou, dostane odpověď „nevím“
    /// podle náhody — a z ní zašedlé tlačítko `Mergnout…` u PR, který je zeleny. Kolik pokusů
    /// a jak dlouho čekat, drží implementace; volající dostane **usazenou** odpověď, nebo
    /// `UNKNOWN` po vyčerpání pokusů, což je pořád odpověď.
    ///
    /// **Dvaadvacátá metoda protokolu**; čtení je čtení a tvrdá podmínka č. 1 platí dál —
    /// mergnout umí jedině `ReviewPublishing`.
    func fetchBranchStatus(id: PRIdentifier) async throws -> BranchStatus
}
