import Foundation
import Testing

@testable import PRism

/// Kdo se dívá a čí jsou PR v seznamu (#330).
@Suite("AppStore — kdo se dívá (#330)")
@MainActor
struct AppStoreOwnershipTests {
    private func summary(author: String, _ identifier: String = "cli/cli#1") -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(_ gateway: FakeGitHubGateway, ownLogins: [String] = []) -> AppStore {
        var configuration = Configuration.standard
        configuration.global.ownLogins = ownLogins
        return AppStore(gateway: gateway, configuration: configuration, time: FakeTimeSource())
    }

    // MARK: - Než login dorazí

    /// **Tohle je ten test, který tvrdí, že se něco nestalo**: dokud login není načtený, nesmí být
    /// nic „moje“. Obrácené výchozí chování by na okamžik po spuštění přehodilo celý seznam
    /// a fronta cizích PR by zmizela.
    @Test("Než se login načte, je všechno cizí")
    func everythingIsTheirsUntilTheViewerArrives() {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.viewer = "ondrajodas"
        let store = store(gateway)

        // Store existuje, ale `keepFresh()` ještě neproběhl.
        #expect(store.viewer.isEmpty)
        #expect(store.ownLogins.isEmpty)
        #expect(store.ownership(of: summary(author: "ondrajodas")) == .theirs)
        #expect(gateway.viewerRequests == 0)
    }

    /// Když se login zjistit nepovede, zůstává „nevím“ — a to je pořád `.theirs`, ne `.mine`.
    @Test("Selhání dotazu nedělá z cizích PR moje")
    func aFailedViewerLookupNeverClaimsOwnership() async {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.viewer = "ondrajodas"
        gateway.viewerFailure = GitHubError.network("bez sítě")
        let store = AppStore(
            gateway: gateway,
            configuration: Configuration.standard,
            time: FakeTimeSource(stopAfter: 1)
        )

        await store.keepFresh()

        #expect(gateway.viewerRequests == 1)
        #expect(store.viewer.isEmpty)
        #expect(store.ownership(of: summary(author: "ondrajodas")) == .theirs)
    }

    // MARK: - Se známým loginem

    @Test("Login se dotáhne při startu a rozřadí seznam")
    func loadsTheViewerAtStartUp() async {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.viewer = "OndraJodas"
        let store = store(gateway)

        await store.loadViewer()

        // Drží se tak, jak ho `gh` vrátil; na velikost písmen se neptá porovnání, ne uložení.
        #expect(store.viewer == "OndraJodas")
        #expect(store.ownership(of: summary(author: "ondrajodas")) == .mine)
        #expect(store.ownership(of: summary(author: "kolega")) == .theirs)
    }

    /// Není to údaj o PR, takže na tik pollingu nepatří: tři tiky, jeden dotaz.
    @Test("Login se tahá jednou za spuštění, ne na každý tik")
    func asksForTheViewerOnlyOnce() async {
        let gateway = FakeGitHubGateway(always: .success([summary(author: "kolega")]))
        gateway.viewer = "ondrajodas"
        let store = AppStore(
            gateway: gateway,
            configuration: Configuration.standard,
            time: FakeTimeSource(stopAfter: 3)
        )

        await store.keepFresh()

        #expect(gateway.viewerRequests == 1)
        #expect(store.viewer == "ondrajodas")
    }

    /// Loginy z konfigurace se k viewerovi **přidávají** — na tom stojí PR agenta s vlastním účtem.
    @Test("Loginy z konfigurace se přidají k viewerovi")
    func configuredLoginsJoinTheViewer() async {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.viewer = "ondrajodas"
        let store = store(gateway, ownLogins: ["github-actions[bot]", "  "])

        await store.loadViewer()

        #expect(store.ownLogins == ["ondrajodas", "github-actions[bot]"])
        #expect(store.ownership(of: summary(author: "github-actions[bot]")) == .mine)
    }

    // MARK: - Zdroj vlastních PR

    @Test("Výchozí konfigurace vlastní PR sleduje, uložená bez toho zdroje ne")
    func knowsWhetherOwnPullRequestsAreTracked() {
        let gateway = FakeGitHubGateway(always: .success([]))
        #expect(store(gateway).tracksOwnPullRequests)

        var configuration = Configuration.standard
        configuration.global.sources = [.reviewRequested]
        let withoutOwnSource = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource()
        )
        #expect(!withoutOwnSource.tracksOwnPullRequests)
    }
}
