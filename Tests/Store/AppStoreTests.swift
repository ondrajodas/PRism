import Foundation
import Testing

@testable import PRism

@Suite("AppStore")
@MainActor
struct AppStoreTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]

    private func summary(_ identifier: String) -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(gateway: gateway, sources: sources, time: FakeTimeSource())
    }

    @Test("Obnovení se zeptá zdrojů")
    func refreshAsksTheSources() async {
        let gateway = FakeGitHubGateway(always: .success([]))

        await store(gateway).refresh()

        #expect(gateway.queries == sources.map(\.query))
    }

    @Test("Seznam PR se čte z pollingu")
    func pullRequestsComeFromPolling() async {
        let store = store(FakeGitHubGateway(always: .success([summary("cli/cli#1")])))

        await store.refresh()

        #expect(store.pullRequests.map(\.id.description) == ["cli/cli#1"])
    }

    @Test("Než něco doběhne, je stav nenačteno")
    func startsBeforeAnythingHasLoaded() {
        #expect(store(FakeGitHubGateway(always: .success([]))).status == .notStarted)
    }

    @Test("Výběr se drží mezi překreslením")
    func keepsSelection() {
        // Výběr žije ve store, ne ve view — jinak by ho každé přestavění seznamu zahodilo.
        let store = store(FakeGitHubGateway(always: .success([])))

        store.selection = PRIdentifier("cli/cli#1")

        #expect(store.selection == PRIdentifier("cli/cli#1"))
    }
}

extension AppStoreTests {
    @Test("Po každém tiku se pustí úklid cache")
    func tidiesTheCacheAfterEveryTick() async throws {
        // Zavřené PR se poznají jen tím, že v odpovědi chybí — úklid proto musí běžet
        // i po tiku, který nenašel nic.
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)
        let clone = layout.bareClone(for: RepoID(owner: "cli", name: "cli"))
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)

        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            sources: sources,
            time: FakeTimeSource(stopAfter: 1),
            eviction: CacheEviction(layout: layout, budget: .max)
        )
        await store.keepFresh()

        #expect(!FileManager.default.fileExists(atPath: clone.path(percentEncoded: false)))
    }
}

extension AppStoreTests {
    @Test("Selhaný tik cache neuklidí")
    func aFailedTickNeverTouchesTheCache() async throws {
        // Po výpadku sítě zůstane seznam beze změny — a po startu je prázdný. Uklízet
        // po takovém tiku by znamenalo smazat celou cache kvůli chvíli bez sítě.
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)
        let clone = layout.bareClone(for: RepoID(owner: "cli", name: "cli"))
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)

        let store = AppStore(
            gateway: FakeGitHubGateway(always: .failure(GitHubError.network("bez sítě"))),
            sources: sources,
            time: FakeTimeSource(stopAfter: 1),
            eviction: CacheEviction(layout: layout, budget: .max)
        )
        await store.keepFresh()

        #expect(FileManager.default.fileExists(atPath: clone.path(percentEncoded: false)))
    }
}
