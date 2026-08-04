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

    /// Detail **per PR** — kvůli `headSha`, proti kterému se píše rozdělané review.
    ///
    /// Dotahuje se při výběru řádku, ne pollingem: pro všech N PR by to byla tatáž N+1 past,
    /// kvůli které se netahá konverzace. Cache podle `updatedAt` je stejná jako u diffu.
    private(set) var detailStates: [PRIdentifier: DetailState] = [:]

    /// Který tab PR je vidět, **per PR**. Co v mapě není, je na `PullRequestTab.standard`.
    ///
    /// Drží se odchylka od výchozího stavu, ne volba u každého PR — stejný vzor jako
    /// u překliknutých vláken. Ve view to být nemůže: `PullRequestDetailView` si SwiftUI mezi
    /// pull requesty ponechá, takže by volba přetekla z jednoho na druhý.
    private(set) var detailTabs: [PRIdentifier: PullRequestTab] = [:]

    /// Rozdělané review **per PR**. Co v mapě není, se nezačalo psát.
    ///
    /// Načte se celé při startu, ne až při výběru řádku: indikátor v seznamu má být vidět
    /// u všech PR naráz a jsou to kilobajty.
    private(set) var drafts: [PRIdentifier: ReviewDraft] = [:]

    /// Kolik souborů s rozdělaným review se nepodařilo přečíst.
    ///
    /// Musí být vidět, a o důvod víc než u nálezů: nález se dá dostat zpátky dalším během,
    /// ručně psané review ne.
    private(set) var unreadableDraftFiles = 0

    /// Proč se rozdělané review nepodařilo uložit.
    ///
    /// Ztracená ručně psaná práce je to nejdražší, co tady umí zmizet — takže se selhání
    /// zápisu nespolkne. Na rozdíl od nálezů se nedá zopakovat žádným během.
    private(set) var draftFailure: String?

    /// Konverzace **per PR** — review ostatních, vlákna, komentáře. Co v mapě není, se
    /// ještě nenačítalo.
    private(set) var conversationStates: [PRIdentifier: ConversationState] = [:]

    /// Vlákna, u kterých si uživatel překlikl rozbalení proti výchozímu stavu, **per PR**.
    ///
    /// Drží se **odchylka**, ne seznam rozbalených: výchozí stav se odvozuje z vlákna
    /// (nevyřešené rozbalené, vyřešené sbalené), takže seznam rozbalených by se musel plnit
    /// při každém načtení konverzace — a ruční obnovení by uživateli zahodilo, co si zavřel.
    /// Rozhoduje `Policy.isThreadExpanded(_:toggled:)`.
    ///
    /// Klíčem je **PR**, i když `id` vlákna je globálně unikátní a samo by na rozlišení
    /// stačilo. Je to kvůli úklidu: zahazovat se má podle toho, jestli PR zmizel ze seznamu,
    /// a to z `id` vlákna poznat nejde. Plochá množina uklízená podle **načtených** konverzací
    /// se po výpadku sítě (`.failed`) vyprázdnila a uživateli naskočilo výchozí rozbalení.
    private(set) var toggledThreads: [PRIdentifier: Set<String>] = [:]

    /// Rozepsané odpovědi do vláken (#73). Co v mapě není, nikdo nerozepsal.
    ///
    /// Žije tady, ne v bublině: ta je buňka líného seznamu nad diffem, takže `@State` v ní
    /// odscrollování nepřežije — tatáž past jako u `DraftTextEditor`. Na disk se to naopak
    /// **neukládá**: je to jedna věta v diskuzi, ne review, a další store by za ni platil
    /// souborem na každé vlákno.
    ///
    /// Zahazuje se s PR mimo seznam, stejně jako konverzace — bez vlákna se odpověď nemá kde
    /// ukázat. To je rozdíl proti rozdělanému review, které se drží: to je vlastní práce
    /// v řádu odstavců a má na disku své místo.
    private(set) var threadReplies: [ThreadKey: String] = [:]

    /// Co se právě děje s vláknem, nebo co u něj selhalo. Chybějící záznam = nic.
    private(set) var threadStates: [ThreadKey: ThreadActionState] = [:]

    /// Rozbalený kontext **per soubor v PR**. Co v mapě není, nikdo nerozbaloval.
    private(set) var expansions: [FileExpansionKey: FileExpansion] = [:]

    /// Sbalené soubory diffu. Co v množině **není**, je rozbalené — u PR o padesáti
    /// souborech je rozbaleno výchozí stav a sbalení je gesto, takže se pamatuje to druhé.
    ///
    /// Žije tady, ne ve view: `PullRequestDetailView` si SwiftUI mezi PR ponechá (stejná
    /// pozice ve stromu), takže by sbalení přeteklo z jednoho pull requestu na druhý.
    private(set) var foldedFiles: Set<FileExpansionKey> = []

    /// Odchylka od pohledu na diff, který je v nastavení. `nil` = ber ho z konfigurace.
    ///
    /// Drží se **globálně, ne per PR**: pohled je způsob čtení, takže přepnutím na jiný pull
    /// request nemá důvod se vracet. A ve storu, ne ve view — `PullRequestDetailView` si
    /// SwiftUI mezi PR ponechá (stejná pozice ve stromu), takže `@State` by odchylku zahodilo
    /// přestavění stromu; tatáž past jako u sbalených souborů.
    ///
    /// **Na disk se nezapisuje.** Nastavení říká „takhle to chci mít“, přepínač v liště „teď
    /// se na to podívám jinak“. Kdyby přepínač zapisoval do `config.json`, přestala by být
    /// hodnota v nastavení tím, čemu se říká výchozí — měnila by se sama tím, že si člověk
    /// u jednoho souboru otočí pohled.
    private(set) var diffLayoutOverride: DiffLayout?

    /// Komentář, který se dá ⇧ klikem roztáhnout na rozsah — ten naposledy přidaný v tomhle PR
    /// (#110). Chybějící záznam = není co roztahovat, takže ⇧ klik založí obyčejný komentář.
    ///
    /// Drží se **id komentáře**, ne kotva: druhý konec se z komentáře dopočítá a po roztažení
    /// zůstane platný, kdežto uložená kotva by se s ním rozešla. Uklízí se s PR mimo seznam,
    /// jako ostatní stav vázaný na PR.
    private(set) var rangeTargets: [PRIdentifier: UUID] = [:]

    /// Rozsah, který se právě táhne přes řádky diffu (#110). `nil` = netáhne se.
    ///
    /// Drží se **složený rozsah**, ne dvojice konců: složit ho umí jen `Policy` (potřebuje k tomu
    /// diff, protože pořadí konců rozhoduje podle kreslených řádků), takže by se to jinak počítalo
    /// dvakrát — při zvýrazňování i při vzniku komentáře. Zvýraznění tak ukazuje **přesně** ten
    /// rozsah, který z tažení vznikne.
    private(set) var commentDrag: CommentRangeDrag?

    /// Co reviewery dělaly, per PR. Drží se i po doběhnutí — právě tehdy se k tomu člověk
    /// vrací. Pořadí kopíruje pořadí, ve kterém běhy začaly.
    private(set) var reviewTimelines: [PRIdentifier: [ReviewerTimeline]] = [:]

    /// Má okno nastavení fokus? Hlavní okno se podle toho rozostří, aby netahalo oko.
    ///
    /// Žije tady, ne ve view: okno nastavení je **vlastní scéna**, takže si to dvě okna
    /// nemají kde říct jinudy.
    ///
    /// Hlásí ho **okno nastavení o sobě**, ne hlavní okno o něm. Hlavní okno umí přes
    /// `controlActiveState` říct jen „nemám fokus“, a to je pravda i tehdy, když je vepředu
    /// úplně jiná aplikace — pak by se rozostřovalo bez důvodu.
    var isSettingsFrontmost = false

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
    /// Dostupnost služeb pro stavový řádek. `nil` = odsud se nesleduje (testy) a řádek pak
    /// žádné puntíky neukazuje.
    ///
    /// Nepovinné schválně, jako `checkout` nebo `reviews`: `keepFresh()` volají i testy
    /// a monitor s živým klientem by z nich udělal testy chodící na síť.
    private let health: HealthMonitor?
    private let gateway: any GitHubGateway
    /// Cesta ke `gh` — jediné, co si store kvůli odesílání drží.
    ///
    /// **Ne publisher a ani továrna na něj** (tvrdá podmínka č. 1): cesta ven se skládá až
    /// v `ReviewSubmission.send()`, takže `AppStore` sám odeslat nic neumí — a grep, kterým
    /// se ta podmínka kontroluje, ho schválně nevypíše. `nil` v testech znamená „odsud se
    /// neposílá“ a `submission(for:)` pak nevrátí nic.
    private let gh: URL?
    private let checkout: (any RepoCheckout)?
    private let reviewer: (any ReviewRunning)?
    private let reviews: ReviewStore?
    private let draftStore: ReviewDraftStore?
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
        drafts: ReviewDraftStore? = nil,
        translator: (any FindingTranslating)? = nil,
        autoRuns: AutoRunLedger? = nil,
        gh: URL? = nil,
        health: HealthMonitor? = nil
    ) {
        self.time = time
        self.gh = gh
        self.health = health
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
        draftStore = drafts
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
        // Monitor si skutečná volání nedrží — bere si je odsud. Jinak by existovalo druhé
        // místo se stavem pollingu a rozejít se v tomhle znamená svítit červeně nad
        // funkčním GitHubem.
        health?.lastCall = { [weak self] service in
            switch service {
            case .github: self?.gitHubCall
            case .claude: self?.lastReviewCall
            }
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
            drafts: ReviewDraftStore(),
            translator: ClaudeFindingTranslator(claude: toolPaths.claude, runner: runner),
            autoRuns: AutoRunLedger(),
            gh: toolPaths.gh,
            health: HealthMonitor()
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

    /// Puntíky pro stavový řádek. Prázdné, když se dostupnost odsud nesleduje.
    var healthReports: [ServiceHealthReport] { health?.reports ?? [] }

    /// Řekne monitoru, jestli je okno vidět — na pozadí se nekontroluje nic.
    ///
    /// Skryté okno interval **neposouvá**, takže po dlouhé nepřítomnosti se zkontroluje
    /// hned na prvním taktu a po krátké se nekontroluje zbytečně. Puntík se stavem z doby,
    /// kdy se nesledovalo, tak nevisí déle než takt.
    func windowVisibilityChanged(_ visible: Bool) {
        health?.isWindowVisible = visible
    }

    /// Jak dopadl poslední dotaz na GitHub — odvozeno z pollingu, ne vedeno zvlášť.
    ///
    /// Polling se ptá každou minutu a je to **totéž volání**, na kterém stojí zbytek
    /// aplikace, takže lepší zdravotní signál se nedá koupit. Ostatní volání gateway
    /// (detail, diff, konverzace) sem schválně nepřitékají: běží nepravidelně a jejich
    /// `notFound` není o dostupnosti, nýbrž o tom, že na PR nevidíme.
    private var gitHubCall: ServiceCall? {
        switch polling.state.status {
        case .notStarted:
            nil
        case .upToDate:
            polling.state.lastSuccess.map { ServiceCall(since: $0) }
        case .failing(let since, let reason):
            ServiceCall(since: since, failure: reason.userDescription)
        case .rateLimited(let since, let retryAt):
            // Rate limit **je** selhané volání, i když si ho aplikace způsobila sama tím,
            // že se ptá moc. Zelená znamená „funguje mi to“ a tady to nefunguje; že za to
            // GitHub nemůže, řekne věta.
            ServiceCall(
                since: since,
                failure: "GitHub omezuje dotazy — zkusím to v \(retryAt.formatted(date: .omitted, time: .shortened))."
            )
        }
    }

    /// Jak dopadla poslední headless session. `nil` = žádná ještě neběžela.
    ///
    /// Jde jen o **review**, ne o překlad nálezů: ten se smí nepovést tiše (nálezy zůstanou
    /// v originále), takže by se z něj červený puntík vyráběl nad něčím, co za chybu ani
    /// nepovažujeme.
    private(set) var lastReviewCall: ServiceCall?

    /// Drží seznam aktuální, dokud okno žije. Zrušení tasku smyčku ukončí.
    func keepFresh() async {
        await reloadConfiguration()
        await loadStoredReviews()
        await loadStoredDrafts()
        // Obojí běží, dokud žije okno; zrušení tasku ukončí skupinu i s oběma smyčkami.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.polling.run() }
            if let health {
                group.addTask { await health.run() }
            }
        }
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

    /// Rozdělaná review z minula. Bez toho by po startu vypadalo každé PR jako nedotčené.
    ///
    /// **Selhání čtení se tady nespolkne**, na rozdíl od nálezů. Nepřečtený soubor sice nikam
    /// nezmizel a příští start ho zkusí znovu, ale u nálezů se nejhůř utratí session, kdežto
    /// tady by chybějící indikátor znamenal, že se ručně psané review napíše podruhé — a to
    /// se druhým pokusem nespraví. Co se nepodařilo přečíst po souborech, se **počítá**.
    func loadStoredDrafts() async {
        guard let draftStore else { return }
        do {
            let loaded = try await draftStore.load()
            drafts = Dictionary(uniqueKeysWithValues: loaded.drafts.map { ($0.pullRequest, $0) })
            unreadableDraftFiles = loaded.unreadable
            pruneBlankComments()
        } catch {
            draftFailure = "Rozdělaná review se nepodařilo načíst. \(error.localizedDescription)"
        }
    }

    /// Zahodí prázdné komentáře, které přežily do dalšího spuštění.
    ///
    /// Za normálního běhu je uklidí bublina, když se od ní odejde. Pád aplikace nebo zabití
    /// zvenčí ale k té chvíli nedojde — a prázdný komentář **blokuje odeslání celého review**,
    /// takže by po restartu zůstal ležet jako důvod, proč to nejde poslat. Nic se tím
    /// neztrácí: prázdný komentář nenese žádný text.
    private func pruneBlankComments() {
        for (pr, draft) in drafts {
            let kept = draft.comments.filter {
                !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard kept.count != draft.comments.count else { continue }
            var pruned = draft
            pruned.comments = kept
            // Prázdný draft se maže — a soubor na disku se musí srovnat s tím, co je v paměti.
            drafts[pr] = pruned.isEmpty ? nil : pruned
            persistDraft(for: pr)
        }
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

    /// Kolik review běží napříč PR. Podle toho se ptá dialog při ukončení aplikace (#94).
    ///
    /// Ze stejného zdroje jako `isReviewing`, ne z vlastního počitadla: dvě místa, která se
    /// můžou rozejít, by v nejhorším nechala aplikaci zavřít bez zeptání.
    var runningReviews: Int { reviewTasks.count }

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

    // MARK: - Taby PR

    /// Který tab je vidět. Výchozí drží `PullRequestTab.standard`, ať je odpověď na jednom
    /// místě — čte ji i test, který hlídá, že se to nerozejde.
    func detailTab(for pr: PRIdentifier) -> PullRequestTab { detailTabs[pr] ?? .standard }

    func setDetailTab(_ tab: PullRequestTab, for pr: PRIdentifier) {
        // Výchozí volba se z mapy maže, ať v ní nezůstávají klíče bez informace.
        detailTabs[pr] = tab == .standard ? nil : tab
    }

    // MARK: - Detail PR

    func detailState(for pr: PRIdentifier) -> DetailState? { detailStates[pr] }

    /// Popis PR, jak ho napsal autor. `nil` = detail se ještě nenačetl.
    func description(of pr: PRIdentifier) -> String? {
        guard case .loaded(let detail, _) = detailStates[pr] else { return nil }
        return detail.body
    }

    /// Hlava PR, jak ji naposledy vrátil `gh pr view`. `nil` = ještě nevíme.
    ///
    /// Na tom visí dvě věci: proti čemu se zakládá nový draft a jestli je ten stávající
    /// zastaralý. „Nevím“ se přitom nesmí splést se „zastaralé“ — proto optional a ne
    /// prázdný řetězec.
    func head(of pr: PRIdentifier) -> String? {
        guard case .loaded(let detail, _) = detailStates[pr] else { return nil }
        return detail.headSha
    }

    /// Dotáhne detail vybraného PR. Načtený se drží, dokud se nezmění `updatedAt` — stejná
    /// cache jako u diffu.
    func loadDetail(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard !hasCurrentDetail(for: pullRequest) else { return }
        detailStates[id] = .loading

        do {
            let detail = try await gateway.fetchDetail(id: id)
            detailStates[id] = .loaded(detail, updatedAt: pullRequest.updatedAt)
        } catch is CancellationError {
            // Maže se **jen** rozdělaný stav: mezitím spuštěné načtení už mohlo doběhnout.
            if detailStates[id] == .loading { detailStates[id] = nil }
        } catch let error as GitHubError {
            detailStates[id] = .failed(error.userDescription)
        } catch {
            detailStates[id] = .failed(error.localizedDescription)
        }
    }

    private func hasCurrentDetail(for pullRequest: PullRequestSummary) -> Bool {
        guard case .loaded(_, let updatedAt) = detailStates[pullRequest.id] else { return false }
        return updatedAt == pullRequest.updatedAt
    }

    // MARK: - Konverzace

    func conversationState(for pr: PRIdentifier) -> ConversationState? { conversationStates[pr] }

    func conversation(for pr: PRIdentifier) -> Conversation? {
        guard case .loaded(let conversation, _) = conversationStates[pr] else { return nil }
        return conversation
    }

    /// Načte konverzaci vybraného PR. Cache stejná jako u diffu — na GitHub se sáhne znovu,
    /// teprve když se změní `updatedAt`.
    ///
    /// **Netahá se při pollingu.** Konverzace pro všech N PR je tatáž N+1 past, kvůli které
    /// se netahá ani detail: jeden tik by byl N podprocesů. Načítá se při výběru řádku.
    func loadConversation(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard !hasCurrentConversation(for: pullRequest) else { return }
        conversationStates[id] = .loading

        do {
            let conversation = try await gateway.fetchConversation(id: id)
            conversationStates[id] = .loaded(conversation, updatedAt: pullRequest.updatedAt)
        } catch is CancellationError {
            // Maže se **jen** rozdělaný stav: mezitím spuštěné načtení už mohlo doběhnout
            // a to se přepsat nesmí. Stejné pravidlo jako u diffu.
            if conversationStates[id] == .loading { conversationStates[id] = nil }
        } catch let error as GitHubError {
            conversationStates[id] = .failed(error.userDescription)
        } catch {
            conversationStates[id] = .failed(error.localizedDescription)
        }
    }

    /// Ruční obnovení konverzace — zahodí uložený stav a načte znovu.
    ///
    /// Kotví se na to, že konverzace **zastarává jinak než diff**: kolega odpoví za minutu
    /// a `updatedAt` se tím sice změní, ale seznam se obnovuje po minutách. Tlačítko je
    /// levnější než čekat na tik.
    func refreshConversation(for pullRequest: PullRequestSummary) async {
        conversationStates[pullRequest.id] = nil
        await loadConversation(for: pullRequest)
    }

    /// Rozdělané načítání se za platnou konverzaci **nepovažuje** — stejný důvod jako
    /// u diffu: přeskočit to jediné, které běží, znamená prázdno v okně.
    private func hasCurrentConversation(for pullRequest: PullRequestSummary) -> Bool {
        guard case .loaded(_, let updatedAt) = conversationStates[pullRequest.id] else { return false }
        return updatedAt == pullRequest.updatedAt
    }

    /// Co patří do tabu `Přehled` — konverzace, která se neváže k řádku v aktuálním diffu.
    ///
    /// Prázdné, dokud konverzace nedorazí. Že se **načítá** nebo že to **selhalo**, se pozná
    /// z `conversationState(for:)`; prázdný seznam sám o sobě neznamená „nikdo nic nenapsal“.
    func overview(for pr: PRIdentifier) -> [ConversationEntry] {
        guard let conversation = conversation(for: pr) else { return [] }
        return Policy.overview(of: conversation, renderedIn: loadedDiff(for: pr))
    }

    /// Vlákna, která se v diffu dají zakotvit — ta se kreslí jako bubliny.
    func anchoredThreads(for pr: PRIdentifier) -> [ReviewThread] {
        guard let conversation = conversation(for: pr) else { return [] }
        return Policy.threadsInTheDiff(conversation.threads.items, renderedIn: loadedDiff(for: pr))
    }

    func isThreadExpanded(_ thread: ReviewThread, in pr: PRIdentifier) -> Bool {
        Policy.isThreadExpanded(thread, toggled: toggledThreads[pr] ?? [])
    }

    // MARK: - Odpovídání do vláken (#73)

    func threadReply(for threadID: String, in pr: PRIdentifier) -> String {
        threadReplies[ThreadKey(pullRequest: pr, threadID: threadID)] ?? ""
    }

    /// Zapíše rozepsaný text. Prázdný se **maže**, ať mapa nedrží záznam po každém vlákně,
    /// do kterého někdo klikl a rozmyslel si to — tentýž vzor jako prázdný draft.
    func setThreadReply(_ text: String, for threadID: String, in pr: PRIdentifier) {
        let key = ThreadKey(pullRequest: pr, threadID: threadID)
        threadReplies[key] = text.isEmpty ? nil : text
    }

    func threadState(for threadID: String, in pr: PRIdentifier) -> ThreadActionState? {
        threadStates[ThreadKey(pullRequest: pr, threadID: threadID)]
    }

    /// Smí se do vláken tohohle repa odesílat?
    ///
    /// Tatáž brána jako u review (`PublishScope`), takže se okno neptá dvakrát jinak. Okno na
    /// ni ale nereaguje schováním tlačítka — nechá ho **zakázané s důvodem**, jinak by
    /// chybějící tlačítko vypadalo jako rozbitá aplikace.
    func canPublishToThreads(in repo: RepoID) -> Bool {
        gh != nil && publishScope.allows(repo)
    }

    /// Odešle rozepsanou odpověď do vlákna a vloží ji do konverzace.
    ///
    /// Text se po úspěchu maže, po selhání **zůstává** — je to zadání #73 a jediná pojistka
    /// proti tomu, aby se rozepsaná věta ztratila kvůli chvilkovému výpadku.
    func sendThreadReply(to thread: ReviewThread, in pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        let key = ThreadKey(pullRequest: id, threadID: thread.id)
        let body = threadReplies[key] ?? ""
        guard let submission = threadSubmission(for: thread.id, in: id) else { return }
        // Dvojklik: druhé odeslání by bylo druhý komentář, ne oprava prvního. Kontrola leží
        // **před** prvním `await`, takže mezi nimi není mezera, do které by se závod vešel.
        guard threadStates[key]?.isBusy != true else { return }
        threadStates[key] = .replying

        do {
            let comment = try await submission.reply(body)
            threadStates[key] = nil
            threadReplies[key] = nil
            insert(comment, intoThread: thread.id, of: pullRequest)
        } catch let error as PublishError {
            threadStates[key] = .replyFailed(error)
        } catch {
            threadStates[key] = .replyFailed(.unknown(error.localizedDescription))
        }
    }

    /// Přepne vyřešení vlákna a zapíše, co GitHub potvrdil.
    func setThreadResolved(
        _ resolved: Bool,
        of thread: ReviewThread,
        in pullRequest: PullRequestSummary
    ) async {
        let id = pullRequest.id
        let key = ThreadKey(pullRequest: id, threadID: thread.id)
        guard let submission = threadSubmission(for: thread.id, in: id) else { return }
        guard threadStates[key]?.isBusy != true else { return }
        threadStates[key] = .resolving(to: resolved)

        do {
            let resolution = try await submission.setResolved(resolved)
            threadStates[key] = nil
            apply(resolution, of: pullRequest)
        } catch let error as PublishError {
            threadStates[key] = .resolutionFailed(error)
        } catch {
            threadStates[key] = .resolutionFailed(.unknown(error.localizedDescription))
        }
    }

    /// Publisher se tu **nevyrábí** — jen se předá `gh`, read-only gateway a brána. Vzniká až
    /// uvnitř `ThreadSubmission`, viz tvrdá podmínka č. 1.
    private func threadSubmission(
        for threadID: String,
        in pr: PRIdentifier
    ) -> ThreadSubmission? {
        guard let gh else { return nil }
        return ThreadSubmission(
            target: ThreadTarget(pullRequest: pr, threadID: threadID),
            gh: gh,
            gateway: gateway,
            scope: publishScope
        )
    }

    /// Vloží odeslanou odpověď do načtené konverzace, ať je vidět bez kola po síti.
    ///
    /// Když vlákno v konverzaci **není** (mezitím se obnovila, nebo ho někdo smazal), konverzace
    /// se načte znovu: odeslaný komentář, který se nemá kde ukázat, vypadá jako neodeslaný.
    private func insert(
        _ comment: ThreadComment,
        intoThread threadID: String,
        of pullRequest: PullRequestSummary
    ) {
        let id = pullRequest.id
        guard case .loaded(let conversation, let updatedAt) = conversationStates[id],
              let updated = Policy.inserting(comment, intoThread: threadID, of: conversation)
        else {
            Task { await refreshConversation(for: pullRequest) }
            return
        }
        conversationStates[id] = .loaded(updated, updatedAt: updatedAt)
    }

    private func apply(_ resolution: ThreadResolution, of pullRequest: PullRequestSummary) {
        let id = pullRequest.id
        guard case .loaded(let conversation, let updatedAt) = conversationStates[id],
              let updated = Policy.applying(resolution, to: conversation)
        else {
            Task { await refreshConversation(for: pullRequest) }
            return
        }
        conversationStates[id] = .loaded(updated, updatedAt: updatedAt)
    }

    func toggleThread(_ thread: ReviewThread, in pr: PRIdentifier) {
        var toggled = toggledThreads[pr] ?? []
        if toggled.contains(thread.id) {
            toggled.remove(thread.id)
        } else {
            toggled.insert(thread.id)
        }
        // Prázdná množina se maže, ať v mapě nezůstávají klíče bez obsahu.
        toggledThreads[pr] = toggled.isEmpty ? nil : toggled
    }

    // MARK: - Tažení rozsahu (#110)

    /// Průběh tažení: `from` je řádek, na kterém začalo, `to` ten pod myší.
    ///
    /// Rozsah se skládá při každém pohybu, protože se z něj kreslí zvýraznění — a musí to být
    /// tentýž rozsah, který vznikne na konci.
    ///
    /// **`to == nil` znamená „pod myší žádný řádek není“** — prázdná protistrana ve split pohledu,
    /// mezera mezi soubory, hlavička hunku. Rozdělaný rozsah se pak **drží**: přejetí přes prázdné
    /// místo není zrušení výběru, a bez tohohle se rozsah srazil na první řádek a po přejetí na
    /// další řádek se zase objevil (nahlášené při zkoušení #110). Dokud ale rozsah není žádný,
    /// platí samotný začátek, ať z tažení vznikne aspoň jednořádkový komentář.
    ///
    /// Když rozsah `Policy` složit nedá (druhý konec v jiném souboru nebo mimo diff), drží se
    /// poslední platný ze stejného důvodu.
    func dragCommentRange(path: String, from: DraftAnchor, to: DraftAnchor?, for pr: PRIdentifier) {
        guard case .loaded(let diff, _) = diffStates[pr], let file = diff.file(at: path) else { return }
        guard let target = to ?? (commentDrag == nil ? from : nil),
              let range = Policy.commentRange(from: from.end, to: target.end, in: file)
        else { return }
        commentDrag = CommentRangeDrag(pullRequest: pr, path: path, anchor: range)
    }

    /// Konec tažení: z rozsahu vznikne komentář. Tažení, které nikam nedošlo (rozsah délky 1),
    /// dá obyčejný jednořádkový komentář — je to totéž, co tlačítko u řádku.
    func finishCommentRange() {
        guard let drag = commentDrag else { return }
        commentDrag = nil
        addDraftComment(at: drag.anchor, path: drag.path, for: drag.pullRequest)
    }

    // MARK: - Pohled na diff

    /// S jakým pohledem se diff kreslí: odchylka z lišty, jinak hodnota z nastavení.
    var diffLayout: DiffLayout {
        diffLayoutOverride ?? configuration.global.diffLayout
    }

    /// Přepnutí z lišty nad diffem.
    ///
    /// Odchylka se zapíše **i tehdy, když se rovná nastavené hodnotě**. Je to totéž pravidlo
    /// jako u `Configuration.setRepository`, kde se maže podle prázdnosti a ne podle shody
    /// s globální hodnotou: kdo si pohled otočil sám, má ho podržet i po změně v nastavení.
    /// Do zavření aplikace — po restartu platí zase nastavení.
    func setDiffLayout(_ layout: DiffLayout) {
        diffLayoutOverride = layout
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

    // MARK: - Rozdělané review

    func draft(for pr: PRIdentifier) -> ReviewDraft? { drafts[pr] }

    /// Je co odeslat? Podle toho svítí indikátor v řádku seznamu i v detailu.
    func hasDraft(_ pr: PRIdentifier) -> Bool { drafts[pr] != nil }

    func draftComments(for pr: PRIdentifier) -> [ReviewDraftComment] { drafts[pr]?.comments ?? [] }

    /// Píše se draft proti staršímu commitu, než je hlava PR?
    ///
    /// `false`, dokud hlavu neznáme: „nevím“ není „zastaralé“ a banner o zablokovaném
    /// odeslání nad načítajícím se detailem by lhal. Odeslání se stejně ptá
    /// `draftSendBlock(for:)`, které neznámou hlavu bere jako vlastní důvod.
    func isDraftStale(for pr: PRIdentifier) -> Bool {
        guard let draft = drafts[pr], let head = head(of: pr) else { return false }
        return Policy.isStale(draft, head: head)
    }

    /// Dá se do draftu psát?
    ///
    /// Nový draft potřebuje `headSha` — bez něj by nešlo poznat, proti čemu je psaný, ani ho
    /// odeslat. Do rozepsaného se psát dá vždycky, ten svůj commit už zná.
    func canComposeDraft(for pr: PRIdentifier) -> Bool {
        drafts[pr] != nil || head(of: pr) != nil
    }

    /// Kam by převzatý nález šel. Bublina podle toho pojmenuje tlačítko a řekne proč.
    func draftTarget(for finding: Finding, in pr: PRIdentifier) -> DraftTarget {
        Policy.draftTarget(for: finding, in: loadedDiff(for: pr))
    }

    /// Je nález už v rozdělaném review?
    func isAdopted(_ finding: Finding, in pr: PRIdentifier) -> Bool {
        Policy.isAdopted(
            finding,
            target: draftTarget(for: finding, in: pr),
            in: drafts[pr],
            repo: pr.repo
        )
    }

    /// Převezme nález do rozdělaného review.
    ///
    /// Kam patří, rozhoduje `Policy.draftTarget` — tedy pravidlo GitHubu, ne vzhled okna:
    /// řádek uvnitř hunku unese řádkový komentář, cokoli jiného jde do těla jako permalink.
    /// Text se předvyplní tím, co napsal reviewer, a jde přepsat.
    func adoptFinding(_ finding: Finding, for pr: PRIdentifier) {
        let text = Policy.adoptedText(of: finding)
        switch draftTarget(for: finding, in: pr) {
        case .line(let path, let anchor):
            addDraftComment(
                at: anchor,
                path: path,
                body: text,
                origin: .finding(reviewer: finding.reviewer),
                for: pr
            )
        case .body(let path, let line):
            appendDraftBodyItem(text: text, path: path, line: line, for: pr)
        }
    }

    /// Založí řádkový komentář. Prázdný schválně — text se dopisuje v bublině.
    func addDraftComment(
        at anchor: DraftAnchor,
        path: String,
        body: String = "",
        origin: ReviewDraftComment.Origin = .own,
        for pr: PRIdentifier
    ) {
        let comment = ReviewDraftComment(path: path, anchor: anchor, body: body, origin: origin)
        mutateDraft(for: pr) { $0.comments.append(comment) }
        // Komentář, který se dá ⇧ klikem roztáhnout na rozsah. Drží se **id**, ne kotva:
        // z komentáře se druhý konec dopočítá, kdežto uložená kotva by se s ním po roztažení
        // rozešla.
        rangeTargets[pr] = comment.id
    }

    /// Roztáhne naposledy přidaný komentář na rozsah končící (nebo začínající) tímhle řádkem.
    ///
    /// Tohle je ⇧ klik na tlačítko u řádku. Když není co roztahovat — nic se nepřidávalo, cíl
    /// se mezitím vyjmul, nebo je v jiném souboru — **založí se obyčejný komentář**. Kliknutí,
    /// po kterém se nestane nic, vypadá jako rozbitá aplikace.
    ///
    /// Rozsah skládá `Policy.commentRange`, protože o pořadí konců rozhoduje diff, ne čísla
    /// (#110). Bez načteného diffu se rozsah nemá o co opřít, takže vyjde jednořádkový komentář.
    func extendDraftComment(to anchor: DraftAnchor, path: String, for pr: PRIdentifier) {
        guard let id = rangeTargets[pr],
              let existing = draft(for: pr)?.comments.first(where: { $0.id == id }),
              existing.path == path,
              case .loaded(let diff, _) = diffStates[pr],
              let file = diff.file(at: path),
              // Na místě zůstává **kotva**, tedy začátek už existujícího rozsahu (u jednořádkového
              // komentáře jeho řádek). Roztahovat od konce by druhým ⇧ klikem zahodilo první konec:
              // z 25–26 by po kliku na 27 vyšlo 26–27. Chytil to test.
              let range = Policy.commentRange(
                  from: existing.anchor.start ?? existing.anchor.end,
                  to: anchor.end,
                  in: file
              )
        else {
            addDraftComment(at: anchor, path: path, for: pr)
            return
        }

        mutateDraft(for: pr) { draft in
            guard let index = draft.comments.firstIndex(where: { $0.id == id }) else { return }
            let comment = draft.comments[index]
            // Nový komentář se **stejným `id`**: kotva je `let`, ale identita musí zůstat, ať
            // si editor udrží rozepsaný text a bublina nepřeskočí jako nová.
            draft.comments[index] = ReviewDraftComment(
                id: comment.id,
                path: comment.path,
                anchor: range,
                body: comment.body,
                origin: comment.origin
            )
        }
    }

    /// Přepíše text komentáře. **Prázdný text komentář zahodí.**
    ///
    /// Prázdné komentáře vznikají běžně (kliknu na „komentovat“ a rozmyslím si to) a GitHub
    /// je odmítne — a protože je odeslání atomické, padlo by s nimi celé review. Nechat je
    /// ležet v draftu znamená hledat, proč se nedá odeslat.
    func updateDraftComment(_ id: UUID, body: String, for pr: PRIdentifier) {
        mutateDraft(for: pr) { draft in
            guard let index = draft.comments.firstIndex(where: { $0.id == id }) else { return }
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.comments.remove(at: index)
            } else {
                draft.comments[index].body = body
            }
        }
    }

    func removeDraftComment(_ id: UUID, for pr: PRIdentifier) {
        mutateDraft(for: pr) { $0.comments.removeAll { $0.id == id } }
    }

    func setDraftBody(_ body: String, for pr: PRIdentifier) {
        mutateDraft(for: pr) { $0.body = body }
    }

    /// Vybere verdikt, nebo volbu zruší (`nil`).
    ///
    /// Nepředvyplňuje se ani návrhem z nálezů: `event` je to jediné, co GitHubu říká, co
    /// s PR udělat, a předvyplněný odhad aplikace by se v okně nedal odlišit od mého
    /// rozhodnutí.
    func setDraftVerdict(_ verdict: ReviewDraft.Verdict?, for pr: PRIdentifier) {
        mutateDraft(for: pr) { $0.verdict = verdict }
    }

    /// Přidá do těla review položku s odkazem na kód.
    ///
    /// Používá se pro nález mimo diff a pro řádek, který komentář neunese — tam GitHub
    /// řádkový komentář nepustí a odmítne s ním celé review (změřeno u #62).
    ///
    /// Odkaz míří na commit, **proti kterému je draft psaný**, ne na aktuální hlavu PR: draft,
    /// který se s hlavou rozešel, se neodešle (banner), ale odkaz v něm pořád ukazuje na kód,
    /// ke kterému se ta věta psala.
    func appendDraftBodyItem(text: String, path: String?, line: Int?, for pr: PRIdentifier) {
        mutateDraft(for: pr) { draft in
            let link = path.flatMap {
                Policy.permalink(to: $0, line: line, in: pr.repo, at: draft.headSha)
            }
            draft.body = Policy.appendingBodyItem(
                Policy.bodyItem(text: text, link: link),
                to: draft.body
            )
        }
    }

    // MARK: - Odeslání review

    /// Proč se rozdělané review nedá odeslat. `nil` = dá se.
    ///
    /// Věta z toho jde do okna: zakázané tlačítko bez důvodu vypadá jako rozbitá aplikace.
    ///
    /// **Proč hlavu neznáme, doplňuje store**, ne `Policy`: ta dostane jen `String?` a z něj
    /// nepozná rozdíl mezi „načítá se“ a „nepovedlo se to“. Slíbit „hned to bude“ nad chybou,
    /// která sama nezmizí, je přitom horší než mlčet.
    func draftSendBlock(for pr: PRIdentifier) -> DraftSendBlock? {
        let block = Policy.sendBlock(for: drafts[pr], head: head(of: pr), scope: publishScope)
        guard case .headUnknown = block, case .failed(let detail) = detailStates[pr] else {
            return block
        }
        return .headUnknown(detail: detail)
    }

    /// Návrh verdiktu z nálezů. `nil` = není z čeho soudit.
    ///
    /// V potvrzení odeslání stojí **vedle** zvoleného verdiktu, aby se dalo porovnat —
    /// nepředvyplňuje nic.
    func suggestedVerdict(for pr: PRIdentifier) -> ReviewVerdict? {
        guard let record = reviewRecords[pr] else { return nil }
        return Policy.suggestedVerdict(
            for: record,
            categories: resolved(for: pr.repo).blockingCategories
        )
    }

    /// Složí jedno odeslání — snímek toho, co je teď v draftu.
    ///
    /// `nil` znamená „odeslat teď nejde“ a tlačítko, které to volá, je v takovém stavu
    /// zakázané; kontrola je tady podruhé proto, že sheet se nad zastaralým draftem **nemá
    /// otevřít vůbec** a spoléhat se na to, že si to view pohlídá, je o jedno místo k
    /// zapomenutí víc.
    ///
    /// Publisher se tu **nevyrábí** — jen se předá `gh` a read-only gateway. Vzniká až
    /// v `ReviewSubmission.send()`, viz tvrdá podmínka č. 1.
    func submission(for pullRequest: PullRequestSummary) -> ReviewSubmission? {
        let id = pullRequest.id
        guard let gh, let draft = drafts[id], draftSendBlock(for: id) == nil else { return nil }
        return ReviewSubmission(
            pullRequest: pullRequest,
            draft: draft,
            suggestion: suggestedVerdict(for: id),
            gh: gh,
            gateway: gateway,
            scope: publishScope,
            afterSuccess: { [weak self] in await self?.draftWasSubmitted(for: pullRequest) }
        )
    }

    /// Brána na odesílání, složená **z aktuální konfigurace**.
    ///
    /// Čte se při použití, ne při startu — jako limit souběhu nebo rozpočet cache — takže
    /// přepnutí v okně nastavení platí bez restartu. Je to počítaná vlastnost schválně:
    /// uložený snímek by se s konfigurací rozešel.
    private var publishScope: PublishScope { PublishScope(configuration: configuration) }

    /// Úklid po odeslaném review: draft je pryč a konverzace se načte znovu.
    ///
    /// Draft se maže **až tady**, tedy po potvrzené odpovědi GitHubu — selhání ho nechává
    /// netknutý, aby se dalo zkusit znovu bez psaní nanovo.
    ///
    /// Konverzace se obnovuje proto, že v ní od téhle chvíle leží moje vlastní review; bez
    /// toho by v tabu `Přehled` chybělo až do dalšího přepnutí PR. Cache jde podle
    /// `updatedAt`, které se odesláním review na GitHubu měnit nemusí, takže se zahazuje
    /// ručně (`refreshConversation`).
    func draftWasSubmitted(for pullRequest: PullRequestSummary) async {
        discardDraft(for: pullRequest.id)
        await refreshConversation(for: pullRequest)
    }

    /// Zahodí celé rozdělané review. Idempotentní — na tlačítko se dá zmáčknout dvakrát.
    func discardDraft(for pr: PRIdentifier) {
        guard drafts[pr] != nil else { return }
        drafts[pr] = nil
        persistDraft(for: pr)
    }

    /// Jediná cesta, kterou se draft mění — a hned se ukládá.
    ///
    /// `headSha` nového draftu se bere z detailu; bez něj se draft **nezakládá**, protože by
    /// nešlo poznat, proti čemu je psaný. Existujícímu draftu se `headSha` nepřepisuje —
    /// přenesení na nový commit je #69.
    private func mutateDraft(for pr: PRIdentifier, _ change: (inout ReviewDraft) -> Void) {
        guard var draft = drafts[pr] ?? head(of: pr).map({ ReviewDraft(pullRequest: pr, headSha: $0) })
        else { return }
        change(&draft)
        // Prázdný draft se maže — „draft existuje“ musí znamenat „je co poslat“.
        drafts[pr] = draft.isEmpty ? nil : draft
        persistDraft(for: pr)
    }

    /// Uloží draft na disk.
    ///
    /// Hodnota se čte **až v tasku**, ne teď: dvě rychlé úpravy za sebou tak zapíšou tentýž
    /// konečný stav a nezáleží na tom, v jakém pořadí se tasky provedou. Kdyby se draft
    /// zachytil do closure, pozdější task by mohl zapsat starší podobu.
    private func persistDraft(for pr: PRIdentifier) {
        guard draftStore != nil else { return }
        Task { [weak self] in await self?.writeDraft(for: pr) }
    }

    private func writeDraft(for pr: PRIdentifier) async {
        guard let draftStore else { return }
        do {
            if let draft = drafts[pr] {
                try await draftStore.save(draft)
            } else {
                // Prázdný draft `save` maže sám, ale tady už v paměti není co uložit.
                try await draftStore.delete(for: pr)
            }
            draftFailure = nil
        } catch {
            draftFailure = "Rozdělané review se nepodařilo uložit. \(error.localizedDescription)"
        }
    }

    private func loadedDiff(for pr: PRIdentifier) -> Diff? {
        guard case .loaded(let diff, _) = diffStates[pr] else { return nil }
        return diff
    }

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

    /// Kolik review dnes automat spustil. `nil` = automat není nastavený nikde, takže se
    /// o limitu nemá co mluvit.
    ///
    /// **Spotřeba, ne zbytek.** Porovnání s limitem patří tam, kde se kreslí, protože limit
    /// se dá změnit v nastavení kdykoli — snímek „zbývá 0“ by po zvednutí limitu tvrdil, že
    /// je pozastaveno, až do dalšího tiku.
    private(set) var automaticRunsToday: Int?

    /// Nespustí automat nic? Počítá se **teď**, z aktuálního limitu.
    ///
    /// Pokrývá **dva důvody** a schválně je nerozlišuje: vyčerpaný limit a limit nastavený
    /// na nulu. Pro rozhodnutí „ukázat hlášku“ je to totéž — repo je v automatickém režimu
    /// a nic se nespustí. Který z těch dvou to je, rozlišuje až text hlášky, protože
    /// „vyčerpaný limit (0)“ by tvrdilo, že se něco spotřebovalo.
    var isAutomaticStopped: Bool {
        guard let automaticRunsToday else { return false }
        return automaticRunsToday >= configuration.global.autoRunsPerDay
    }

    /// Naplánuje review pro repa v automatickém režimu.
    ///
    /// Volá se **jen po úspěšném tiku**: po výpadku sítě je seznam prázdný, takže by se
    /// nespustilo nic a `consideredForAutomation` by se rozešlo se skutečností.
    private func startAutomaticReviews(for summaries: [PullRequestSummary]) async {
        guard let autoRuns else { return }
        let limit = configuration.global.autoRunsPerDay
        let anyAutomatic = summaries.contains { resolved(for: $0.repo).mode == .automatic }
        automaticRunsToday = anyAutomatic ? await autoRuns.used() : nil

        let candidates = Policy.automaticallyReviewable(
            in: summaries,
            configuration: configuration,
            considered: consideredForAutomation,
            running: Set(reviewTasks.keys)
        )
        let updates = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0.updatedAt) })

        // Vyčerpaný rozpočet zastaví plánování **dřív**, než se sáhne na síť. Jinak by
        // každý tik stál `gh pr view` za PR, které se stejně nespustí.
        //
        // `?? 0` není tichý default: hodnota se o dva řádky výš právě načetla z disku a
        // `nil` je jen ve stavu „žádné automatické repo“, kdy je `candidates` stejně prázdné.
        guard (automaticRunsToday ?? 0) < limit else { return }

        for pr in candidates {
            // Zapsat se to smí až potom, co se běh opravdu naplánoval. Obrácené pořadí by
            // znamenalo, že PR zamítnutý rozpočtem se už nikdy nezváží.
            consideredForAutomation[pr] = updates[pr]
            automaticReviews.insert(pr)
            reviewTasks[pr] = Task { [weak self] in await self?.review(pr) }
        }
    }

    /// Smí tenhle běh utratit session?
    ///
    /// Ruční se neptá — za tím vždycky někdo stojí. Automatický si sáhne o denní rozpočet,
    /// a jen když je co spustit: repo s prázdnou sadou skillů („tady nereviewuj nic“) žádnou
    /// session neutratí, takže by za ni neměl nikdo platit.
    private func canSpendSession(on pr: PRIdentifier) async -> Bool {
        guard automaticReviews.contains(pr) else { return true }
        guard !reviewSkills(for: pr.repo).isEmpty else {
            reviewPhases[pr] = nil
            return false
        }
        guard await claimAutomaticRun(for: pr) else {
            reviewPhases[pr] = nil
            return false
        }
        return true
    }

    /// Sáhne si o rozpočet pro automatický běh. `false` = dnes už ne.
    ///
    /// Volá se **až potom, co je jasné, že se utratí session** — tedy za bránou na
    /// `headSha`. Strhávat ho v plánovači znamenalo počítat i běhy, které se po dotažení
    /// detailu zahodí, a protože se `consideredForAutomation` po restartu vynuluje, spálil
    /// každý restart rozpočet za všechna auto PR, aniž by se cokoli spustilo.
    private func claimAutomaticRun(for pr: PRIdentifier) async -> Bool {
        guard let autoRuns else { return true }
        let allowed = await autoRuns.take(limit: configuration.global.autoRunsPerDay)
        automaticRunsToday = await autoRuns.used()
        // Zamítnutý PR se musí dát zvážit znovu, jinak by o review přišel i zítra, kdy je
        // rozpočet volný — `updatedAt` se od té doby nemusí změnit.
        if !allowed { consideredForAutomation[pr] = nil }
        return allowed
    }

    /// Zahodí uložené nálezy vybraného PR.
    ///
    /// Smysl je pustit review znovu, typicky jiným skillem: nový běh **nahrazuje jen běh
    /// téhož skillu**, takže po změně sady zůstávají v záznamu nálezy od revieweera, který
    /// už neběží — a návrh verdiktu počítá z obojího.
    ///
    /// Maže se jen záznam pro commit, který je **vidět** — ostatní zůstávají. „Historie
    /// zůstává“ se tedy vztahuje na ostatní záznamy, ne na ochranu toho viditelného: kdo
    /// zmáčkne zahodit nad zastaralými nálezy, chce se zbavit právě jich.
    ///
    /// Selhání **letí ven**: nesmazaný záznam, o kterém se mlčí, vypadá v panelu jako
    /// smazaný, dokud si někdo nevšimne, že se po restartu vrátil.
    func clearFindings(for pr: PRIdentifier) async throws {
        guard let reviews, let record = reviewRecords[pr] else { return }
        try await reviews.delete(for: pr, at: record.headSha)
        reviewRecords[pr] = nil

        // Plánovač si pamatuje `updatedAt`, se kterým PR naposledy zvažoval, takže by ho po
        // vyčištění považoval za vyřízený až do dalšího pushe. Zahození nálezů je ale právě
        // ta chvíle, kdy se má review pustit znovu.
        consideredForAutomation[pr] = nil
        // A hned, ne až za minutu: kdo nálezy zahodí, čeká výsledek, ne příští tik. Jde se
        // tou samou cestou jako po tiku, včetně rozpočtu a limitu souběhu. U manuálního repa
        // se nestane nic — tam se spouští tlačítkem.
        await startAutomaticReviews(for: pullRequests)
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
            // Nemá cenu klonovat kvůli commitu, který je zreviewovaný. Rozpočet se tu ale
            // **nestrhává** — session utrácí až `runSkills` a mezi tím může selhat checkout.
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

            // Rozpočet **až tady**: `runSkills` je jediné místo, které session utrácí.
            // Cokoli dřív znamená platit i za běhy, které se nikdy nerozjely — selhal
            // checkout, nebo repo nemá nastavený žádný skill. Ráno to spálilo šest z dvaceti
            // za jedno dopoledne, když se to strhávalo v plánovači, a znovu, když se to
            // strhávalo před checkoutem.
            guard await canSpendSession(on: pr) else { return }

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
        record(outcome)
        guard var timelines = reviewTimelines[pr],
              let index = timelines.firstIndex(where: { $0.skill == skill })
        else { return }
        timelines[index].finish(outcome, at: time.now)
        reviewTimelines[pr] = timelines
    }

    /// Doběhlý běh jako zdravotní signál Claude — puntík ve stavovém řádku jede na skutečném
    /// provozu, ne na sondě.
    ///
    /// **`timedOut` nezapisuje nic.** Session jsme po patnácti minutách zabili sami, takže
    /// z toho nejde vyvodit ani „funguje“, ani „nefunguje“ — a dlouhé review je běžná věc.
    /// `failed` naopak signál je, i když příčina může být na naší straně (třeba neexistující
    /// skill); věta v nápovědě proto říká, co přišlo na stderr, a to, jestli za to může
    /// Claude, se pozná ze žlutého puntíku.
    /// **Při opakovaném selhání se `since` drží.** Nese začátek výpadku, ne poslední pokus —
    /// jinak by se „Nedaří se od …“ posouvalo s každou další spadlou session a nešlo by poznat,
    /// jak dlouho to trvá. Je to tatáž úvaha (a tatáž věta v nápovědě) jako
    /// `PollingService.failingSince`; u GitHubu ji drží `PollState`, tady ji musí držet tohle.
    private func record(_ outcome: ReviewRunOutcome) {
        switch outcome {
        case .finished:
            lastReviewCall = ServiceCall(since: time.now)
        case .failed(let detail):
            let failingSince = lastReviewCall.flatMap { $0.succeeded ? nil : $0.since } ?? time.now
            lastReviewCall = ServiceCall(since: failingSince, failure: detail)
        case .timedOut:
            break
        }
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
        // Detail se drží jen pro to, co je v seznamu — je z něj `headSha` pro draft, a ten
        // se u PR mimo seznam nepíše. Rozdělané načítání přežije jako u diffu.
        //
        // **Rozdělané review se nezahazuje.** Je to ručně psaná práce, mapa je jeden malý
        // záznam na PR a PR, které ze seznamu vypadlo, se do něj umí vrátit (znovuotevření).
        detailStates = detailStates.filter {
            wantedPullRequests.contains($0.key) || $0.value == .loading
        }
        // Konverzace se drží ze stejného důvodu jako diff — u PR s desítkami vláken to nejsou
        // kilobajty. Rozdělané načítání přežije, aby si ho doběhlé volání nezapsalo zpátky.
        conversationStates = conversationStates.filter {
            wantedPullRequests.contains($0.key) || $0.value == .loading
        }
        // Překliknutá vlákna se uklízejí podle **PR**, ne podle vláken v načtených
        // konverzacích. Podle konverzací to nešlo: PR ve stavu `.failed` v mapě zůstane, ale
        // žádná vlákna nedá, takže by výpadek sítě uživateli zahodil, co si zavřel.
        toggledThreads = toggledThreads.filter { wantedPullRequests.contains($0.key) }
        // Rozepsané odpovědi a stavy odesílání jdou s konverzací, ke které patří. Klíč nese PR
        // právě kvůli tomuhle — z `id` vlákna by se nepoznalo, ke kterému PR patří.
        threadReplies = threadReplies.filter { wantedPullRequests.contains($0.key.pullRequest) }
        threadStates = threadStates.filter { wantedPullRequests.contains($0.key.pullRequest) }
        // Volba tabu je jen příznak, ale drží klíč s celým identifikátorem PR — bez úklidu by
        // mapa rostla donekonečna, stejně jako u sbalených souborů.
        detailTabs = detailTabs.filter { wantedPullRequests.contains($0.key) }
        // Cíl pro ⇧ klik (#110) je jen zkratka pro to, co je zrovna na obrazovce. Draft sám se
        // drží dál — kdyby se PR vrátilo, komentáře v něm jsou, jen se ⇧ klikem nedá roztáhnout
        // něco, na co se člověk mezitím přestal dívat.
        rangeTargets = rangeTargets.filter { wantedPullRequests.contains($0.key) }
        // Rozdělané tažení nemá s PR mimo seznam co dělat — a je to stav v řádu sekundy.
        if let drag = commentDrag, !wantedPullRequests.contains(drag.pullRequest) { commentDrag = nil }
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
