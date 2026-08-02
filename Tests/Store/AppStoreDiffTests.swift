import Foundation
import Testing

@testable import PRism

/// Diff drží store, ne view: `PullRequestDetailView` si SwiftUI mezi PR ponechá, takže
/// vlastní `@State` by přetekl z jednoho pull requestu na druhý.
@Suite("AppStore — diff")
@MainActor
struct AppStoreDiffTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
    private let pr = PRIdentifier("cli/cli#1")!

    private func summary(updatedAt: TimeInterval = 100) -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/1")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(gateway: gateway, sources: sources, time: FakeTimeSource())
    }

    @Test("Výběr PR načte diff")
    func loadsTheDiff() async throws {
        let text = try Fixture.text("gh/pr-diff-deleted.diff")
        let gateway = FakeGitHubGateway(always: .success([]), diffs: [.success(text)])
        let store = store(gateway)

        await store.loadDiff(for: summary())

        guard case .loaded(let diff, _) = store.diffState(for: pr) else {
            Issue.record("Čekal jsem načtený diff, přišlo \(String(describing: store.diffState(for: pr)))")
            return
        }
        #expect(diff.files.count == 1)
        #expect(gateway.diffRequests == [pr])
    }

    @Test("Načtený diff se drží — druhý výběr téhož PR se GitHubu neptá")
    func keepsTheLoadedDiff() async {
        // Přepínání mezi PR je nejčastější pohyb v okně; každé by jinak stálo podproces
        // a kolo po síti.
        let gateway = FakeGitHubGateway(always: .success([]), diffs: [.success("")])
        let store = store(gateway)

        await store.loadDiff(for: summary())
        await store.loadDiff(for: summary())

        #expect(gateway.diffRequests.count == 1)
    }

    @Test("Nový commit diff načte znovu")
    func reloadsAfterAnUpdate() async {
        // `updatedAt` je jediné, co seznam o čerstvosti ví. Ukázat starý diff k novému
        // commitu je dražší chyba než načíst zbytečně.
        let gateway = FakeGitHubGateway(always: .success([]), diffs: [.success("")])
        let store = store(gateway)

        await store.loadDiff(for: summary(updatedAt: 100))
        await store.loadDiff(for: summary(updatedAt: 200))

        #expect(gateway.diffRequests.count == 2)
    }

    @Test("Selhání je vidět a jde zkusit znovu")
    func showsFailureAndRetries() async {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            diffs: [.failure(GitHubError.network("bez sítě")), .success("")]
        )
        let store = store(gateway)

        await store.loadDiff(for: summary())

        guard case .failed(let detail) = store.diffState(for: pr) else {
            Issue.record("Čekal jsem selhání, přišlo \(String(describing: store.diffState(for: pr)))")
            return
        }
        // Text od `gh` musí projít až do UI — z něj se pozná, co se stalo.
        #expect(detail.contains("bez sítě"))

        // Selhaný diff se necachuje — opakování je totéž volání, ne zvláštní cesta.
        await store.loadDiff(for: summary())

        #expect(gateway.diffRequests.count == 2)
        if case .loaded = store.diffState(for: pr) {} else {
            Issue.record("Po opakování jsem čekal načtený diff")
        }
    }

    @Test("Diff PR, které zmizelo ze seznamu, se zahodí")
    func forgetsTheDiffOfAPullRequestThatLeftTheList() async {
        // Diff velkého PR jsou megabajty; držet je pro PR, o která už není zájem, znamená
        // paměť, která jen roste.
        let gateway = FakeGitHubGateway(
            always: .success([]),
            diffs: [.success("")]
        )
        let store = AppStore(
            gateway: gateway,
            sources: sources,
            time: FakeTimeSource(stopAfter: 1)
        )

        await store.loadDiff(for: summary())
        #expect(store.diffState(for: pr) != nil)

        await store.keepFresh()   // tik, ve kterém to PR není

        #expect(store.diffState(for: pr) == nil)
    }
}
