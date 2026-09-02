import Foundation

@testable import PRism

/// Gateway, která nic nespouští — vrací předepsané odpovědi v pořadí, jak se jí volající
/// ptá. Poslední odpověď se opakuje, takže test nemusí předepisovat víc, než ho zajímá.
final class FakeGitHubGateway: GitHubGateway, @unchecked Sendable {
    typealias Outcome = Result<[PullRequestSummary], any Error>

    private let outcomes: [Outcome]
    /// Co vrátí `fetchDetail`. Detail se tahá až kvůli review, takže ho většina testů
    /// nepotřebuje a nechá ho `nil`.
    private let detail: Result<PullRequest, any Error>?
    /// Co vrátí `fetchDiff` — v pořadí, poslední se opakuje. Na střídání selhání a
    /// úspěchu stojí test, že „zkusit znovu“ opravdu načte.
    private let diffs: [Result<String, any Error>]
    /// Co vrátí `fetchDiff(repo:from:to:)`, tedy rozsah „co přibylo“ (#284) — v pořadí,
    /// poslední se opakuje.
    private let rangeDiffs: [Result<String, any Error>]
    /// Co vrátí `fetchFile` — v pořadí, poslední se opakuje.
    private let files: [Result<String, any Error>]
    /// Co vrátí `fetchConversation` — v pořadí, poslední se opakuje.
    private let conversations: [Result<Conversation, any Error>]
    /// Co vrátí `fetchReleases` — v pořadí, poslední se opakuje. Na střídání selhání
    /// a úspěchu stojí test, že „Zkusit znovu“ opravdu načte.
    private let releases: [Result<[Release], any Error>]
    private let lock = NSLock()
    private var asked: [String] = []
    private var detailsAsked: [PRIdentifier] = []
    private var overriddenDetail: Result<PullRequest, any Error>?
    private var detailQueue: [Result<PullRequest, any Error>] = []
    private var detailQueueUsed = 0
    private var diffsAsked: [PRIdentifier] = []
    private var rangeDiffsAsked: [(repo: RepoID, base: String, head: String)] = []
    private var filesAsked: [(id: PRIdentifier, path: String)] = []
    private var conversationsAsked: [PRIdentifier] = []
    private var releasesAsked = 0

    init(
        _ outcomes: [Outcome],
        detail: Result<PullRequest, any Error>? = nil,
        diffs: [Result<String, any Error>] = [],
        rangeDiffs: [Result<String, any Error>] = [],
        files: [Result<String, any Error>] = [],
        conversations: [Result<Conversation, any Error>] = [],
        releases: [Result<[Release], any Error>] = []
    ) {
        self.outcomes = outcomes
        self.detail = detail
        self.diffs = diffs
        self.rangeDiffs = rangeDiffs
        self.files = files
        self.conversations = conversations
        self.releases = releases
    }

    convenience init(
        always outcome: Outcome,
        detail: Result<PullRequest, any Error>? = nil,
        diffs: [Result<String, any Error>] = [],
        rangeDiffs: [Result<String, any Error>] = [],
        files: [Result<String, any Error>] = [],
        conversations: [Result<Conversation, any Error>] = [],
        releases: [Result<[Release], any Error>] = []
    ) {
        self.init(
            [outcome],
            detail: detail,
            diffs: diffs,
            rangeDiffs: rangeDiffs,
            files: files,
            conversations: conversations,
            releases: releases
        )
    }

    /// Čím se `detail` přebije **od teď dál** — nespotřebuje se, platí pro všechna další
    /// volání. Na tom stojí testy, ve kterých PR mezi dvěma tiky dostane nový commit.
    var detailFromNowOn: Result<PullRequest, any Error>? {
        get { lock.withLock { overriddenDetail } }
        set { lock.withLock { overriddenDetail = newValue } }
    }

