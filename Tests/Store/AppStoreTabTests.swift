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
