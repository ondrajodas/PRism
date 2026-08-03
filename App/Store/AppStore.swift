import Foundation
import Observation

/// Stav aplikace, který kreslí okno.
///
/// Drží polling seznamu PR, výběr řádku a stav pracovních kopií. Výběr žije tady, ne ve
/// view — jinak by ho každé přestavění seznamu zahodilo. Postupně sem přibude stav
/// běžících review a limit souběžných session.
@MainActor
@Observable
final class AppStore {
    /// Který řádek je vybraný.
    var selection: PRIdentifier?

    /// Stav pracovní kopie **per repo**. Co v mapě není, v cache není.
    ///
    /// Jediný zdroj pravdy o checkoutu: `ReviewState` pro řádek se z něj odvozuje
    /// (`Policy.reviewState(for:)`) a `busy` pro eviction taky. Dvě mapy s různými klíči
    /// si dokázaly odporovat — jedno PR hlásilo selhání nad klonem, který mezitím pro
    /// druhé PR téhož repa v pořádku vznikl.
    private(set) var checkoutStates: [RepoID: CheckoutState] = [:]

    /// Co se s review právě děje. Co v mapě není, neběží.
    private(set) var reviewPhases: [PRIdentifier: ReviewPhase] = [:]

    /// Poslední známý výsledek per PR — z disku při startu, pak z doběhlých běhů.
    ///
    /// Na disku je záznamů víc (historie po commitech), tady je vždycky jen ten platný;
    /// který to je, rozhoduje `Policy.currentRecords(from:)`.
    private(set) var reviewRecords: [PRIdentifier: ReviewRecord] = [:]

    /// Diff **per PR**. Co v mapě není, se ještě nenačítalo.
    private(set) var diffStates: [PRIdentifier: DiffState] = [:]

    /// Rozbalený kontext **per soubor v PR**. Co v mapě není, nikdo nerozbaloval.
    private(set) var expansions: [FileExpansionKey: FileExpansion] = [:]

    /// Sbalené soubory diffu. Co v množině **není**, je rozbalené — u PR o padesáti
    /// souborech je rozbaleno výchozí stav a sbalení je gesto, takže se pamatuje to druhé.
    ///
    /// Žije tady, ne ve view: `PullRequestDetailView` si SwiftUI mezi PR ponechá (stejná
    /// pozice ve stromu), takže by sbalení přeteklo z jednoho pull requestu na druhý.
    private(set) var foldedFiles: Set<FileExpansionKey> = []

    /// Co reviewery dělaly, per PR. Drží se i po doběhnutí — právě tehdy se k tomu člověk
    /// vrací. Pořadí kopíruje pořadí, ve kterém běhy začaly.
    private(set) var reviewTimelines: [PRIdentifier: [ReviewerTimeline]] = [:]

    /// Je otevřené okno nastavení? Hlavní okno se podle toho rozostří, aby netahalo oko.
    ///
    /// Žije tady, ne ve view: okno nastavení je **vlastní scéna**, takže si to dvě okna
    /// nemají kde říct jinudy.
    var isSettingsOpen = false

    /// Nastavení, se kterým aplikace běží.
    private(set) var configuration: Configuration
    /// Proč se konfiguraci nepodařilo přečíst nebo uložit. Ani jedno nesmí aplikaci
    /// položit, ale ani projít tiše — jinak uživatel hledá, proč mu nastavení nefunguje.
    private(set) var configurationFailure: String?

    /// Kolik uložených souborů s nálezy se nepodařilo přečíst.
    ///
    /// Musí být vidět: rozbitý soubor znamená ztracené nálezy, a ty se nesmí tvářit jako
    /// „review neběželo“.
    private(set) var unreadableReviewFiles = 0

    private let time: any TimeSource
    private let polling: PollingService
    private let gateway: any GitHubGateway
    private let checkout: (any RepoCheckout)?
    private let reviewer: (any ReviewRunning)?
    private let reviews: ReviewStore?
    private let translator: (any FindingTranslating)?
    private let configStore: ConfigStore?
    /// Běžící review podle PR — drží se kvůli zrušení.
    private var reviewTasks: [PRIdentifier: Task<Void, Never>] = [:]
    /// Review, která spustil **automat**. Ruční se pozná tím, že tady není — a jen ta
    /// automatická se ruší, když PR zmizí ze seznamu.
    private var automaticReviews: Set<PRIdentifier> = []
    /// `updatedAt`, se kterým se PR naposledy zvažoval pro automat.
    ///
    /// V paměti, ne na disku: po restartu se zváží znovu, což stojí jedno `gh pr view` na
    /// PR. Session se za to neutratí — o tu rozhoduje až porovnání `headSha`.
    private var consideredForAutomation: [PRIdentifier: Date] = [:]
    private let autoRuns: AutoRunLedger?