    /// Odpovědi na `fetchDetail` **v pořadí, poslední se opakuje** — jako u `releases`.
    ///
    /// Existuje kvůli scéně „po force pushi se hlava změnila“ (#466, z proklikání), která se jinak
    /// **nedá složit**: `detailFromNowOn` platí od nastavení dál, takže by novou hlavu viděl
    /// i **pre-flight** a ten by push odmítl jako `headMoved` — tedy přesně to, co se ve scéně stát
    /// nemá. Sekvence odděluje „co GitHub říkal před pushem“ od „co říká po něm“.
    ///
    /// Nastavením se **počítadlo resetuje**, aby test nemusel vědět, kolik dotazů proběhlo předtím.
    var detailsInOrder: [Result<PullRequest, any Error>] {
        get { lock.withLock { detailQueue } }
        set { lock.withLock { detailQueue = newValue; detailQueueUsed = 0 } }
    }

    var detailRequests: [PRIdentifier] { lock.withLock { detailsAsked } }

    /// Kolikrát a na co se někdo ptal na diff. Počet je součást kontraktu: načtený diff
    /// se drží, takže druhý výběr téhož PR se ptát nemá.
    var diffRequests: [PRIdentifier] { lock.withLock { diffsAsked } }

    /// Dotazy v pořadí, jak přišly — na nich se pozná, že se prošly všechny zdroje.
    var queries: [String] { lock.withLock { asked } }

    var searchCount: Int { queries.count }

    func checkAuth() async -> GhAuthState { .loggedIn }

    // MARK: - Kdo se dívá (#330)

    /// Login, který vrátí `fetchViewer`. **Výchozí `nil` znamená „gateway ho nezná“** a volání
    /// vyhodí — schválně, protože to je ten stav, ve kterém aplikace startuje: dokud login
    /// nedorazí, je podle `Policy.ownership` všechno cizí. Test, který o rozřazení stojí, si login
    /// nastaví; ostatním se tím nic nemění.
    var viewer: String?

    /// Čím `fetchViewer` spadne. `nil` = vrátí `viewer`, nebo `notFound`, když ani ten není.
    ///
    /// Vlastní přepínač vedle `viewer`, ne `Result`: „login jsem nezjistil“ a „`gh` selhal“ vedou
    /// ke stejnému prázdnu, a právě proto se musí dát nastavit obojí — jinak nejde ověřit, že se
    /// selhání **neprojeví jako `.mine`**.
    var viewerFailure: (any Error)?

    /// Kolikrát se někdo ptal. Na počtu stojí test, že se login tahá **jednou za spuštění**,
    /// ne na každý tik pollingu.
    var viewerRequests: Int { lock.withLock { viewersAsked } }

    private var viewersAsked = 0

    func fetchViewer() async throws -> String {
        lock.withLock { viewersAsked += 1 }
        if let viewerFailure { throw viewerFailure }
        guard let viewer else { throw GitHubError.notFound("Fake gateway login nezná.") }
        return viewer
    }

    /// Co udělat **uvnitř** běžícího dotazu, ještě než se vrátí odpověď (#442).
    ///
    /// Bez toho se nedá zvenčí sáhnout na stav „právě se ptáme“: `isRefreshing` je pravdivé jen po
    /// dobu, kdy `searchPullRequests` neskončil, takže test, který chce ověřit, že druhé obnovení
    /// v té chvíli neprojde, ho musí spustit odsud. Dotaz se přitom **nedrží** — hook doběhne
    /// a odpověď se vrátí normálně; blokující fake by z čekání udělal další zdroj falešně
    /// červeného `main`u.
    ///
    /// **Pod zámkem, jako `detailFromNowOn`**: `searchPullRequests` je `nonisolated async`, takže
    /// se čte odjinud, než se zapisuje (test píše z `MainActor`u). Fake je `@unchecked Sendable`,
    /// tedy si tu synchronizaci musí obstarat sám.
    var duringSearch: (@Sendable () async -> Void)? {
        get { lock.withLock { searchHook } }
        set { lock.withLock { searchHook = newValue } }
    }

    private var searchHook: (@Sendable () async -> Void)?

