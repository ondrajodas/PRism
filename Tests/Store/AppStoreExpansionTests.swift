import Foundation
import Testing

@testable import PRism

/// Rozbalování kontextu drží store, ne view — jinak by se stav přelil mezi pull requesty
/// stejně jako u diffu.
@Suite("AppStore — rozbalení kontextu")
@MainActor
struct AppStoreExpansionTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]

    /// Zdroje i sada skillů se berou z konfigurace, takže si ji test postaví.
    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = sources
        return configuration
    }
    private let pr = PRIdentifier("cli/cli#1")!
    private let path = "App/Main.swift"

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/1")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(gateway: gateway, configuration: configuration, time: FakeTimeSource())
    }

    private func waitForContent(_ store: AppStore) async {
        for _ in 0..<200 where store.expansion(of: path, in: pr).content.isEmpty {
            await Task.yield()
        }
    }

    @Test("Rozbalení dotáhne obsah souboru")
    func loadsTheFileContent() async {
        let gateway = FakeGitHubGateway(always: .success([]), files: [.success("první\ndruhý\ntřetí")])
        let store = store(gateway)

        store.reveal(1...2, of: path, in: pr)
        await waitForContent(store)

        let expansion = store.expansion(of: path, in: pr)
        #expect(expansion.content == ["první", "druhý", "třetí"])
        #expect(expansion.revealed.ranges == [1...2])
        #expect(gateway.fileRequests.map(\.path) == [path])
    }

    @Test("Druhé rozbalení téhož souboru se GitHubu neptá")
    func loadsTheContentOnlyOnce() async {
        let gateway = FakeGitHubGateway(always: .success([]), files: [.success("první\ndruhý\ntřetí")])
        let store = store(gateway)

        store.reveal(1...1, of: path, in: pr)
        await waitForContent(store)
        store.reveal(3...3, of: path, in: pr)

        #expect(gateway.fileRequests.count == 1)
        #expect(store.expansion(of: path, in: pr).revealed.ranges == [1...1, 3...3])
    }

    @Test("Selhání je vidět a nezůstane po něm točící se kolečko")
    func showsAFailureInsteadOfSpinningForever() async {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            files: [.failure(GitHubError.notFound("soubor tam není"))]
        )
        let store = store(gateway)

        store.reveal(1...2, of: path, in: pr)
        for _ in 0..<200 where store.expansion(of: path, in: pr).failure == nil {
            await Task.yield()
        }

        let expansion = store.expansion(of: path, in: pr)
        #expect(expansion.failure?.contains("soubor tam není") == true)
        #expect(!expansion.isLoading)
        // Nepovedené načtení nesmí nechat úsek označený za odkrytý — jinak by po něm
        // zůstalo prázdno bez rozbalovacího řádku.
        #expect(expansion.revealed.ranges.isEmpty)
    }

    @Test("Dokud nikdo nic nerozbalil, není co sbalit")
    func hasNothingToCollapseAtFirst() {
        #expect(!store(FakeGitHubGateway(always: .success([]))).hasRevealedLines(in: pr))
    }

    @Test("Sbalení zahodí rozbalené řádky, ale načtený obsah si nechá")
    func collapsingKeepsTheLoadedContent() async {
        let gateway = FakeGitHubGateway(always: .success([]), files: [.success("první\ndruhý\ntřetí")])
        let store = store(gateway)

        store.reveal(1...2, of: path, in: pr)
        await waitForContent(store)
        #expect(store.hasRevealedLines(in: pr))

        store.collapseRevealedLines(in: pr)

        #expect(!store.hasRevealedLines(in: pr))
        // Obsah se drží schválně: druhé rozbalení by jinak zbytečně chodilo po síti.
        #expect(store.expansion(of: path, in: pr).content.count == 3)

        store.reveal(1...1, of: path, in: pr)
        #expect(gateway.fileRequests.count == 1)
    }

    @Test("Sbalení se týká jen svého PR")
    func collapsingLeavesOtherPullRequestsAlone() async {
        let other = PRIdentifier("cli/cli#2")!
        let gateway = FakeGitHubGateway(always: .success([]), files: [.success("první\ndruhý")])
        let store = store(gateway)

        store.reveal(1...1, of: path, in: pr)
        await waitForContent(store)
        store.reveal(1...1, of: path, in: other)
        for _ in 0..<200 where store.expansion(of: path, in: other).content.isEmpty {
            await Task.yield()
        }

        store.collapseRevealedLines(in: pr)

        #expect(!store.hasRevealedLines(in: pr))
        #expect(store.hasRevealedLines(in: other))
    }

    @Test("Rozbalení PR, které zmizelo ze seznamu, se zahodí")
    func forgetsExpansionsOfPullRequestsThatLeftTheList() async {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            files: [.success("první\ndruhý")]
        )
        let store = AppStore(gateway: gateway, configuration: configuration, time: FakeTimeSource(stopAfter: 1))

        store.reveal(1...1, of: path, in: pr)
        await waitForContent(store)
        #expect(!store.expansion(of: path, in: pr).content.isEmpty)

        await store.keepFresh()   // tik, ve kterém to PR není

        #expect(store.expansion(of: path, in: pr).content.isEmpty)
    }
}
