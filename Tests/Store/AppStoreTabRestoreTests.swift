import Foundation
import Testing

@testable import PRism

/// Záložky, které přežijí restart (#527).
///
/// **Nejcennější polovina sady tvrdí, že se něco NEstalo**: obnovení nepustí review ani session,
/// nepřipraví pracovní kopii a mergnutý PR nezavře. Rozbilo by se to potichu — v okně by po
/// startu vypadalo úplně stejně, jen by se za review platilo, a to se pozná až na účtu.
///
/// Druhá polovina je o tom, co naopak **přežít musí**: první tik, který obnovenou záložku
/// v seznamu nenajde, ji nesmí vyprázdnit.
@Suite("AppStore — obnovení záložek (#527)")
@MainActor
struct AppStoreTabRestoreTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let tabs: OpenTabsStore
    private let vault = PRIdentifier("keboola/vault#85")!
    private let listed = PRIdentifier("cli/cli#1")!
    private let merged = PRIdentifier("ondrajodas/PRism#171")!

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        tabs = OpenTabsStore(layout: layout)
    }

    private func summary(_ id: PRIdentifier) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "titulek \(id.number)",
            author: "odinuv",
            url: Policy.githubURL(of: id),
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func detail(_ id: PRIdentifier, state: PullRequestState = .open) -> PullRequest {
        PullRequest(
            id: id,
            title: "z detailu \(id.number)",
            author: "odinuv",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            headRef: "feat/ttl",
            baseRef: "main",
            url: Policy.githubURL(of: id),
            updatedAt: Date(timeIntervalSince1970: 300),
            state: state
        )
    }

    /// Store po jednom tiku, se snímkem záložek na disku. Jeden zdroj, ne výchozí dva — fake
    /// gateway spotřebovává odpovědi po dotazech (tatáž úvaha jako jinde ve `Tests/Store`).
    private func started(
        list: [PullRequestSummary] = [],
        detail: Result<PullRequest, any Error> = .success(PullRequest(
            id: PRIdentifier("keboola/vault#85")!,
            title: "z detailu",
            author: "odinuv",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/keboola/vault/pull/85")!,
            updatedAt: Date(timeIntervalSince1970: 300),
            state: .open
        )),
        reviewer: FakeReviewRunner = FakeReviewRunner(),
        checkout: FakeRepoCheckout = FakeRepoCheckout(),
        mode: ReviewMode = .manual,
        withStore: Bool = true
    ) async -> (AppStore, FakeGitHubGateway) {
        var configuration = Configuration.standard
        configuration.global.sources = [.reviewRequested]
        configuration.global.mode = mode
        let gateway = FakeGitHubGateway(always: .success(list), detail: detail)
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            checkout: checkout,
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            openTabsStore: withStore ? tabs : nil,
            autoRuns: AutoRunLedger(layout: layout, time: FakeTimeSource()),
            cacheLayout: layout
        )
        await store.keepFresh()
        return (store, gateway)
    }

    private func settle(_ store: AppStore, _ id: PRIdentifier) async {
        await waitUntil("detail \(id) dorazí") { store.detailStates[id] != .loading }
    }

    // MARK: - Zápis snímku

    @Test("Otevření, přepnutí i zavření záložky se zapíše")
    func everyTabChangeIsWritten() async {
        let (store, _) = await started(list: [summary(listed), summary(vault)])

        store.openTab(listed)
        #expect(tabs.load().tabs.map(\.pullRequest) == [listed])
        #expect(tabs.load().active == listed)

        store.openTab(vault)
        #expect(tabs.load().tabs.map(\.pullRequest) == [listed, vault])
        #expect(tabs.load().active == vault)

        store.setDetailTab(.filesChanged, for: vault)
        #expect(tabs.load().tabs.last?.tab == .filesChanged)

        store.selectTab(.backward)
        #expect(tabs.load().active == listed)

        store.closeTab(listed)
        #expect(tabs.load().tabs.map(\.pullRequest) == [vault])
        #expect(tabs.load().active == vault)
    }

    /// Odchod na domácí záložku je taky změna aktivní záložky — bez tohohle by se po restartu
    /// otevřel PR, ze kterého člověk odešel.
    @Test("Odchod domů zapíše prázdnou aktivní záložku")
    func goingHomeClearsTheActiveTab() async {
        let (store, _) = await started(list: [summary(listed)])
        store.openTab(listed)

        store.show(.queue)

        #expect(tabs.load().active == nil)
        #expect(tabs.load().tabs.map(\.pullRequest) == [listed])
    }

    @Test("Kotva scrollu jde do snímku, a jen u otevřené záložky")
    func theScrollAnchorIsRecorded() async {
        let (store, _) = await started(list: [summary(listed), summary(vault)])
        store.openTab(listed)

        store.noteDiffScrollAnchor(DiffScrollAnchor(file: "App/A.swift", line: 42), for: listed)
        // Hlášení samo na disk nesahá — jde tam s příští změnou záložky.
        #expect(tabs.load().tabs.first?.anchor == nil)

        store.openTab(vault)
        #expect(tabs.load().tabs.first?.anchor == DiffScrollAnchor(file: "App/A.swift", line: 42))

        // Zavřená záložka kotvu nemá kde držet, takže se hlášení zahodí.
        store.closeTab(listed)
        store.noteDiffScrollAnchor(DiffScrollAnchor(file: "App/B.swift", line: 1), for: listed)
        #expect(store.diffScrollAnchors[listed] == nil)
    }

    /// `nil` **nemaže**: „zrovna nevím, kde výřez stojí“ (rozsahy se přeměřují) není totéž jako
    /// „do diffu se nekouklo“, a zahodit poslední polohu kvůli jednomu průchodu bez odpovědi by
    /// znamenalo obnovit se na začátek diffu právě po přerovnání okna.
    @Test("Hlášení bez odpovědi kotvu nesmaže")
    func anEmptyReportKeepsTheAnchor() async {
        let (store, _) = await started(list: [summary(listed)])
        store.openTab(listed)
        let anchor = DiffScrollAnchor(file: "App/A.swift", line: 42)

        store.noteDiffScrollAnchor(anchor, for: listed)
        store.noteDiffScrollAnchor(nil, for: listed)

        #expect(store.diffScrollAnchors[listed] == anchor)
    }

    @Test("Bez snímkovacího store se nikam nezapisuje")
    func withoutAStoreNothingIsWritten() async {
        let (store, _) = await started(list: [summary(listed)], withStore: false)

        store.openTab(listed)

        #expect(tabs.load() == .none)
    }

    // MARK: - Obnovení

    @Test("Záložky se vrátí v pořadí, s tabem i s aktivní záložkou")
    func tabsComeBackInOrder() async {
        tabs.save(OpenTabs(
            tabs: [
                OpenTab(pullRequest: listed, tab: .conversation),
                OpenTab(pullRequest: vault, tab: .filesChanged)
            ],
            active: vault
        ))

        let (store, _) = await started(list: [summary(listed)])

        #expect(store.openTabs == [listed, vault])
        #expect(store.activeTab == .pullRequest(vault))
        #expect(store.selection == vault)
        #expect(store.detailTab(for: listed) == .conversation)
        #expect(store.detailTab(for: vault) == .filesChanged)
    }

    /// **Tohle je ta věta, na které issue stojí.** Obnovení nepustí review ani session
    /// a nepřipraví pracovní kopii — dotáhne jediné, a to čtením.
    @Test("Obnovení nespustí žádnou session ani checkout")
    func restoringStartsNothing() async {
        tabs.save(OpenTabs(tabs: [OpenTab(pullRequest: vault, tab: .overview)], active: vault))
        let reviewer = FakeReviewRunner()
        let checkout = FakeRepoCheckout()

        let (store, gateway) = await started(
            // **Prázdné zdroje a zapnutý automat**, tedy stav, ve kterém je otevřená záložka to
            // jediné, co by se dalo spustit. Automat čte `summaries` z tiku, takže se o obnovené
            // záložce nemá kde dozvědět (#4) — a tenhle test je to jediné, co tu větu drží.
            list: [],
            reviewer: reviewer,
            checkout: checkout,
            mode: .automatic
        )
        await settle(store, vault)

        #expect(reviewer.requests.isEmpty)
        #expect(checkout.preparedRepositories.isEmpty)
        #expect(store.reviewPhases.isEmpty)
        // A **nic se neodeslalo**: jediné, co obnovení dělá se sítí, je čtení detailu.
        #expect(gateway.detailRequests == [vault])
    }

    /// Puntík načítání je nový stav záložky (#527): dokud detail nedorazí, nesmí pruh kreslit
    /// stav review z minula.
    @Test("Obnovená záložka bez detailu má puntík načítání")
    func aRestoredTabLoadsFirst() async {
        tabs.save(OpenTabs(tabs: [OpenTab(pullRequest: vault, tab: .overview)], active: vault))
        // Detail se nikdy nedotáhne — tím se stav načítání udrží po celý test.
        let gateway = FakeGitHubGateway(
            always: .success([]),
            detail: .failure(GitHubError.notFound("nikdy"))
        )
        var configuration = Configuration.standard
        configuration.global.sources = [.reviewRequested]
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            checkout: FakeRepoCheckout(),
            openTabsStore: tabs,
            cacheLayout: layout
        )

        // Ještě před `keepFresh()` je pruh prázdný; po obnovení je v něm záložka i s puntíkem.
        #expect(store.openTabs.isEmpty)
        await store.restoreOpenTabs()

        #expect(store.tabContent(for: vault) == .loading)
        #expect(store.tabMark(for: vault) == .loading)
        // Pruh musí umět záložku nakreslit, i když se o PR ví jenom adresa — jinak by v něm
        // chyběla ta, na kterou `activeTab` ukazuje.
        #expect(store.openTabSummaries.map(\.id) == [vault])
    }

    /// PR, který mezitím zmizel z fronty, se vrátí taky — **dočíst ho jde a zavírá ho člověk**
    /// (pravidlo z #67). Fialový puntík je stav *pull requestu*, ne review.
    @Test("Mergnutý PR se obnoví s fialovým puntíkem a nezavře se sám")
    func aMergedPullRequestComesBack() async {
        tabs.save(OpenTabs(tabs: [OpenTab(pullRequest: merged, tab: .overview)], active: merged))

        // V seznamu není (mergnutý PR z `review-requested` vypadl), detail ho hlásí jako mergnutý.
        let (store, _) = await started(
            list: [summary(listed)],
            detail: .success(detail(merged, state: .merged))
        )
        await settle(store, merged)

        #expect(store.openTabs == [merged])
        #expect(store.summary(for: merged)?.state == .merged)
        #expect(store.tabMark(for: merged) == .pullRequest(.merged))
        // A **tik ho nezavře**: záložka je otevřená práce, ne řádek fronty.
        await store.refresh()
        #expect(store.openTabs == [merged])
        #expect(store.activeTab == .pullRequest(merged))
    }

    /// Obnovení běží **před prvním tikem**, takže značka přijaté záložky musí být na místě dřív,
    /// než úklid po tiku začne zahazovat stav PR, které nejsou v seznamu.
    @Test("První tik obnovenou záložku nevyprázdní")
    func theFirstTickDoesNotWipeARestoredTab() async {
        tabs.save(OpenTabs(tabs: [OpenTab(pullRequest: vault, tab: .filesChanged)], active: vault))

        let (store, _) = await started(list: [summary(listed)])
        await settle(store, vault)

        #expect(store.adoptedTabs[vault] == .restored)
        #expect(store.detailStates[vault] != nil)

        await store.refresh()

        #expect(store.openTabs == [vault])
        #expect(store.detailStates[vault] != nil)
        #expect(store.summary(for: vault)?.title == "z detailu")
    }

    /// Pilulka `mimo zdroje` (#531) má přežít restart, kdežto značka `restored` je značka
    /// **tohohle** spuštění — proto se do snímku ukládá jen ta první.
    @Test("Záložka otevřená odkazem si po restartu nechá pilulku, obnovená ji nedostane")
    func onlyLinkedTabsKeepThePill() async {
        tabs.save(OpenTabs(
            tabs: [
                OpenTab(pullRequest: vault, tab: .overview, openedByLink: true),
                OpenTab(pullRequest: merged, tab: .overview, openedByLink: false)
            ],
            active: nil
        ))

        let (store, _) = await started(list: [])

        #expect(store.adoptedTabs[vault] == .link)
        #expect(store.adoptedTabs[merged] == .restored)
        #expect(store.origin(of: vault) == .outsideSources)
        #expect(store.origin(of: merged) == .sources)

        // A ve snímku se to nepřehází: obnovená zůstane obnovenou, ne „otevřenou odkazem“.
        #expect(store.openTabsSnapshot.tabs.map(\.openedByLink) == [true, false])
    }

    /// Snímek může být rozpadlý (ručně editovaný soubor). Aktivní záložka, která v pruhu není,
    /// znamená okno bez jediné zvýrazněné záložky nad prázdnou plochou.
    @Test("Aktivní záložka mimo pruh se ignoruje")
    func anActiveTabOutsideTheStripIsIgnored() async {
        tabs.save(OpenTabs(tabs: [OpenTab(pullRequest: vault, tab: .overview)], active: listed))

        let (store, _) = await started(list: [])

        #expect(store.openTabs == [vault])
        #expect(store.activeTab == .home)
    }

    @Test("Prázdný snímek nic neotevře")
    func anEmptySnapshotOpensNothing() async {
        let (store, gateway) = await started(list: [summary(listed)])

        #expect(store.openTabs.isEmpty)
        #expect(store.activeTab == .home)
        #expect(gateway.detailRequests.isEmpty)
    }

    /// Kotva se má posadit **jednou**, po obnovení — jinak by se výřez vracel na uložené místo
    /// při každém přepnutí do `Změněných souborů`, tedy i po tom, co si člověk odscrolloval jinam.
    @Test("Kotva scrollu se vyzvedne jen jednou")
    func thePendingAnchorIsConsumedOnce() async {
        let anchor = DiffScrollAnchor(file: "App/A.swift", line: 42)
        tabs.save(OpenTabs(
            tabs: [OpenTab(pullRequest: vault, tab: .filesChanged, anchor: anchor)],
            active: vault
        ))

        let (store, _) = await started(list: [])

        #expect(store.pendingScrollAnchors[vault] == anchor)
        #expect(store.takePendingScrollAnchor(for: vault) == anchor)
        #expect(store.takePendingScrollAnchor(for: vault) == nil)
    }

    /// Zavření záložky je jediné, co kotvu smí zahodit: je to stav **otevřené záložky**, ne PR.
    @Test("Zavření záložky kotvu zahodí")
    func closingTheTabDropsTheAnchor() async {
        let anchor = DiffScrollAnchor(file: "App/A.swift", line: 42)
        tabs.save(OpenTabs(
            tabs: [OpenTab(pullRequest: vault, tab: .filesChanged, anchor: anchor)],
            active: vault
        ))

        let (store, _) = await started(list: [])
        store.closeTab(vault)

        #expect(store.pendingScrollAnchors[vault] == nil)
        #expect(store.diffScrollAnchors[vault] == nil)
        #expect(tabs.load() == .none)
    }
}
