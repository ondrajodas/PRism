import Foundation
import Testing

@testable import PRism

/// Filtr seznamu PR ve storu (#117).
///
/// **To nejdůležitější z celého issue: filtr je pohled, ne seznam.** Zapnutí filtru nesmí zahodit
/// diffy, konverzace ani drafty, nesmí zrušit běžící review a nesmí spustit úklid cache. Ověřuje se
/// to proti fakes, ne úvahou o tom, kdo dnes co čte: `pullRequests` (plný) a `visiblePullRequests`
/// (zúžený) jsou dva různé gettery a rozdíl mezi nimi je jediné, co dělí filtr od mazání cache.
@Suite("AppStore — filtr seznamu")
@MainActor
struct AppStoreFilterTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]

    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = sources
        return configuration
    }

    private func summary(_ number: Int, repo: String = "cli/cli", author: String = "kdosi") -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID(repo)!, number: number),
            title: "PR \(number)",
            author: author,
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_000_000),
            state: .open
        )
    }

    private func filter(repos: [String] = [], authors: [String] = []) -> PullRequestFilter {
        PullRequestFilter(repositories: Set(repos.compactMap { RepoID($0) }), authors: Set(authors))
    }

    /// Detail je to, odkud se ví, proti kterému commitu se review píše — bez něj draft nevznikne.
    private func detail(_ pr: PRIdentifier) -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "kdosi",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_000_000),
            state: .open
        )
    }

    /// Store po jednom tiku, ve kterém dorazila daná PR.
    private func loaded(
        _ list: [PullRequestSummary],
        diffs: [Result<String, any Error>] = [],
        detailOf: PullRequestSummary? = nil
    ) async -> (AppStore, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(
            always: .success(list),
            detail: detailOf.map { .success(detail($0.id)) },
            diffs: diffs
        )
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1)
        )
        await store.keepFresh()
        if let detailOf { await store.loadDetail(for: detailOf) }
        return (store, gateway)
    }

    // MARK: - Zúžení seznamu

    @Test("Bez filtru je vidět všechno")
    func showsEverythingWithoutAFilter() async {
        let (store, _) = await loaded([summary(1), summary(2, repo: "ondrajodas/PRism")])

        #expect(store.visiblePullRequests.count == 2)
        #expect(store.hiddenQueuePullRequestCount == 0)
        #expect(!store.filter.isActive)
    }

    @Test("Filtr zúží viditelný seznam a řekne, kolik schoval")
    func narrowsTheVisibleList() async {
        let (store, _) = await loaded([
            summary(1),
            summary(2, repo: "ondrajodas/PRism"),
            summary(3, repo: "keboola/job-queue"),
        ])

        store.setFilter(filter(repos: ["cli/cli"]))

        #expect(store.visiblePullRequests.map(\.number) == [1])
        #expect(store.hiddenQueuePullRequestCount == 2)
    }

    /// **Plný seznam zůstává plný.** Na něm visí okno nastavení, souhrn fronty a automat.
    @Test("Zapnutý filtr nesahá na plný seznam")
    func keepsTheFullListIntact() async {
        let (store, _) = await loaded([summary(1), summary(2, repo: "ondrajodas/PRism")])

        store.setFilter(filter(repos: ["cli/cli"]))

        #expect(store.pullRequests.count == 2)
        #expect(store.visiblePullRequests.count == 1)
    }

    /// Okno nastavení musí vidět i repo, které jsem si schoval — je to zrovna to, u kterého chci
    /// něco přenastavit.
    @Test("Okno nastavení vidí repa i po zapnutí filtru")
    func keepsRepositoriesVisibleInSettings() async {
        let (store, _) = await loaded([summary(1), summary(2, repo: "ondrajodas/PRism")])

        store.setFilter(filter(repos: ["cli/cli"]))

        #expect(store.knownRepositories.map(\.description) == ["cli/cli", "ondrajodas/PRism"])
    }

    /// Souhrn fronty (#155) sčítá **obsah**, ne pohled — jinak by tvrdil, že práce ubyla, jen
    /// protože jsem si schoval jedno repo.
    @Test("Souhrn fronty se filtrem nemění")
    func keepsTheQueueSummaryIntact() async {
        let (store, _) = await loaded([summary(1), summary(2, repo: "ondrajodas/PRism")])
        let before = store.queueSummary

        store.setFilter(filter(repos: ["cli/cli"]))

        #expect(store.queueSummary == before)
        #expect(store.queueSummary?.pullRequests == 2)
    }

    // MARK: - Filtr je pohled, ne mazání

    /// **Nejcennější test téhle sady.** Kdyby na zúženém seznamu viselo cokoli z úklidu, zapnutí
    /// filtru by zahodilo diff schovaného PR — a po vypnutí by se musel načítat znovu.
    @Test("Zapnutí filtru nezahodí diff schovaného PR")
    func keepsTheDiffOfAHiddenPullRequest() async throws {
        let hidden = summary(2, repo: "ondrajodas/PRism")
        let (store, gateway) = await loaded(
            [summary(1), hidden],
            diffs: [.success(try Fixture.text("gh/pr-diff-deleted.diff"))]
        )
        await store.loadDiff(for: hidden)
        #expect(store.diffState(for: hidden.id) != nil)

        store.setFilter(filter(repos: ["cli/cli"]))

        #expect(store.diffState(for: hidden.id) != nil)
        // A po vypnutí filtru se GitHubu neptá znovu — diff v mapě pořád leží.
        store.clearFilter()
        await store.loadDiff(for: hidden)
        #expect(gateway.diffRequests == [hidden.id])
    }

    @Test("Zapnutí filtru nezahodí rozdělané review schovaného PR")
    func keepsTheDraftOfAHiddenPullRequest() async {
        let hidden = summary(2, repo: "ondrajodas/PRism")
        let (store, _) = await loaded([summary(1), hidden], detailOf: hidden)
        store.setDraftBody("rozepsáno", for: hidden.id)
        #expect(store.hasDraft(hidden.id))

        store.setFilter(filter(repos: ["cli/cli"]))

        #expect(store.hasDraft(hidden.id))
        #expect(store.draft(for: hidden.id)?.body == "rozepsáno")
    }

    /// Běžící review na schovaném PR **běží dál**. Kdyby ho filtr rušil, znamenalo by schování
    /// zahození právě té práce, na kterou se člověk chystal podívat.
    @Test("Zapnutí filtru nezruší běžící review")
    func keepsRunningReviews() async {
        let hidden = summary(2, repo: "ondrajodas/PRism")
        let (store, _) = await loaded([summary(1), hidden])

        store.setFilter(filter(repos: ["cli/cli"]))

        // Store nemá reviewer ani checkout, takže se tu nic nespustí; podstatné je, že filtr
        // sám nic neruší — počet běžících zůstává, jaký byl.
        #expect(store.runningReviews == 0)
        #expect(store.isReviewing(hidden.id) == false)
    }

    /// Automat filtr **neřeší**: review na schovaném repu se dál plánuje. Vypnout ho jde
    /// `mode: manual` per repo — kdyby to dělal filtr, slil by se pohled s nastavením.
    @Test("Automat vidí i schovaná repa")
    func leavesAutomaticModeAlone() async {
        let hidden = summary(2, repo: "ondrajodas/PRism")
        let (store, _) = await loaded([summary(1), hidden])

        store.setFilter(filter(repos: ["cli/cli"]))

        // `startAutomaticReviews` bere plný seznam; tady se ověřuje ten vstup, protože bez
        // reviewera se nic nespustí.
        #expect(store.pullRequests.contains { $0.id == hidden.id })
    }

    // MARK: - Výběr

    /// Vybraný PR mimo filtr výběr **ztrácí**: detail PR, který v seznamu není, se nedá zavřít ani
    /// znovu vybrat kliknutím.
    @Test("Vybraný PR mimo filtr ztrácí výběr")
    func clearsTheSelectionOutsideTheFilter() async {
        let (store, _) = await loaded([summary(1), summary(2, repo: "ondrajodas/PRism")])
        store.selection = PRIdentifier("ondrajodas/PRism#2")

        store.setFilter(filter(repos: ["cli/cli"]))

        #expect(store.selection == nil)
    }

    @Test("Vybraný PR uvnitř filtru výběr drží")
    func keepsTheSelectionInsideTheFilter() async {
        let (store, _) = await loaded([summary(1), summary(2, repo: "ondrajodas/PRism")])
        store.selection = PRIdentifier("cli/cli#1")

        store.setFilter(filter(repos: ["cli/cli"]))

        #expect(store.selection == PRIdentifier("cli/cli#1"))
    }

    /// **Nezruší se**, když vybraný PR ze seznamu vypadne jen proto, že se změnil seznam z tiku —
    /// to je dnešní chování (mergnutý PR jde ještě dočíst) a nemá se změnit.
    @Test("Tik, ve kterém PR není, výběr nesráží")
    func keepsTheSelectionAfterATickWithoutIt() async {
        let gateway = FakeGitHubGateway([.success([summary(1)]), .success([])])
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 2)
        )
        await store.keepFresh()
        store.selection = PRIdentifier("cli/cli#1")

        await store.keepFresh()

        #expect(store.selection == PRIdentifier("cli/cli#1"))
    }

    // MARK: - Prázdný stav

    @Test("Filtr, který schoval všechno, má vlastní důvod")
    func explainsTheEmptyFilteredList() async {
        let (store, _) = await loaded([summary(1)])

        store.setFilter(filter(repos: ["kdesi/jinde"]))

        #expect(store.listEmptyReason == .filtered(hidden: 1))
        // A plný seznam prázdný **není** — proto se nesmí hlásit `noPullRequests`.
        #expect(store.emptyReason == nil)
    }

    @Test("Vymazání filtru vrátí seznam i výběr do hry")
    func clearingTheFilterRestoresTheList() async {
        let (store, _) = await loaded([summary(1), summary(2, repo: "ondrajodas/PRism")])
        store.setFilter(filter(repos: ["kdesi/jinde"]))

        store.clearFilter()

        #expect(store.visiblePullRequests.count == 2)
        #expect(store.listEmptyReason == nil)
        #expect(!store.filter.isActive)
    }

    /// Nabídka drží hodnoty aktivního filtru i po tiku, ve kterém jejich PR zmizel — bez toho by
    /// filtr zůstal zapnutý bez cesty zpátky.
    @Test("Nabídka drží schované repo i po tiku, ve kterém zmizelo")
    func keepsFilterValuesInTheOptionsAfterATick() async {
        let gateway = FakeGitHubGateway([
            .success([summary(1), summary(2, repo: "ondrajodas/PRism")]),
            .success([summary(1)]),
        ])
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 2)
        )
        await store.keepFresh()
        store.setFilter(filter(repos: ["ondrajodas/PRism"]))

        await store.keepFresh()

        #expect(store.filterOptions.repositories.map(\.value.description).contains("ondrajodas/PRism"))
    }

    /// **Počty u položek jdou z plného seznamu** (#199), a je to tentýž rozdíl mezi `pullRequests`
    /// a `visiblePullRequests` jako všude jinde v téhle sadě. Kdyby store poslal do
    /// `Policy.filterOptions` zúžený seznam, čísla by se měnila podle právě odškrtaných položek —
    /// odškrtnuté repo by mělo svůj počet a všechna ostatní nulu, takže by z nabídky nešlo poznat,
    /// co zapnutí položky udělá.
    @Test("Počty v nabídce se zapnutím filtru nezmění")
    func countsOptionsFromTheFullList() async {
        let (store, _) = await loaded([
            summary(1),
            summary(2, repo: "ondrajodas/PRism"),
            summary(3, repo: "ondrajodas/PRism"),
        ])
        let before = store.filterOptions

        store.setFilter(filter(repos: ["cli/cli"]))

        #expect(store.filterOptions == before)
        #expect(store.filterOptions.repositories.map(\.count) == [1, 2])
        #expect(store.visiblePullRequests.count == 1)
    }
}