    init(
        gateway: any GitHubGateway,
        configuration: Configuration = .standard,
        configStore: ConfigStore? = nil,
        time: any TimeSource = SystemTimeSource(),
        eviction: CacheEviction? = nil,
        checkout: (any RepoCheckout)? = nil,
        reviewer: (any ReviewRunning)? = nil,
        reviews: ReviewStore? = nil,
        translator: (any FindingTranslating)? = nil,
        autoRuns: AutoRunLedger? = nil
    ) {
        self.time = time
        self.configuration = configuration
        self.configStore = configStore
        polling = PollingService(
            gateway: gateway,
            sources: configuration.activeSources,
            interval: .seconds(configuration.global.pollIntervalSeconds),
            time: time
        )
        self.gateway = gateway
        self.checkout = checkout
        self.reviewer = reviewer
        self.reviews = reviews
        self.translator = translator
        self.autoRuns = autoRuns
        polling.afterSuccessfulTick = { [weak self] summaries in
            await self?.forget(whatIsNotIn: summaries)
            // Až po `forget`: PR, který ze seznamu vypadl, se nemá čím spustit, a běžící
            // automat nad ním se má naopak zrušit.
            await self?.startAutomaticReviews(for: summaries)
            // `busy` se nepředává jako snímek, ale jako dotaz: eviction je dlouhá disková
            // operace a příprava, která začne uprostřed ní, by jinak přišla o ochranu.
            let busy: @Sendable () async -> Set<RepoID> = { [weak self] in
                await self?.busyRepositories ?? []
            }
            try? await eviction?.run(openPullRequests: summaries.map(\.id), busy: busy)
            // Stejné pravidlo jako u eviction: uklízet se smí jen po **úspěšném** tiku,
            // protože „PR chybí v seznamu“ znamená po výpadku sítě něco jiného. Selhání
            // úklidu se spolkne schválně — neuklizený soubor nikomu nevadí a příští tik to
            // zkusí znovu; hlásit to uživateli by byl šum bez akce.
            try? await reviews?.cleanUp(openPullRequests: summaries.map(\.id))
        }
    }

    /// Sestavení z toho, co našel preflight. Absolutní cesta k `gh` je jediné, co gateway
    /// potřebuje — token si drží `gh` sám.
    convenience init(toolPaths: ToolPaths) {
        let runner = SubprocessRunner()
        let checkout = GitRepoCheckout(git: toolPaths.git, gh: toolPaths.gh, runner: runner)
        // Hodnoty se čtou **při použití**, ne teď: jinak by se reload konfigurace projevil
        // až po restartu. `weak` proto, aby si providery nedržely store.
        // Konfigurace se načte hned v `keepFresh()`; do té doby platí výchozí hodnoty,
        // takže se nikde nečeká na disk.
        let box = ConfigurationBox(.standard)
        self.init(
            gateway: GhGateway(gh: toolPaths.gh, runner: runner),
            configStore: ConfigStore(),
            eviction: CacheEviction(
                budget: { box.value.global.cacheBudgetMegabytes * 1024 * 1024 },
                checkout: checkout
            ),
            checkout: checkout,
            reviewer: ClaudeReviewRunner(
                claude: toolPaths.claude,
                gh: toolPaths.gh,
                runner: SubprocessStreamer(),
                maxConcurrent: { box.value.global.maxConcurrentReviews },
                model: { box.value.global.model }
            ),
            reviews: ReviewStore(),
            translator: ClaudeFindingTranslator(claude: toolPaths.claude, runner: runner),
            autoRuns: AutoRunLedger()
        )
        self.configurationBox = box
    }

    /// Sdílená schránka na aktuální konfiguraci pro věci, které běží mimo hlavní vlákno
    /// (limit souběhu, rozpočet cache, model). Store je `@MainActor`, takže sáhnout si
    /// na něj přímo nemůžou.
    private var configurationBox: ConfigurationBox?

    /// Nastavení pro konkrétní repo — globální hodnoty přebité tím, co si repo řeklo.
    func resolved(for repo: RepoID) -> ResolvedConfig {
        configuration.resolved(for: repo)
    }

    /// Repozitáře, které okno nastavení nabídne — z posledního seznamu PR i z konfigurace.
    var knownRepositories: [RepoID] {
        Policy.knownRepositories(in: pullRequests, configuration: configuration)
    }

    /// Znovu načte `config.json`. Co se čte při použití (skilly, kategorie, limit souběhu,
    /// rozpočet cache), se projeví hned; zdroje a interval se přepíšou pollingu tady.
    func reloadConfiguration() async {
        guard let configStore else { return }
        let loaded = await configStore.load()
        configurationFailure = loaded.failure
        await apply(loaded.configuration)
    }

    /// Uloží konfiguraci z okna nastavení a hned ji propíše dál.
    ///
    /// Chyba **letí ven**: neuložené nastavení, o kterém se mlčí, vypadá v okně jako
    /// uložené a po restartu je pryč. Do stavu se přitom propíše až po úspěšném zápisu,
    /// aby se okno a soubor nerozešly.
    func updateConfiguration(_ configuration: Configuration) async throws {
        // Optional chaining by bez tohohle tiše prošlo a okno by hlásilo „Uloženo“ nad
        // něčím, co nikam neodešlo. Store bez `ConfigStore` staví jen testy, ale
        // signatura říká `throws` a to musí platit.
        guard let configStore else { throw ConfigurationError.noStore }
        try await configStore.save(configuration)
        // Na disku teď leží to, co jsme zapsali — starší chyba čtení už neplatí. Uložit se
        // dá jen z odemčeného editoru, takže se tím nepřebíjí soubor, který se nepovedlo
        // přečíst.
        configurationFailure = nil
        await apply(configuration)
    }

    /// Jedna cesta, kterou se nová konfigurace dostane do běžící aplikace — ať přišla
    /// z disku, nebo z okna nastavení. Kdyby byly dvě, jedna z nich by časem zapomněla
    /// něco přepsat.
    private func apply(_ configuration: Configuration) async {
        self.configuration = configuration
        configurationBox?.value = configuration
        polling.sources = configuration.activeSources
        polling.interval = .seconds(configuration.global.pollIntervalSeconds)
        // Limit souběhu se čte při každém pokusu o slot, ale kdo už čeká ve frontě, spí.
        await reviewer?.configurationChanged()
    }