    func searchPullRequests(query: String) async throws -> [PullRequestSummary] {
        let index: Int = lock.withLock {
            asked.append(query)
            return asked.count - 1
        }
        // Kopie **před** zavoláním: zámek se drží jen na čtení, ne přes `await` — `NSLock` se
        // odemyká na tom vlákně, na kterém se zamkl, a po suspenzi to nemusí být totéž.
        if let hook = duringSearch { await hook() }
        return try (outcomes[min(index, outcomes.count - 1)]).get()
    }

    /// Polling detail netahá — SHA potřebuje až review, ne seznam.
    /// Co vrátí `fetchChecks` (#209). Většina testů checky nepotřebuje, takže prázdno.
    var checks: [PullRequestCheck] = []
    /// Čím `fetchChecks` spadne (#215). `nil` = vrátí `checks`.
    ///
    /// Vlastní přepínač, ne `Result`: rozdíl mezi „PR nemá CI“ (prázdno) a „nepodařilo se to
    /// zjistit“ (chyba) je přesně to, co se u #215 nesmí slít, takže se musí dát nastavit obojí.
    var checksFailure: (any Error)?

    func fetchChecks(id: PRIdentifier) async throws -> [PullRequestCheck] {
        if let checksFailure { throw checksFailure }
        return checks
    }

    // MARK: - Commity (#316)

    /// Co vrátí `fetchCommits`. Většina testů commity nepotřebuje, takže prázdno.
    var commits: [PullRequestCommit] = []

    /// Čím `fetchCommits` spadne. `nil` = vrátí `commits`.
    ///
    /// Vlastní přepínač, ne `Result`, ze stejného důvodu jako u checků: „prázdná odpověď“
    /// a „nepodařilo se to načíst“ jsou dva stavy, které se nesmí slít — u commitů o to víc, že
    /// prázdno je tam samo o sobě porucha.
    var commitsFailure: (any Error)?

    /// Na co se kdo ptal, v pořadí. Na počtu stojí test, že se seznam **nedotahuje znovu při
    /// každém příchodu na PR**.
    var commitRequests: [PRIdentifier] { lock.withLock { commitsAsked } }

    private var commitsAsked: [PRIdentifier] = []

    func fetchCommits(id: PRIdentifier) async throws -> [PullRequestCommit] {
        lock.withLock { commitsAsked.append(id) }
        if let commitsFailure { throw commitsFailure }
        return commits
    }

    // MARK: - Diff commitu (#317)

    /// Co vrátí `fetchDiff(repo:commit:)`. Výchozí **prázdný text** není lenost: prázdná odpověď
    /// je u commitu platný výsledek (změřeno na `git commit --allow-empty`), takže je to zároveň
    /// ten stav, který se nesmí splést s poruchou.
    var commitDiff = ""
    var commitDiffFailure: (any Error)?
    /// Na které sha se kdo ptal, v pořadí. Na počtu stojí test, že se stažený diff **drží** —
    /// druhé otevření téhož commitu se ptát nemá.
    var commitDiffRequests: [String] { lock.withLock { commitDiffsAsked } }

    private var commitDiffsAsked: [String] = []

    /// Závora **před** vrácením diffu. Na ní se dá pozorovat mezistav `loading`.
    var commitDiffGate: AsyncGate?

    func fetchDiff(repo: RepoID, commit sha: String) async throws -> String {
        lock.withLock { commitDiffsAsked.append(sha) }
        if let commitDiffGate { await commitDiffGate.wait() }
        if let commitDiffFailure { throw commitDiffFailure }
        return commitDiff
    }

    /// Obsah souborů v konkrétním commitu (#317) — v pořadí, poslední se opakuje. Vlastní pole
    /// vedle `files`, protože „soubor na hlavě PR“ a „soubor v commitu“ jsou dvě různé otázky
    /// a test má poznat, kterou se kdo ptal.
    var commitFiles: [Result<String, any Error>] = []
    /// Na co se kdo ptal — z toho se pozná, že se rozbalený kontext bere **z toho commitu**,
    /// ne z hlavy PR.
    var commitFileRequests: [(repo: RepoID, path: String, commit: String)] {
        lock.withLock { commitFilesAsked }
    }

