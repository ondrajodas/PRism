import Foundation
import Testing

@testable import PRism

/// Záložka nad PR **mimo zdroje** (#531).
///
/// Půlka sady tvrdí, že se něco **nestalo**: PR otevřený odkazem se nesmí objevit ve frontě,
/// na kartách, v odznaku ani v automatu — frontu definují zdroje (#4). Rozbilo by se to potichu,
/// protože jediné, co by se stalo, je o jedničku větší číslo u položky railu.
///
/// Druhá půlka je o tom, co naopak **přežít musí**: tik, ve kterém PR v seznamu není, je u téhle
/// záložky normální stav, ne důvod ji vyprázdnit. Do #531 by ji `forget(whatIsNotIn:)` na prvním
/// tiku připravil o detail, diff i konverzaci.
@Suite("AppStore — PR mimo zdroje (#531)")
@MainActor
struct AppStoreExternalTabTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let vault = PRIdentifier("keboola/vault#85")!
    private let listed = PRIdentifier("cli/cli#1")!

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func summary(_ id: PRIdentifier, author: String = "odinuv") -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "titulek \(id.number)",
            author: author,
            url: Policy.githubURL(of: id),
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func detail(_ id: PRIdentifier, title: String = "z detailu") -> PullRequest {
        PullRequest(
            id: id,
            title: title,
            author: "odinuv",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            headRef: "feat/ttl",
            baseRef: "main",
            url: Policy.githubURL(of: id),
            updatedAt: Date(timeIntervalSince1970: 300),
            state: .open
        )
    }

    /// Store po jednom tiku. Jeden zdroj, ne výchozí dva — fake gateway spotřebovává odpovědi
    /// po dotazech, takže by druhý posunul celou sekvenci (tatáž úvaha jako jinde ve `Tests/Store`).
    private func loaded(
        _ list: [PullRequestSummary],
        gateway: FakeGitHubGateway? = nil,
        reviewer: FakeReviewRunner = FakeReviewRunner(),
        mode: ReviewMode = .manual
    ) async -> (AppStore, FakeGitHubGateway) {
        var configuration = Configuration.standard
        configuration.global.sources = [.reviewRequested]
        configuration.global.mode = mode
        let gateway = gateway
            ?? FakeGitHubGateway(always: .success(list), detail: .success(detail(vault)))
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            autoRuns: AutoRunLedger(layout: layout, time: FakeTimeSource())
        )
        await store.keepFresh()
        return (store, gateway)
    }

    /// Počká, až doběhne dotažení detailu, které `openPullRequest` rozjelo.
    private func settle(_ store: AppStore) async {
        await waitUntil("detail dorazí") { store.detailStates[vault] != .loading }
    }

    // MARK: - Otevření

    @Test("PR mimo zdroje se otevře jako záložka a dotáhne se jeho detail")
    func opensATabForAPullRequestOutsideSources() async {
        let (store, gateway) = await loaded([summary(listed)])

        store.openPullRequest(vault)
        // Záložka je v pruhu **hned**, ještě než detail dorazí: kliknutí, po kterém se sekundu
        // neděje nic, je k nerozeznání od kliknutí, které nic neudělalo.
        #expect(store.openTabs == [vault])
        #expect(store.activeTab == .pullRequest(vault))
        #expect(store.openTabSummaries.map(\.id) == [vault])
        #expect(store.tabContent(for: vault) == .loading)

        await settle(store)

        #expect(gateway.detailRequests == [vault])
        #expect(store.summary(for: vault)?.title == "z detailu")
        #expect(store.tabContent(for: vault) == .detail(store.summary(for: vault)!))
        #expect(store.origin(of: vault) == .outsideSources)
    }

    @Test("PR ze seznamu se otevře beze změny, bez jediného dotazu navíc")
    func aListedPullRequestOpensWithoutAsking() async {
        let (store, gateway) = await loaded([summary(listed)])
        let details = gateway.detailRequests.count

        store.openPullRequest(listed)

        #expect(store.openTabs == [listed])
        #expect(store.adoptedTabs.isEmpty)
        #expect(store.origin(of: listed) == .sources)
        #expect(gateway.detailRequests.count == details)
    }

    @Test("Nepovedené dotažení se přizná a dá se zopakovat")
    func aFailedFetchIsVisibleAndRetryable() async {
        let gateway = FakeGitHubGateway(
            always: .success([summary(listed)]),
            detail: .failure(GitHubError.notFound("HTTP 404"))
        )
        let (store, _) = await loaded([summary(listed)], gateway: gateway)

        store.openPullRequest(vault)
        await settle(store)

        guard case .failed(let reason) = store.tabContent(for: vault) else {
            Issue.record("čekal jsem poruchu, přišlo \(store.tabContent(for: vault))")
            return
        }
        #expect(reason.contains("HTTP 404"))
        // Záložka zůstává otevřená, takže se dá zavřít i zkusit znovu.
        #expect(store.openTabs == [vault])

        gateway.detailFromNowOn = .success(detail(vault))
        await store.loadExternalDetail(of: vault)

        #expect(store.summary(for: vault) != nil)
    }

    // MARK: - Co se nestalo

    /// **Nejcennější test sady.** Frontu definují zdroje: PR otevřený odkazem není v seznamu,
    /// takže se nemá kde objevit — ani v odznaku, ani na desce, ani v souhrnu.
    @Test("PR mimo zdroje není ve frontě, na desce ani v odznaku")
    func staysOutOfTheQueue() async {
        let (store, _) = await loaded([summary(listed)])
        let badge = store.railQueueCount
        let board = store.board

        store.openPullRequest(vault)
        await settle(store)

        #expect(store.pullRequests.map(\.id) == [listed])
        #expect(store.visiblePullRequests.map(\.id) == [listed])
        #expect(store.queuePullRequests.map(\.id) == [listed])
        #expect(store.railQueueCount == badge)
        #expect(store.board == board)
    }

    @Test("Automat na PR mimo zdroje nesáhne")
    func theAutomaticModeIgnoresIt() async {
        let reviewer = FakeReviewRunner()
        // Automatický režim globálně, takže by se pustil na **cokoli**, co plánovač uvidí.
        let (store, _) = await loaded([summary(listed)], reviewer: reviewer, mode: .automatic)

        store.openPullRequest(vault)
        await settle(store)
        await store.refresh()
        await waitUntil("tik doběhne") { store.busyRepositories.isEmpty }

        #expect(reviewer.requests.map(\.key.pullRequest) == [listed])
    }

    // MARK: - Tik pollingu

    @Test("Záložka mimo zdroje přežije tik, ve kterém PR v seznamu není")
    func theTabSurvivesAPollTick() async {
        let (store, _) = await loaded([summary(listed)])
        store.openPullRequest(vault)
        await settle(store)
        let opened = store.summary(for: vault)

        // Tik, ve kterém je jen PR ze zdrojů — přesně ten, který do #531 záložku vyprázdnil.
        await store.refresh()

        #expect(store.summary(for: vault) == opened)
        #expect(store.tabContent(for: vault) == .detail(opened!))
        #expect(store.detailStates[vault] != nil)
        #expect(store.openTabSummaries.map(\.id) == [vault])
        // A pořád to není fronta.
        #expect(store.queuePullRequests.map(\.id) == [listed])
    }

    /// Dvě `↵` na řádku `Odkaz` (nebo dvakrát otevřený `prism://`) jsou dva pokusy o totéž —
    /// a bez `.loading` v podmínce z nich byly **dva `gh pr view`** a dva zápisy do jednoho stavu.
    /// Nález Copilota na PR #535.
    @Test("Druhé otevření během načítání se neptá podruhé")
    func openingTwiceWhileLoadingAsksOnce() async {
        let (store, gateway) = await loaded([summary(listed)])

        store.openPullRequest(vault)
        store.openPullRequest(vault)
        store.openPullRequest(vault)
        await settle(store)

        #expect(gateway.detailRequests == [vault])
        #expect(store.openTabs == [vault])
    }

    /// Zavření uprostřed načítání nesmí v mapě nechat `.loading`: `openPullRequest` ho bere jako
    /// „někdo se právě ptá“, takže by znovuotevření uvízlo na obrazovce načítání navždycky.
    @Test("Zavření uprostřed načítání nechá záložku znovu otevřít")
    func closingWhileLoadingLeavesNoStaleState() async {
        let (store, gateway) = await loaded([summary(listed)])
        store.openPullRequest(vault)
        store.closeTab(vault)
        await waitUntil("dotažení dojede") { store.detailStates[vault] != .loading }

        #expect(store.detailStates[vault] == nil)

        store.openPullRequest(vault)
        await settle(store)

        #expect(store.summary(for: vault) != nil)
        #expect(gateway.detailRequests == [vault, vault])
    }

    /// Znovuotevření nad detailem, který tik ještě neuklidil, se **neptá znovu** — a hlavně
    /// záložku nevrátí na obrazovku načítání nad daty, která už jsou v ruce.
    @Test("Znovuotevření záložky se neptá, dokud je detail v paměti")
    func reopeningDoesNotAskAgain() async {
        let (store, gateway) = await loaded([summary(listed)])
        store.openPullRequest(vault)
        await settle(store)
        let details = gateway.detailRequests.count
        store.closeTab(vault)

        store.openPullRequest(vault)

        #expect(store.tabContent(for: vault) == .detail(store.summary(for: vault)!))
        #expect(gateway.detailRequests.count == details)
    }

    @Test("Zavřená záložka mimo zdroje se z paměti uklidí")
    func closingTheTabForgetsIt() async {
        let (store, _) = await loaded([summary(listed)])
        store.openPullRequest(vault)
        await settle(store)

        store.closeTab(vault)
        #expect(store.adoptedTabs.isEmpty)
        #expect(store.summary(for: vault) == nil)

        // Značka je jediné, co detail u tiku drželo — po zavření ho tedy úklid zahodí.
        await store.refresh()
        #expect(store.detailStates[vault] == nil)
    }

    /// Úklid v paměti, eviction na disku a mazání uložených nálezů musí znát **tutéž** množinu:
    /// jinak zbude po otevřené záložce klon bez záznamu, nebo záznam bez klonu.
    @Test("Množina, kterou tik neuklízí, nese seznam i záložky mimo zdroje")
    func whatTheTickKeeps() async {
        let (store, _) = await loaded([summary(listed)])
        store.openPullRequest(vault)

        #expect(store.pullRequestsInPlay(besides: [summary(listed)]) == [listed, vault].sorted())
    }

    // MARK: - Paleta

    @Test("Vložený odkaz dá skupinu Odkaz, a je první")
    func theLinkGroupComesFirst() async {
        let (store, _) = await loaded([summary(listed)])

        let sections = store.paletteSections(for: "https://github.com/keboola/vault/pull/85")

        #expect(sections.first?.group == .link)
        #expect(sections.first?.hits.map(\.item.title) == ["Otevřít keboola/vault#85"])
        #expect(sections.first?.hits.first?.item.subtitle == "není ve zdrojích")
    }

    @Test("Odkaz na PR ze zdrojů to řekne")
    func theLinkKnowsAListedPullRequest() async {
        let (store, _) = await loaded([summary(listed)])

        let sections = store.paletteSections(for: Policy.githubURL(of: listed).absoluteString)

        #expect(sections.first?.hits.first?.item.subtitle == "je ve tvých zdrojích")
    }

    @Test("Běžné hledání skupinu Odkaz nedostane")
    func anOrdinaryQueryHasNoLinkGroup() async {
        let (store, _) = await loaded([summary(listed)])

        #expect(store.paletteSections(for: "titulek").allSatisfy { $0.group != .link })
        #expect(store.paletteSections(for: "").allSatisfy { $0.group != .link })
    }

    /// Skládání katalogu se nesmí nikoho ptát — to je pravidlo palety od #184. Odkaz na tom nic
    /// nemění: PR se dotáhne teprve po `↵`, ne při psaní.
    @Test("Psaní odkazu se nikoho neptá")
    func typingALinkAsksNobody() async {
        let (store, gateway) = await loaded([summary(listed)])
        let details = gateway.detailRequests.count

        for prefix in ["h", "https://github.com/keboola", "https://github.com/keboola/vault/pull/85"] {
            _ = store.paletteSections(for: prefix)
        }

        #expect(gateway.detailRequests.count == details)
    }

    @Test("Enter na řádku Odkaz otevře záložku")
    func revealingTheLinkOpensATab() async {
        let (store, _) = await loaded([summary(listed)])
        let link = store.paletteLink(for: "https://github.com/keboola/vault/pull/85")

        store.reveal(link!.target)
        await settle(store)

        #expect(store.openTabs == [vault])
        #expect(store.origin(of: vault) == .outsideSources)
    }
}