    var pullRequests: [PullRequestSummary] { polling.state.pullRequests }
    var status: PollStatus { polling.state.status }
    var lastSuccess: Date? { polling.state.lastSuccess }
    var isStale: Bool { polling.state.isStale }
    var emptyReason: PollEmptyReason? { polling.state.emptyReason }

    /// Drží seznam aktuální, dokud okno žije. Zrušení tasku smyčku ukončí.
    func keepFresh() async {
        await reloadConfiguration()
        await loadStoredReviews()
        await polling.run()
    }

    /// Nálezy z minula. Bez toho by se po startu tvářil každý PR, že se nikdy nereviewoval.
    ///
    /// Selhání čtení se **smí** spolknout, na rozdíl od selhání zápisu: nepřečtený soubor
    /// nikam nezmizel a příští start ho zkusí znovu. Co se přečíst nepodařilo po souborech,
    /// se navíc počítá do `unreadableReviewFiles` a je to vidět pod seznamem.
    func loadStoredReviews() async {
        guard let reviews else { return }
        guard let loaded = try? await reviews.load() else { return }
        reviewRecords = Policy.currentRecords(from: loaded.records)
        unreadableReviewFiles = loaded.unreadable
    }

    /// Tlačítko „obnovit teď“ — tik mimo pořadí.
    func refresh() async {
        await polling.refresh()
    }

    /// Repa, se kterými se právě pracuje — odvozeno ze stavu, ne vedené zvlášť. Množina
    /// s ručním `insert`/`remove` by u dvou souběžných příprav téhož repa sundala ochranu
    /// při první, která doběhne.
    ///
    /// Patří sem i repa s **běžícím review**, ne jen ta, která se právě klonují: smazat klon
    /// pod běžící session by jí vzalo pracovní strom pod rukama.
    var busyRepositories: Set<RepoID> {
        Set(checkoutStates.filter { $0.value == .preparing }.keys)
            .union(reviewTasks.keys.map(\.repo))
    }

    func checkoutState(for repo: RepoID) -> CheckoutState {
        checkoutStates[repo] ?? .absent
    }

    func reviewState(for pr: PRIdentifier) -> ReviewState {
        Policy.reviewState(
            phase: reviewPhases[pr],
            record: reviewRecords[pr],
            checkout: checkoutState(for: pr.repo),
            categories: resolved(for: pr.repo).blockingCategories
        )
    }

    func reviewRecord(for pr: PRIdentifier) -> ReviewRecord? { reviewRecords[pr] }

    /// Běží nad PR review? Rozhoduje běžící úloha, ne fáze — ta zůstává i po selhání, aby
    /// bylo z čeho ukázat důvod.
    func isReviewing(_ pr: PRIdentifier) -> Bool { reviewTasks[pr] != nil }

    /// Připraví pracovní kopii repa. Slouží i jako „zkusit znovu“ po selhání — příprava
    /// je idempotentní, takže opakování je totéž volání.
    ///
    /// Po úspěchu se stav vrací na `notStarted`: `ReviewState` popisuje **review**, a to
    /// se ještě nespustilo. Že je kopie připravená, ukazuje detail, ne odznak v řádku.
    func prepareCheckout(for pr: PRIdentifier) async {
        guard let checkout else { return }
        let previous = checkoutState(for: pr.repo)
        checkoutStates[pr.repo] = .preparing

        do {
            checkoutStates[pr.repo] = .ready(try await checkout.prepare(pr.repo))
        } catch is CancellationError {
            // Zrušení není selhání checkoutu — a `localizedDescription` by z něj udělalo
            // anglickou systémovou hlášku v české aplikaci.
            checkoutStates[pr.repo] = previous
        } catch let error as CheckoutError {
            checkoutStates[pr.repo] = .failed(error.userDescription)
        } catch {
            checkoutStates[pr.repo] = .failed(error.localizedDescription)
        }
    }

    func checkoutPath(for pr: PRIdentifier) -> URL? {
        guard case .ready(let url) = checkoutState(for: pr.repo) else { return nil }
        return url
    }

    /// Srovná stav podle toho, co je **teď** v cache. Volá se při výběru řádku, nic
    /// nestahuje.
    ///
    /// Nejde jen o doplnění chybějícího: klon mohla mezitím sebrat eviction, takže se
    /// zapsaná cesta musí ověřit znovu — jinak by detail ukazoval „připraveno“ na složku,
    /// která už neexistuje. Běžící přípravu to nepřepisuje.
    func noteExistingCheckout(for pr: PRIdentifier) async {
        guard checkoutState(for: pr.repo) != .preparing else { return }
        if let clone = await checkout?.existingClone(for: pr.repo) {
            checkoutStates[pr.repo] = .ready(clone)
        } else if case .failed = checkoutState(for: pr.repo) {
            return // Chybu drž, dokud si uživatel neřekne o opakování.
        } else {
            checkoutStates[pr.repo] = .absent
        }
    }

    // MARK: - Diff

    func diffState(for pr: PRIdentifier) -> DiffState? { diffStates[pr] }