    private var commitFilesAsked: [(repo: RepoID, path: String, commit: String)] = []

    func fetchFile(repo: RepoID, path: String, at commit: String) async throws -> String {
        let index: Int = lock.withLock {
            commitFilesAsked.append((repo, path, commit))
            return commitFilesAsked.count - 1
        }
        guard !commitFiles.isEmpty else {
            throw GitHubError.notFound("Fake gateway obsah souboru v commitu nezná.")
        }
        return try commitFiles[min(index, commitFiles.count - 1)].get()
    }

    // MARK: - Detail checku (#214)

    /// Co vrátí `fetchAnnotations`. Prázdno je běžný stav — workflow anotace emitovat nemusí.
    var annotations = CheckAnnotations()
    var annotationsFailure: (any Error)?
    /// Kolik bajtů hlásí `HEAD`. Na tom stojí strop, takže se musí dát nastavit i „obří“ — **a
    /// `nil`**, tedy „velikost neřekl“: přesně to u #292 vypnulo konec logu u všech checků.
    var logSize: Int? = 1024
    var logSizeFailure: (any Error)?
    var jobLog = ""
    var jobLogFailure: (any Error)?
    /// Na co se kdo ptal, v pořadí — z toho se pozná, že se **pro log nad stropem nešlo**.
    private(set) var logSizesAsked: [Int] = []
    private(set) var logsAsked: [Int] = []
    private(set) var annotationsAsked: [Int] = []

    func fetchAnnotations(repo: RepoID, checkRunID: Int) async throws -> CheckAnnotations {
        annotationsAsked.append(checkRunID)
        if let annotationsFailure { throw annotationsFailure }
        return annotations
    }

    func fetchJobLogSize(repo: RepoID, jobID: Int) async throws -> Int? {
        logSizesAsked.append(jobID)
        if let logSizeFailure { throw logSizeFailure }
        return logSize
    }

    /// Závora **před** vrácením logu. Na ní se dá pozorovat mezistav `.loading` — tedy to, jestli se
    /// do hlášky dostala velikost z `HEAD`u; bez ní se dá zkontrolovat jen výsledek.
    var jobLogGate: AsyncGate?

    func fetchJobLog(repo: RepoID, jobID: Int) async throws -> String {
        logsAsked.append(jobID)
        if let jobLogGate { await jobLogGate.wait() }
        if let jobLogFailure { throw jobLogFailure }
        return jobLog
    }

    // MARK: - Labely a reviewery (#392)

    /// Co vrátí `fetchMetadata`. Výchozí **prázdný snímek**, protože prázdno je platná odpověď:
    /// PR bez labelů a bez vyžádaných reviewerů je běžný.
    var metadata = PullRequestMetadata()

    /// Čím `fetchMetadata` spadne. `nil` = vrátí `metadata`.
    ///
    /// Vlastní přepínač, ne `Result`, ze stejného důvodu jako u checků: „PR nemá labely“ a „nešlo
    /// to zjistit“ jsou dva stavy, které se u téhle sekce nesmí slít — podle prvního se sekce
    /// nekreslí, podle druhého se nesmí dát měnit sada, kterou aplikace nezná.
    var metadataFailure: (any Error)?

    /// Na co se kdo ptal, v pořadí. Na počtu stojí test, že se snímek **nedotahuje znovu při
    /// každém příchodu na PR**.
    var metadataRequests: [PRIdentifier] { lock.withLock { metadataAsked } }

    private var metadataAsked: [PRIdentifier] = []

    func fetchMetadata(id: PRIdentifier) async throws -> PullRequestMetadata {
        lock.withLock { metadataAsked.append(id) }
        if let metadataFailure { throw metadataFailure }
        return metadata
    }

    /// Co vrátí `fetchBranchStatus` (#465). Výchozí je **usazené `MERGEABLE`/`CLEAN`**, protože
    /// v drtivé většině testů jde o něco jiného a `UNKNOWN` by tam potichu zakázalo merge.
    var branchStatus = BranchStatus(mergeability: .mergeable, mergeState: .clean)

