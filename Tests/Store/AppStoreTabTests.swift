import Foundation
import Testing

@testable import PRism

/// Volba tabu PR. Žije ve store, ne ve view — jinak by přetekla z jednoho PR na druhý.
@Suite("AppStore — taby PR")
@MainActor
struct AppStoreTabTests {
    private let first = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let second = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 43)

    private func summary(_ pr: PRIdentifier) -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(_ summaries: [PullRequestSummary]) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success(summaries)),
            time: FakeTimeSource()
        )
    }

    /// Popis a diskuze je to, co se čte **než** se člověk podívá na kód — a stejně to má
    /// GitHub. Změna proti zadání #72, které předepisovalo `filesChanged`.
    @Test("PR se otevírá na přehledu")
    func defaultsToOverview() {
        #expect(PullRequestTab.standard == .overview)
        #expect(store([]).detailTab(for: first) == .overview)
    }

    @Test("Volba tabu se drží per PR")
    func keepsTheChoicePerPullRequest() {
        let store = store([])

        store.setDetailTab(.filesChanged, for: first)

        #expect(store.detailTab(for: first) == .filesChanged)
        #expect(store.detailTab(for: second) == .overview, "volba přetekla na jiné PR")
    }

    @Test("Přepnutí zpátky vrátí výchozí stav")
    func switchesBack() {
        let store = store([])
        store.setDetailTab(.filesChanged, for: first)

        store.setDetailTab(.overview, for: first)

        #expect(store.detailTab(for: first) == .overview)
        // Výchozí volba se z mapy maže, ať v ní nezůstávají klíče bez informace.
        #expect(store.detailTabs.isEmpty)
    }

    // MARK: - Volba tabu se nezarovnává na data (#306)

    private var passing: [PullRequestCheck] {
        [PullRequestCheck(name: "phpcs", outcome: .passed, link: nil, startedAt: nil, completedAt: nil)]
    }

    /// **Nejcennější test téhle sady** (#306) — tvrdí, že se něco NEstalo: volba tabu se nemění
    /// tím, co zrovna dorazilo ze sítě. Do #306 se zarovnávala na `Policy.tabs(hasChecks:)`, takže
    /// člověk z tabu `Kontroly` vypadl při **každém** příchodu na PR (checky se dotahují s detailem,
    /// takže chvíli nejsou) a u PR bez CI se do něj nedostal vůbec. Projde se všemi čtyřmi stavy
    /// checků, protože zarovnání by se dalo vrátit u kteréhokoli z nich.
    @Test("Volba Kontroly přežije každý stav checků")
    func keepsTheChecksTabInEveryDataState() {
        let store = store([])
        store.setDetailTab(.checks, for: first)

        // Nenačteno — jako hned po přepnutí PR.
        store.checks[first] = nil
        #expect(store.detailTab(for: first) == .checks)

        // PR bez CI.
        store.checks[first] = []
        #expect(store.detailTab(for: first) == .checks)

        // Seznam.
        store.checks[first] = passing
        #expect(store.detailTab(for: first) == .checks)

        // Porucha bez starých checků.
        store.checks[first] = nil
        store.checkFailures[first] = "gh spadl"
        #expect(store.detailTab(for: first) == .checks)
    }

    /// Volba zůstává **per PR** i po tom, co zarovnání odpadlo: druhé PR se otevírá `Přehledem`,
    /// i když v prvním sedím v `Kontrolách`.
    @Test("Volba Kontroly nepřeteče na jiné PR")
    func doesNotLeakTheChecksTab() {
        let store = store([])
        store.setDetailTab(.checks, for: first)

        #expect(store.detailTab(for: second) == .overview)
    }

    // MARK: - Co je v tabu k vidění (#306)

    /// Tab se kreslí vždycky, takže se z těch čtyř stavů musí dát poznat, který je který — a hlavně
    /// se **nenačteno nesmí čít jako „PR nemá CI“**. Rozhodování samo je vyčerpané v
    /// `ChecksTabStateTests`; tady se hlídá, že store skládá stav ze **správných dvou map**.
    @Test("Stav tabu se skládá z checků a z poruchy")
    func buildsTheTabStateFromBothMaps() {
        let store = store([])

        #expect(store.checksTabState(for: first) == .loading)

        store.checks[first] = []
        #expect(store.checksTabState(for: first) == .empty)

        store.checks[first] = passing
        #expect(store.checksTabState(for: first) == .list(passing, failure: nil))

        store.checkFailures[first] = "timeout"
        #expect(store.checksTabState(for: first) == .list(passing, failure: "timeout"))

        store.checks[first] = nil
        #expect(store.checksTabState(for: first) == .failed("timeout"))
    }

    // MARK: - Selhané načtení checků není „PR bez CI“ (#215)

    private func gateway(
        checks: [PullRequestCheck] = [],
        failure: (any Error)? = nil,
        detail: Result<PullRequest, any Error>? = nil
    ) -> FakeGitHubGateway {
        let gateway = FakeGitHubGateway(always: .success([summary(first)]), detail: detail)
        gateway.checks = checks
        gateway.checksFailure = failure
        return gateway
    }

    /// Detail k `first`. Testy, které chodí přes `loadDetail`, ho **potřebují úspěšný** — bez něj
    /// spadne a `hasCurrentDetail` je pak pořád `false`, takže by se cesta z cache nikdy neprošla
    /// a test by měřil něco jiného, než co má napsané v titulku.
    private var detail: PullRequest {
        PullRequest(
            id: first,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: summary(first).url,
            updatedAt: summary(first).updatedAt,
            state: .open,
            body: ""
        )
    }

    /// **Nejcennější test téhle sady.** Do #215 to bylo `try? … ?? []`, takže z chyby sítě vyšlo
    /// prázdno — a prázdno znamená „tenhle PR nemá CI“. Tiše by tedy z poruchy vyšlo tvrzení
    /// o pull requestu.
    @Test("Selhání se zapíše, prázdno se z něj nestane")
    func recordsAFailureInsteadOfEmptyChecks() async {
        let store = AppStore(
            gateway: gateway(failure: GitHubError.toolUnavailable("gh není po ruce")),
            time: FakeTimeSource()
        )

        await store.loadChecks(for: first)

        #expect(store.checks[first] == nil, "porucha se zapsala jako „žádné checky“")
        #expect(store.checkFailures[first] != nil)
        // A v tabu je vidět porucha, ne „PR nemá CI“ (#306) — i s textem od `gh`, protože je to
        // jediné, z čeho se pozná, co dělat dál.
        #expect(store.checksTabState(for: first)
            == .failed(GitHubError.toolUnavailable("gh není po ruce").userDescription))
    }

    /// PR bez CI je běžný stav, ne porucha — nesmí se z něj stát hlášení o chybě.
    @Test("PR bez checků žádnou poruchu nehlásí")
    func doesNotReportAFailureForAPullRequestWithoutCI() async {
        let store = AppStore(gateway: gateway(checks: []), time: FakeTimeSource())

        await store.loadChecks(for: first)

        #expect(store.checks[first] == [])
        #expect(store.checkFailures[first] == nil)
    }

    /// Po selhání se **stará sada nechává být**: zastaralý seznam s větou nad ním je pořád lepší
    /// než plocha s chybou místo checků, které se před chvílí načetly.
    @Test("Selhané načtení nezahodí to, co už bylo")
    func keepsPreviousChecksAfterAFailure() async {
        let check = PullRequestCheck(
            name: "phpcs",
            outcome: .passed,
            link: nil,
            startedAt: nil,
            completedAt: nil
        )
        let gateway = gateway(checks: [check])
        let store = AppStore(gateway: gateway, time: FakeTimeSource())
        await store.loadChecks(for: first)

        gateway.checksFailure = GitHubError.timedOut
        await store.loadChecks(for: first)

        #expect(store.checks[first] == [check], "zastaralý seznam se zahodil")
        #expect(store.checkFailures[first] != nil)
        // Seznam zůstává vidět **i s důvodem** (#306): věta o zastaralosti patří nad něj.
        #expect(store.checksTabState(for: first)
            == .list([check], failure: GitHubError.timedOut.userDescription))
    }

    /// Selhaný pokus se musí dát **zopakovat** (#306): `loadDetail` má cache podle `updatedAt`,
    /// takže by po chybě sítě už checky nikdo nedotáhl a tab by v poruše zůstal do dalšího commitu.
    /// Tlačítko `Zkusit znovu` v tabu chodí přímo sem.
    @Test("Zkusit znovu poruchu opravdu přepíše")
    func retriesAfterAFailure() async {
        let gateway = gateway(checks: [], failure: GitHubError.timedOut)
        let store = AppStore(gateway: gateway, time: FakeTimeSource())
        await store.loadChecks(for: first)
        #expect(store.checksTabState(for: first) == .failed(GitHubError.timedOut.userDescription))

        gateway.checks = [
            PullRequestCheck(name: "phpcs", outcome: .passed, link: nil, startedAt: nil, completedAt: nil),
        ]
        gateway.checksFailure = nil
        await store.loadChecks(for: first)

        #expect(store.checksTabState(for: first) == .list(gateway.checks, failure: nil))
    }

    /// Checky se tahají s detailem — **ale i tehdy, když detail spadl** (#306). Bez toho by v tabu
    /// `Kontroly` nad spadlým detailem svítilo `Načítám kontroly…` navždycky, protože `loadChecks`
    /// se v takovém případě vůbec nespustil.
    @Test("Spadlý detail nezastaví načtení kontrol")
    func loadsChecksEvenWhenTheDetailFails() async {
        let gateway = FakeGitHubGateway(
            always: .success([summary(first)]),
            detail: .failure(GitHubError.notFound("PR neznám."))
        )
        gateway.checks = [
            PullRequestCheck(name: "phpcs", outcome: .passed, link: nil, startedAt: nil, completedAt: nil),
        ]
        let store = AppStore(gateway: gateway, time: FakeTimeSource())

        await store.loadDetail(for: summary(first))

        #expect(store.detailState(for: first) == .failed(GitHubError.notFound("PR neznám.").userDescription))
        #expect(store.checksTabState(for: first) == .list(gateway.checks, failure: nil),
                "checky se kvůli spadlému detailu nedotáhly — tab by tvrdil, že se načítají")
    }

    /// **Zrušené načtení checků se musí dotáhnout po návratu na PR** (#306). `loadChecks` běží až
    /// po detailu, takže přepnutí PR uprostřed toho volání ho zruší — a zrušení se schválně
    /// nezapisuje, protože to není porucha. Detail je ale po návratu z cache, takže bez dotažení
    /// v `guardu` by v tabu svítilo `Načítám kontroly…` navždycky a nic by neběželo.
    @Test("Po zrušeném načtení se checky dotáhnou při návratu na PR")
    func fetchesChecksMissedByCancellation() async {
        let gateway = gateway(checks: [], failure: CancellationError(), detail: .success(detail))
        let store = AppStore(gateway: gateway, time: FakeTimeSource())
        await store.loadDetail(for: summary(first))
        #expect(store.detailState(for: first) != nil)
        #expect(store.checksTabState(for: first) == .loading, "zrušení se zapsalo jako stav")

        // Návrat na PR: detail je z cache, takže se nenačítá znovu.
        gateway.checks = [
            PullRequestCheck(name: "phpcs", outcome: .passed, link: nil, startedAt: nil, completedAt: nil),
        ]
        gateway.checksFailure = nil
        await store.loadDetail(for: summary(first))

        #expect(store.checksTabState(for: first) == .list(gateway.checks, failure: nil))
    }

    /// A hotová odpověď se při návratu **nepřepisuje** — ani prázdno, ani porucha. Jinak by z checků
    /// byl polling: dotahovaly by se při každém příchodu na PR.
    @Test("Hotovou odpověď návrat na PR nepřepíše")
    func doesNotRefetchSettledChecks() async {
        let gateway = gateway(checks: [], detail: .success(detail))
        let store = AppStore(gateway: gateway, time: FakeTimeSource())
        await store.loadDetail(for: summary(first))
        #expect(store.checksTabState(for: first) == .empty)

        // PR bez CI: kdyby se checky tahaly znovu, tenhle check by se v tabu objevil.
        gateway.checks = [
            PullRequestCheck(name: "phpcs", outcome: .passed, link: nil, startedAt: nil, completedAt: nil),
        ]
        await store.loadDetail(for: summary(first))

        #expect(store.checksTabState(for: first) == .empty, "prázdná odpověď se přepsala")
    }

    /// A když spadne obojí, tab hlásí poruchu kontrol, ne nekonečné načítání.
    @Test("Spadlý detail i kontroly dají v tabu poruchu")
    func reportsAFailureWhenBothFail() async {
        let gateway = FakeGitHubGateway(
            always: .success([summary(first)]),
            detail: .failure(GitHubError.notFound("PR neznám."))
        )
        gateway.checksFailure = GitHubError.timedOut
        let store = AppStore(gateway: gateway, time: FakeTimeSource())

        await store.loadDetail(for: summary(first))

        #expect(store.checksTabState(for: first) == .failed(GitHubError.timedOut.userDescription))
    }

    /// Povedený pokus musí starou poruchu **smazat**, jinak by věta o zastaralosti zůstala svítit
    /// nad načtenými checky.
    @Test("Povedené načtení poruchu smaže")
    func clearsTheFailureOnSuccess() async {
        let gateway = gateway(failure: GitHubError.timedOut)
        let store = AppStore(gateway: gateway, time: FakeTimeSource())
        await store.loadChecks(for: first)
        #expect(store.checkFailures[first] != nil)

        gateway.checksFailure = nil
        await store.loadChecks(for: first)

        #expect(store.checkFailures[first] == nil)
        #expect(store.checks[first] == [])
    }

    /// Bez úklidu by mapa rostla donekonečna — drží klíč s celým identifikátorem PR.
    @Test("Volba tabu se zahodí s PR, které zmizelo ze seznamu")
    func forgetsTabsOfGonePullRequests() async {
        let store = AppStore(
            gateway: FakeGitHubGateway([.success([summary(first)]), .success([])]),
            time: FakeTimeSource()
        )
        await store.refresh()
        store.setDetailTab(.filesChanged, for: first)

        await store.refresh()

        #expect(store.detailTab(for: first) == .overview)
        #expect(store.detailTabs.isEmpty)
    }
}