    /// Načte diff vybraného PR. Načtený se drží — na GitHub se sáhne znovu, teprve když
    /// se změní `updatedAt`.
    ///
    /// `updatedAt` se mění i po komentáři, takže se občas načte zbytečně. Opačná chyba —
    /// ukázat diff, ve kterém chybí nový commit — je dražší.
    func loadDiff(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard !hasCurrentDiff(for: pullRequest) else { return }
        diffStates[id] = .loading

        do {
            let text = try await gateway.fetchDiff(id: id)
            diffStates[id] = .loaded(DiffParser.parse(text), updatedAt: pullRequest.updatedAt)
            revealFindingsOutsideTheDiff(for: id)
        } catch is CancellationError {
            // Přepnutí na jiné PR načítání zruší. Nechat tam `.loading` by znamenalo
            // spinner, který se nikdy nedotočí. Maže se **jen** rozdělaný stav: mezitím
            // spuštěné načtení už mohlo doběhnout a to se přepsat nesmí.
            if diffStates[id] == .loading { diffStates[id] = nil }
        } catch let error as GitHubError {
            diffStates[id] = .failed(error.userDescription)
        } catch {
            diffStates[id] = .failed(error.localizedDescription)
        }
    }

    /// Rozdělané načítání se za platný diff **nepovažuje** — dvě souběžná načtení jsou
    /// jen zbytečné volání navíc, kdežto přeskočit to jediné, které běží, znamená prázdno
    /// v okně, dokud si uživatel PR nevybere znovu.
    private func hasCurrentDiff(for pullRequest: PullRequestSummary) -> Bool {
        guard case .loaded(_, let updatedAt) = diffStates[pullRequest.id] else { return false }
        return updatedAt == pullRequest.updatedAt
    }

    // MARK: - Sbalení souboru

    func isFolded(_ path: String, in pr: PRIdentifier) -> Bool {
        foldedFiles.contains(FileExpansionKey(pullRequest: pr, path: path))
    }

    func toggleFolded(_ path: String, in pr: PRIdentifier) {
        let key = FileExpansionKey(pullRequest: pr, path: path)
        if foldedFiles.contains(key) {
            foldedFiles.remove(key)
        } else {
            foldedFiles.insert(key)
        }
    }

    /// Rozbalí soubor, ať se dá skočit dovnitř. Skok na sbalený soubor by jinak skončil
    /// nikde — jeho řádky v líném seznamu vůbec nejsou.
    func unfold(_ path: String, in pr: PRIdentifier) {
        foldedFiles.remove(FileExpansionKey(pullRequest: pr, path: path))
    }

    /// Sbalí vyjmenované soubory. Cesty dodává volající, protože co je v diffu, store neví.
    func foldAll(_ paths: [String], in pr: PRIdentifier) {
        foldedFiles.formUnion(paths.map { FileExpansionKey(pullRequest: pr, path: $0) })
    }

    /// Rozbalí všechno v tomhle PR. Cesty netřeba — rozbalené je to, co v množině není.
    ///
    /// Sahá **jen na tohle PR**: sbalení v jiném je cizí stav a smazat ho při „rozbalit vše“
    /// by znamenalo, že se tlačítko v jednom okně projeví jinde.
    func unfoldAll(in pr: PRIdentifier) {
        foldedFiles = foldedFiles.filter { $0.pullRequest != pr }
    }

    // MARK: - Rozbalení kontextu

    func expansion(of path: String, in pr: PRIdentifier) -> FileExpansion {
        expansions[FileExpansionKey(pullRequest: pr, path: path)] ?? FileExpansion()
    }

    /// Je v diffu vidět něco navíc proti tomu, co poslal `gh`?
    func hasRevealedLines(in pr: PRIdentifier) -> Bool {
        expansions.contains { $0.key.pullRequest == pr && !$0.value.revealed.ranges.isEmpty }
    }

    /// Sbalí všechen rozbalený kontext zpátky na samotný diff.
    ///
    /// Načtený obsah souborů si **nechá**: kdyby ho zahodila, druhé rozbalení by znovu
    /// chodilo po síti pro něco, co už jednou dorazilo.
    func collapseRevealedLines(in pr: PRIdentifier) {
        // Zápis do `expansions` uprostřed iterace je bezpečný: slovník je hodnotový typ,
        // takže smyčka jede přes snapshot pořízený na jejím začátku. Ověřeno spuštěním
        // (1000 prvků, žádný přeskočený). Podmínka na prázdné rozsahy tu není kvůli
        // výkonu — zbytečný zápis by hlásil změnu i tam, kde se nic nezměnilo.
        for (key, expansion) in expansions where key.pullRequest == pr {
            guard !expansion.revealed.ranges.isEmpty else { continue }
            expansions[key]?.revealed = RevealedLines()
        }
    }

    /// Odkryje skryté řádky souboru. Obsah se dotáhne při prvním rozbalení a pak už se drží.
    ///
    /// Rozsah se zapíše **až po** načtení: kdyby se zapsal hned, zmizel by rozbalovací
    /// řádek i se spinnerem a zůstalo by po něm prázdno.
    func reveal(_ lines: ClosedRange<Int>, of path: String, in pr: PRIdentifier) {
        let key = FileExpansionKey(pullRequest: pr, path: path)
        var state = expansions[key] ?? FileExpansion()

        guard state.content.isEmpty else {
            state.revealed.reveal(lines)
            expansions[key] = state
            return
        }

        // Než obsah dorazí, rozsahy se schovávají stranou. Zahodit ten druhý (dva nálezy
        // v jednom souboru) by znamenalo bublinu bez kódu, o kterém mluví.
        state.pending.append(lines)
        guard !state.isLoading else {
            expansions[key] = state
            return
        }
        state.isLoading = true
        state.failure = nil
        expansions[key] = state
        Task { [weak self] in await self?.loadFile(key) }
    }