    /// Čím `fetchBranchStatus` spadne. `nil` = vrátí `branchStatus`.
    ///
    /// Vlastní přepínač, ne `Result`, ze stejného důvodu jako u labelů: „nedá se mergnout“
    /// a „nezjistil jsem to“ se u nevratné akce nesmí slít.
    var branchStatusFailure: (any Error)?

    /// Na co se kdo ptal, v pořadí. Na počtu stojí testy, které tvrdí, že se **na cizí PR
    /// neptáme vůbec**.
    var branchStatusRequests: [PRIdentifier] { lock.withLock { branchStatusAsked } }

    /// **Čím** se ptalo na polohu větve (#466) — základ a hlava. Vlastní typ, ne tuple: tuple
    /// v Swiftu není `Equatable`, takže by se pole nedalo srovnat jedním tvrzením.
    struct BranchStatusQuery: Equatable, Sendable {
        let id: PRIdentifier
        let base: String
        let head: String
    }

    var branchStatusQueries: [BranchStatusQuery] { lock.withLock { branchStatusAskedAbout } }

    private var branchStatusAsked: [PRIdentifier] = []
    private var branchStatusAskedAbout: [BranchStatusQuery] = []

    func fetchBranchStatus(id: PRIdentifier, base: String, head: String) async throws -> BranchStatus {
        lock.withLock {
            branchStatusAsked.append(id)
            branchStatusAskedAbout.append(BranchStatusQuery(id: id, base: base, head: head))
        }
        if let branchStatusFailure { throw branchStatusFailure }
        return branchStatus
    }

    /// Co vrátí `fetchDivergence` (#466). **Vlastní hodnota, ne `branchStatus.divergence`** — celý
    /// smysl té metody je, že se odpověď na „pozadu“ může změnit, aniž by se změnilo cokoli
    /// ostatního, a s jedním polem by se ten případ nedal napsat.
    var divergence: BranchDivergence?

    /// Čím `fetchDivergence` spadne. `nil` = vrátí `divergence`.
    var divergenceFailure: (any Error)?

    /// Na co se kdo ptal, v pořadí. Na počtu stojí tvrzení, že se **na cizí ani na neotevřené PR
    /// neptáme vůbec**.
    var divergenceQueries: [BranchStatusQuery] { lock.withLock { divergenceAskedAbout } }

    private var divergenceAskedAbout: [BranchStatusQuery] = []

    func fetchDivergence(id: PRIdentifier, base: String, head: String) async throws -> BranchDivergence? {
        lock.withLock {
            divergenceAskedAbout.append(BranchStatusQuery(id: id, base: base, head: head))
        }
        if let divergenceFailure { throw divergenceFailure }
        return divergence
    }

    // MARK: - Repozitáře organizace (#532)

    /// Co vrátí `repositories(in:)` pro danou organizaci. Chybějící klíč = prázdný výpis.
    var organizationRepositories: [String: OrganizationRepositories] = [:]
    /// Čím `repositories(in:)` spadne. Klíčem je organizace, aby šlo mít jednu funkční a jednu
    /// nedostupnou naráz — což je zrovna ta scéna, kvůli které se chyba hlásí u řádku.
    var organizationFailures: [String: any Error] = [:]
    /// Na co se kdo ptal, **v pořadí**. Na počtu stojí test, že se výpis nedotahuje při každém
    /// úhozu — jinak by tenhle typ o téhle vlastnosti netvrdil nic.
    var repositoryRequests: [String] { lock.withLock { repositoriesAsked } }

    private var repositoriesAsked: [String] = []

    func repositories(in organization: String) async throws -> OrganizationRepositories {
        lock.withLock { repositoriesAsked.append(organization) }
        if let failure = organizationFailures[organization] { throw failure }
        return organizationRepositories[organization]
            ?? OrganizationRepositories(repositories: [], hitLimit: false)
    }

