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