    private func loadFile(_ key: FileExpansionKey) async {
        do {
            let text = try await gateway.fetchFile(id: key.pullRequest, path: key.path)
            // Stav se čte **až po** awaitu: mezitím mohly přibýt další vyžádané rozsahy.
            var state = expansions[key] ?? FileExpansion()
            state.isLoading = false
            state.content = FileExpansion.lines(of: text)
            // Rozsahy se ořezávají na skutečnou délku souboru. Reviewer umí nahlásit řádek,
            // který v souboru není, a odkrytý neexistující řádek by dal kotvu na řádek,
            // který se nikdy nevykreslí — tedy skok, po kterém se nic nestane.
            for range in state.pending {
                guard let clamped = clamp(range, to: state.content.count) else { continue }
                state.revealed.reveal(clamped)
            }
            state.pending = []
            expansions[key] = state
        } catch is CancellationError {
            // Zrušení není selhání: úsek zůstane skrytý a další kliknutí to zkusí znovu.
            expansions[key]?.isLoading = false
        } catch {
            var state = expansions[key] ?? FileExpansion()
            state.isLoading = false
            state.pending = []
            state.failure = (error as? GitHubError)?.userDescription ?? error.localizedDescription
            expansions[key] = state
        }
    }

    /// Dotáhne kód k nálezům, jejichž řádek v diffu není.
    ///
    /// Děje se to samo, ne na kliknutí (**změna proti #47**): bublina, která mluví
    /// o řádku 10, a řádek 10 nikde — to je přesně případ, kdy čekání na kliknutí stojí
    /// nejvíc. Týká se to jen souborů, kde nález opravdu je, takže se stahuje málo.
    private func revealFindingsOutsideTheDiff(for pr: PRIdentifier) {
        guard case .loaded(let diff, _) = diffStates[pr], let record = reviewRecords[pr] else { return }

        for group in Policy.groups(of: record.findings) {
            guard let path = group.file, let line = group.line,
                  let file = diff.file(at: path),
                  // Smazaný soubor ani binárka nový obsah nemají, takže není co stahovat.
                  file.change != .deleted, !file.isBinary,
                  !file.showsLine(line)
            else { continue }

            reveal(max(1, line - Self.findingContext)...(line + Self.findingContext), of: file.displayPath, in: pr)
        }
    }

    private func clamp(_ range: ClosedRange<Int>, to length: Int) -> ClosedRange<Int>? {
        let lower = max(1, range.lowerBound)
        let upper = min(length, range.upperBound)
        return lower <= upper ? lower...upper : nil
    }

    /// Kolik řádků kolem nálezu se dotáhne. Samotný řádek bez okolí se čte špatně.
    private static let findingContext = 3

    // MARK: - Review

    /// Spustí review vybraného PR. Opakované zmáčknutí, dokud běží, nic nedělá.
    func startReview(for pr: PRIdentifier) {
        guard reviewer != nil, reviewTasks[pr] == nil else { return }
        // Ruční spuštění přebíjí automat: kdyby PR mezitím spustil automat, nespustí se
        // podruhé (`reviewTasks` už není `nil`), ale zůstal by označený jako automatický
        // a zmizení ze seznamu by ho zrušilo pod rukama.
        automaticReviews.remove(pr)
        reviewTasks[pr] = Task { [weak self] in await self?.review(pr) }
    }

    // MARK: - Automatický režim

    /// Kolik automatických review dnes ještě zbývá. `nil` = automat není nastavený nikde,
    /// takže se o limitu nemá co mluvit.
    private(set) var remainingAutomaticRuns: Int?