    /// Labely, které zná repo. Prázdno je platná odpověď — a hlavně: z prázdné nabídky nejde
    /// vyrobit label.
    var repositoryLabels: [PullRequestLabel] = []
    var repositoryLabelsFailure: (any Error)?
    /// Na co se kdo ptal. Na počtu stojí test, že se nabídka tahá **jednou**, ne při každém
    /// otevření.
    var repositoryLabelRequests: [RepoID] { lock.withLock { repositoryLabelsAsked } }

    private var repositoryLabelsAsked: [RepoID] = []

    func fetchRepositoryLabels(repo: RepoID) async throws -> [PullRequestLabel] {
        lock.withLock { repositoryLabelsAsked.append(repo) }
        if let repositoryLabelsFailure { throw repositoryLabelsFailure }
        return repositoryLabels
    }

    var assignableUsers: [String] = []
    var assignableUsersFailure: (any Error)?
    var assignableUserRequests: [RepoID] { lock.withLock { assignableUsersAsked } }

    private var assignableUsersAsked: [RepoID] = []

    func fetchAssignableUsers(repo: RepoID) async throws -> [String] {
        lock.withLock { assignableUsersAsked.append(repo) }
        if let assignableUsersFailure { throw assignableUsersFailure }
        return assignableUsers
    }

    /// Slugy týmů. Prázdno je platná odpověď — repo mimo organizaci týmy nemá.
    var assignableTeams: [String] = []
    var assignableTeamsFailure: (any Error)?
    var assignableTeamRequests: [RepoID] { lock.withLock { assignableTeamsAsked } }

    private var assignableTeamsAsked: [RepoID] = []

    func fetchAssignableTeams(repo: RepoID) async throws -> [String] {
        lock.withLock { assignableTeamsAsked.append(repo) }
        if let assignableTeamsFailure { throw assignableTeamsFailure }
        return assignableTeams
    }

    // MARK: - Hlavy dávkou (#420)

    /// Co vrátí `fetchHeads(of:)`, klíčované PR. **Chybějící klíč není chyba** — je to ta odpověď,
    /// kterou GitHub dá u repa, na které nevidíme, a která se nesmí splést s „hlava se neposunula“.
    var heads: [PRIdentifier: PullRequestHead] = [:]

    /// Čím `fetchHeads(of:)` spadne. `nil` = vrátí, co je v `heads`.
    var headsFailure: (any Error)?

    /// **Na co se kdo ptal, po jednotlivých voláních.** Vnořené pole je tady to podstatné: na něm
    /// stojí tvrzení, že se za tik pošle **jeden** dotaz na celou frontu, ne jeden na PR ani jeden
    /// na repozitář. Plochý seznam by ten rozdíl neuměl vyjádřit.
    var headRequests: [[PRIdentifier]] { lock.withLock { headsAsked } }

    private var headsAsked: [[PRIdentifier]] = []
    private var headsQueue: [[PRIdentifier: PullRequestHead]] = []
    private var headsQueueUsed = 0

    /// Odpovědi na `fetchHeads` **v pořadí, poslední se opakuje** — jako `detailsInOrder`.
    ///
    /// Existuje kvůli scéně „po force pushi GitHub chvíli hlásí starou hlavu“ (#466, změřeno
    /// 1,45–2,16 s). Časovat ji odmlkou v testu **nešlo**: první dotaz na hlavu padne až za
    /// podprocesem `git`, takže se pauza rozešla s tím, co se měřilo, a test byl falešně zelený.
    /// Sekvence tu časovou závislost odstraňuje úplně.
    var headsInOrder: [[PRIdentifier: PullRequestHead]] {
        get { lock.withLock { headsQueue } }
        set { lock.withLock { headsQueue = newValue; headsQueueUsed = 0 } }
    }