    /// Naplánuje review pro repa v automatickém režimu.
    ///
    /// Volá se **jen po úspěšném tiku**: po výpadku sítě je seznam prázdný, takže by se
    /// nespustilo nic a `consideredForAutomation` by se rozešlo se skutečností.
    private func startAutomaticReviews(for summaries: [PullRequestSummary]) async {
        guard let autoRuns else { return }
        let limit = configuration.global.autoRunsPerDay
        let anyAutomatic = summaries.contains { resolved(for: $0.repo).mode == .automatic }
        remainingAutomaticRuns = anyAutomatic ? await autoRuns.remaining(limit: limit) : nil

        let candidates = Policy.automaticallyReviewable(
            in: summaries,
            configuration: configuration,
            considered: consideredForAutomation,
            running: Set(reviewTasks.keys)
        )
        let updates = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0.updatedAt) })

        for pr in candidates {
            // Rozpočet se bere **před** spuštěním: session je utracená v okamžiku, kdy běh
            // začne, ne až doběhne.
            guard await autoRuns.take(limit: limit) else { break }
            // Zapsat se to smí až potom, co se běh opravdu naplánoval. Obrácené pořadí by
            // znamenalo, že PR zamítnutý rozpočtem se už nikdy nezváží.
            consideredForAutomation[pr] = updates[pr]
            automaticReviews.insert(pr)
            reviewTasks[pr] = Task { [weak self] in await self?.review(pr) }
        }
        remainingAutomaticRuns = anyAutomatic ? await autoRuns.remaining(limit: limit) : nil
    }

    /// Zrušení uživatelem. Session dostane `SIGKILL`, rozdělané výsledky se zahodí.
    func cancelReview(for pr: PRIdentifier) {
        reviewTasks[pr]?.cancel()
    }

    /// Sada skillů pro repo. Chipy z ní berou pořadí i to, co ještě neběželo.
    func reviewSkills(for repo: RepoID) -> [String] { resolved(for: repo).skills }

    /// Reviewery, kteří na PR **právě běží**.
    ///
    /// Odvozeno, ne vedeno zvlášť: běh, který ještě nestihl poslat první událost, osu
    /// nemá — a přesto běží. Proto se počítá jako „všechno, co nedoběhlo“.
    func runningReviewers(for pr: PRIdentifier) -> Set<String> {
        guard isReviewing(pr) else { return [] }
        let finished = Set(timelines(for: pr).filter(\.isFinished).map(\.skill))
        return Set(reviewSkills(for: pr.repo)).subtracting(finished)
    }

    /// Časová osa běhů posledního review. Prázdná, dokud se nic nespustilo.
    func timelines(for pr: PRIdentifier) -> [ReviewerTimeline] {
        reviewTimelines[pr] ?? []
    }

    private func review(_ pr: PRIdentifier) async {
        defer {
            reviewTasks[pr] = nil
            automaticReviews.remove(pr)
        }
        guard let reviewer, let checkout, let reviews else { return }

        // Nový běh začíná s čistou osou — míchat dohromady, co dělaly dva různé běhy, by
        // z časové osy udělalo nesmysl.
        reviewTimelines[pr] = []
        reviewPhases[pr] = .preparing
        do {
            // SHA umí dát jen detail — vyhledávání ho nevrací (viz rozhodnutí u #4).
            let detail = try await gateway.fetchDetail(id: pr)
            try await reviews.markCurrent(detail.headSha, of: pr)
            markStaleInMemory(for: pr, current: detail.headSha)

            // Tady se rozhoduje, jestli se utratí session. Výběr po tiku jede podle
            // `updatedAt`, které se mění i po komentáři — teprve `headSha` řekne, jestli
            // se kód opravdu změnil. Ruční spuštění se **nezastavuje**: když si o něj
            // někdo řekl podruhé, chce to pustit znovu.
            if automaticReviews.contains(pr), hasCurrentReview(of: pr, at: detail.headSha) {
                reviewPhases[pr] = nil
                return
            }

            checkoutStates[pr.repo] = .preparing
            let worktree = try await checkout.worktree(for: pr, at: detail.headSha)
            await syncCheckoutState(for: pr.repo, using: checkout)
            try Task.checkCancellation()

            // Musí to být **před** `runSkills`, ne po: sada, kterou detekce zapíše, je
            // ta, se kterou má tenhle běh jet.
            await adoptDetectedSkills(for: pr.repo, in: worktree, using: checkout)
            // Odhad jazyka zrušení **spolkne** — nepovedený výpis se od zrušeného nepozná
            // a obojí tam znamená „sadu neodvodíme“. Zrušené review by pak jelo dál, takže
            // se to musí zeptat znovu tady.
            try Task.checkCancellation()

            try await runSkills(for: pr, of: detail, in: worktree, using: reviewer, saving: reviews)
            reviewPhases[pr] = nil
        } catch is CancellationError {
            // Zrušení není selhání — stav se srovná podle disku, ne do chyby.
            reviewPhases[pr] = nil
            await syncCheckoutState(for: pr.repo, using: checkout)
        } catch let error as CheckoutError {
            // Chyba pracovní kopie je stav **repa**, ne tohohle PR: druhé PR téhož repa na
            // ni narazí taky a řeší se stejným tlačítkem.
            reviewPhases[pr] = nil
            checkoutStates[pr.repo] = .failed(error.userDescription)
        } catch let error as GitHubError {
            reviewPhases[pr] = .failed(detail: error.userDescription)
        } catch {
            reviewPhases[pr] = .failed(detail: error.localizedDescription)
        }
    }

    /// Odvodí sadu skillů z toho, co v repu leží.
    ///
    /// Běží při **každém** review, dokud si repo o skilly neřeklo (`skills == nil`) — ne
    /// jen při prvním. Je to schválně: mapa jazyků se dá vyplnit až potom, co se repo
    /// jednou zreviewovalo, a bez opakování by se projevila teprve na dalším repu.
    /// Stojí to jedno lokální `git ls-files` navíc.
    ///
    /// Ruční hodnota má přednost a **i prázdná** („tady nereviewuj nic“) detekci
    /// navždycky umlčí — přepsat ji by znamenalo vracet uživateli jeho rozhodnutí zpátky.
    ///
    /// Zapisuje se jen to, co se od globální sady liší. Zápis „stejné jako globální“ by byl
    /// override, o který nikdo nežádal — a pozdější změna globální sady by tenhle repo
    /// tiše minula.
    private func adoptDetectedSkills(for repo: RepoID, in worktree: URL, using checkout: any RepoCheckout) async {
        guard configuration.repositories[repo]?.skills == nil else { return }

        let files: [String]
        do {
            files = try await checkout.trackedFiles(in: worktree)
        } catch {
            // Nepovedený výpis znamená, že se sada neodvodí a poběží globální — tedy přesně
            // to, co běželo před #24. Nic se neztrácí a příští review to zkusí znovu,
            // protože `skills` zůstává `nil`. Položit kvůli tomu celé review by bylo dražší
            // než ta ztráta.
            return
        }

        let detected = configuration.defaultSkills(for: Policy.projectLanguages(in: files))
        guard detected != resolved(for: repo).skills else { return }

        var entry = configuration.repositories[repo] ?? RepositoryConfig()
        entry.skills = detected
        var updated = configuration
        updated.setRepository(entry, for: repo)

        do {
            try await updateConfiguration(updated)
        } catch {
            // Review poběží dál, jen s globální sadou — `resolved(for:)` čte to, co je
            // v paměti, a tam se nic nezměnilo. Mlčet o tom ale nejde: nastavení, které
            // se neuložilo, je přesně to, kvůli čemu se pak hledá, proč něco nefunguje.
            configurationFailure = "Rozpoznanou sadu skillů se nepodařilo uložit. \(error.localizedDescription)"
        }
    }

    /// Reviewery běží paralelně; limit souběhu hlídá `ReviewRunner`, ne tenhle kód.
    ///
    /// Ukládá se po **každém** doběhlém skillu, ne až na konci: když se aplikace zavře
    /// uprostřed, co doběhlo, zůstane.
    private func runSkills(
        for pr: PRIdentifier,
        of detail: PullRequest,
        in worktree: URL,
        using reviewer: any ReviewRunning,
        saving reviews: ReviewStore
    ) async throws {
        let skills = reviewSkills(for: pr.repo)
        reviewPhases[pr] = .running(finished: 0, total: skills.count)

        // Průběh teče přes proud, ne přímo do store: hlásí se ze session, která běží mimo
        // hlavní vlákno, a **pořadí událostí je to hlavní, co časová osa říká**. Proud ho
        // drží; hop do vlastního tasku na každou událost by o pořadí nechal rozhodovat
        // plánovač.
        let (events, reporter) = AsyncStream<ReviewEvent>.makeStream()
        async let drained: Void = drain(events, for: pr, in: worktree)
        let failure = await runSkills(
            for: pr,
            of: detail,
            in: worktree,
            using: reviewer,
            saving: reviews,
            reporting: reporter
        )
        reporter.finish()
        await drained

        if let failure { throw failure }
    }

    /// Co se v běhu stalo. **Konec běhu jde stejným proudem jako průběh** — jinak by ho
    /// osa dostala dřív než události, které mu předcházely, a někdy vůbec.
    private enum ReviewEvent: Sendable {
        case progress(skill: String, ReviewProgress)
        case finished(skill: String, ReviewRunOutcome)
    }

    /// Zapisuje průběh v pořadí, ve kterém dorazil.
    private func drain(_ events: AsyncStream<ReviewEvent>, for pr: PRIdentifier, in worktree: URL) async {
        for await event in events {
            switch event {
            case .progress(let skill, let progress): record(progress, of: skill, for: pr, in: worktree)
            case .finished(let skill, let outcome): finish(outcome, of: skill, for: pr)
            }
        }
    }

    private func record(_ progress: ReviewProgress, of skill: String, for pr: PRIdentifier, in worktree: URL) {
        var timelines = reviewTimelines[pr] ?? []
        if let index = timelines.firstIndex(where: { $0.skill == skill }) {
            timelines[index].record(progress, at: time.now)
        } else {
            var timeline = ReviewerTimeline(skill: skill, worktree: worktree)
            timeline.record(progress, at: time.now)
            timelines.append(timeline)
        }
        reviewTimelines[pr] = timelines
    }

    private func finish(_ outcome: ReviewRunOutcome, of skill: String, for pr: PRIdentifier) {
        guard var timelines = reviewTimelines[pr],
              let index = timelines.firstIndex(where: { $0.skill == skill })
        else { return }
        timelines[index].finish(outcome, at: time.now)
        reviewTimelines[pr] = timelines
    }

    private func runSkills(
        for pr: PRIdentifier,
        of detail: PullRequest,
        in worktree: URL,
        using reviewer: any ReviewRunning,
        saving reviews: ReviewStore,
        reporting reporter: AsyncStream<ReviewEvent>.Continuation
    ) async -> (any Error)? {
        let skills = reviewSkills(for: pr.repo)
        return await withTaskGroup(of: ReviewRun?.self) { group in
            for skill in skills {
                let request = ReviewRequest(
                    key: ReviewRunKey(pullRequest: pr, headSha: detail.headSha, skillID: skill),
                    worktree: worktree,
                    baseSha: detail.baseSha
                )
                // Protokol slibuje, že selhání session se vrací jako výsledek a vyhodí se
                // jen zrušení — ale spolehnout se na to znamená, že jakákoli jiná chyba
                // zmizí a řádek se bude tvářit, že se nic nespustilo. Radši ji přeložíme
                // na `failed`, kde je vidět.
                group.addTask {
                    do {
                        return try await reviewer.run(request) { reporter.yield(.progress(skill: skill, $0)) }
                    } catch is CancellationError {
                        return nil
                    } catch {
                        return ReviewRun(
                            key: request.key,
                            summary: StreamSummary(),
                            outcome: .failed(detail: error.localizedDescription)
                        )
                    }
                }
            }

            var finished = 0
            var saveFailure: (any Error)?
            for await run in group {
                finished += 1
                reviewPhases[pr] = .running(finished: finished, total: skills.count)
                guard let run, !Task.isCancelled else { continue }
                reporter.yield(.finished(skill: run.key.skillID, run.outcome))
                do {
                    // Ukládá se **před** překladem: ten je krátká síťová operace navíc
                    // a když se na ní aplikace zavře, nálezy už jsou na disku. V originále,
                    // ale jsou — což je přesně to, co pravidlo „co doběhlo, zůstane“ chce.
                    reviewRecords[pr] = try await reviews.save(run)
                    revealFindingsOutsideTheDiff(for: pr)
                    if let translated = await translated(run, for: pr.repo) {
                        reviewRecords[pr] = try await reviews.save(translated)
                    }
                } catch {
                    // Nezapsaný nález je ztracený nález. Spolknout to by znamenalo, že
                    // řádek po doběhlém review ukazuje „neběželo“ — tedy přesně to, čemu se
                    // celý ten rozlišený stav vyhýbá. Ostatní skilly doběhnou, ať se
                    // nezahodí i to, co se uložit povedlo.
                    saveFailure = saveFailure ?? error
                }
            }
            return saveFailure
        }
    }

    /// Doplní běhu překlady nálezů. `nil` = není co ukládat znovu.
    ///
    /// Jazyk se čte **teď**, ne při startu, takže se přepnutí projeví na dalším běhu.
    /// Zpětně neplatí: uložené nálezy zůstanou v jazyce, ve kterém se uložily.
    private func translated(_ run: ReviewRun, for repo: RepoID) async -> ReviewRun? {
        guard let translator, !run.summary.findings.isEmpty else { return nil }
        // Zrušené review nemá utrácet session za překlad. Nálezy jsou v tu chvíli uložené
        // v originále, takže se nic neztrácí — jen se nepřekládá to, co si nikdo nevyžádal.
        guard !Task.isCancelled else { return nil }
        // Angličtina se nepřekládá — reviewer v ní píše sám od sebe (ověřeno na skutečných
        // bězích). Volat kvůli tomu model by byla session za nic.
        let language = resolved(for: repo).findingsLanguage
        guard language != .english else { return nil }

        // Selhání překladu review nepoloží: nálezy jsou uložené a v originále čitelné.
        // Že jsou anglicky, je vidět na první pohled — mlčení tu nic neschovává.
        guard let translations = try? await translator.translate(run.summary.findings, to: language),
              translations.contains(where: { $0 != nil })
        else { return nil }

        var translated = run
        translated.translations = translations
        return translated
    }

    /// Srovná stav pracovní kopie podle disku.
    ///
    /// Volá se po každé fázi, která ho mohla nechat v `.preparing` — a to je i zrušení.
    /// Zapomenout na to znamená řádek, který do restartu ukazuje „ve frontě · clone“.
    private func syncCheckoutState(for repo: RepoID, using checkout: any RepoCheckout) async {
        if let clone = await checkout.existingClone(for: repo) {
            checkoutStates[repo] = .ready(clone)
        } else {
            checkoutStates[repo] = .absent
        }
    }

    /// Je pro tenhle `headSha` hotové review se **všemi** nastavenými skilly?
    ///
    /// Chybějící skill znamená, že se sada mezitím rozšířila nebo že běh nedoběhl celý —
    /// a to je důvod pustit ho znovu. Zastaralý záznam se nepočítá vůbec.
    private func hasCurrentReview(of pr: PRIdentifier, at headSha: String) -> Bool {
        guard let record = reviewRecords[pr], record.headSha == headSha, !record.isStale else {
            return false
        }
        let finished = Set(record.runs.map(\.skillID))
        return Set(reviewSkills(for: pr.repo)).isSubset(of: finished)
    }

    /// Nový head commit zneplatní i to, co držíme v paměti — jinak by řádek do konce běhu
    /// ukazoval nálezy proti kódu, který v PR není.
    private func markStaleInMemory(for pr: PRIdentifier, current headSha: String) {
        guard var record = reviewRecords[pr], record.headSha != headSha else { return }
        record.isStale = true
        reviewRecords[pr] = record
    }

    /// Zahodí stav rep, o která už není zájem. Bez toho by mapa rostla donekonečna a PR,
    /// které se po týdnu vrátí do seznamu, by přivítala chyba z minula.
    private func forget(whatIsNotIn summaries: [PullRequestSummary]) {
        let wanted = Set(summaries.map(\.id.repo))
        checkoutStates = checkoutStates.filter { wanted.contains($0.key) || $0.value == .preparing }

        // Diff velkého PR jsou megabajty, takže se drží jen pro to, co je v seznamu.
        // Rozdělané načítání přežije ze stejného důvodu jako běžící příprava: jinak by si
        // ho doběhlé volání zapsalo zpátky a v mapě by zůstalo tak jako tak.
        let wantedPullRequests = Set(summaries.map(\.id))
        diffStates = diffStates.filter { wantedPullRequests.contains($0.key) || $0.value == .loading }
        expansions = expansions.filter {
            wantedPullRequests.contains($0.key.pullRequest) || $0.value.isLoading
        }
        // Sbalení je jen příznak, ale drží klíč s celým identifikátorem PR — bez úklidu by
        // množina rostla donekonečna.
        foldedFiles = foldedFiles.filter { wantedPullRequests.contains($0.pullRequest) }
        // Běžící review si osu drží: `reviewTasks` je pravda o tom, co ještě běží, a jeho
        // události by se jinak zapisovaly do mapy, ze které je někdo právě vyhodil.
        reviewTimelines = reviewTimelines.filter {
            wantedPullRequests.contains($0.key) || reviewTasks[$0.key] != nil
        }

        // Zavřený nebo mergnutý PR nemá co blokovat slot. Ruší se **jen automatická**
        // review: to ruční si vyžádal člověk a zrušit mu ho pod rukama proto, že PR mezitím
        // někdo mergnul, je horší než session navíc.
        for pr in automaticReviews where !wantedPullRequests.contains(pr) {
            reviewTasks[pr]?.cancel()
        }
        consideredForAutomation = consideredForAutomation.filter { wantedPullRequests.contains($0.key) }
    }
}