    func fetchHeads(of ids: [PRIdentifier]) async throws -> [PRIdentifier: PullRequestHead] {
        // Prázdný dotaz se nezaznamenává ani nespouští — jako ve `GhGateway`, ať se na tom dá
        // tvrdit, že se na nic neptáme.
        guard !ids.isEmpty else { return [:] }
        let queued: [PRIdentifier: PullRequestHead]? = lock.withLock {
            headsAsked.append(ids)
            guard !headsQueue.isEmpty else { return nil }
            let answer = headsQueue[min(headsQueueUsed, headsQueue.count - 1)]
            headsQueueUsed += 1
            return answer
        }
        if let headsFailure { throw headsFailure }
        return (queued ?? heads).filter { ids.contains($0.key) }
    }

    func fetchDetail(id: PRIdentifier) async throws -> PullRequest {
        let answer: Result<PullRequest, any Error>? = lock.withLock {
            detailsAsked.append(id)
            if !detailQueue.isEmpty {
                // Poslední se opakuje, takže sekvence nikdy „nedojde“ — dojití by z chybějící
                // odpovědi udělalo `notFound`, tedy jinou scénu, než jakou test píše.
                let answer = detailQueue[min(detailQueueUsed, detailQueue.count - 1)]
                detailQueueUsed += 1
                return answer
            }
            return overriddenDetail ?? detail
        }
        guard let answer else { throw GitHubError.notFound("Fake gateway detail nezná.") }
        return try answer.get()
    }

    /// Na co se někdo ptal, v pořadí. Na počtu stojí test, že se obsah souboru dotahuje
    /// jednou, ne při každém rozbalení.
    var fileRequests: [(id: PRIdentifier, path: String)] { lock.withLock { filesAsked } }

    func fetchFile(id: PRIdentifier, path: String) async throws -> String {
        let index: Int = lock.withLock {
            filesAsked.append((id, path))
            return filesAsked.count - 1
        }
        guard !files.isEmpty else { throw GitHubError.notFound("Fake gateway soubor nezná.") }
        return try files[min(index, files.count - 1)].get()
    }

    func fetchDiff(id: PRIdentifier) async throws -> String {
        let index: Int = lock.withLock {
            diffsAsked.append(id)
            return diffsAsked.count - 1
        }
        guard !diffs.isEmpty else { throw GitHubError.notFound("Fake gateway diff nezná.") }
        return try diffs[min(index, diffs.count - 1)].get()
    }

    /// Na co se někdo ptal u rozsahového diffu (#284), v pořadí. Na obsahu stojí test, že se
    /// ptáme na **viděnou** hlavu proti dnešní, ne obráceně.
    var rangeDiffRequests: [(repo: RepoID, base: String, head: String)] {
        lock.withLock { rangeDiffsAsked }
    }

    func fetchDiff(repo: RepoID, from base: String, to head: String) async throws -> String {
        let index: Int = lock.withLock {
            rangeDiffsAsked.append((repo, base, head))
            return rangeDiffsAsked.count - 1
        }
        guard !rangeDiffs.isEmpty else {
            throw GitHubError.notFound("Fake gateway rozsahový diff nezná.")
        }
        return try rangeDiffs[min(index, rangeDiffs.count - 1)].get()
    }

    /// Na co se někdo ptal, v pořadí.
    var conversationRequests: [PRIdentifier] { lock.withLock { conversationsAsked } }

    func fetchConversation(id: PRIdentifier) async throws -> Conversation {
        let index: Int = lock.withLock {
            conversationsAsked.append(id)
            return conversationsAsked.count - 1
        }
        guard !conversations.isEmpty else {
            throw GitHubError.notFound("Fake gateway konverzaci nezná.")
        }
        return try conversations[min(index, conversations.count - 1)].get()
    }

    /// Kolikrát se někdo ptal na vydání. Na počtu stojí test, že se historie tahá **jednou
    /// za běh**, ne při každém otevření okna.
    var releaseRequests: Int { lock.withLock { releasesAsked } }

    func fetchReleases() async throws -> [Release] {
        let index: Int = lock.withLock {
            releasesAsked += 1
            return releasesAsked - 1
        }
        guard !releases.isEmpty else {
            throw GitHubError.notFound("Fake gateway vydání nezná.")
        }
        return try releases[min(index, releases.count - 1)].get()
    }
}
