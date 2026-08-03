import Foundation
import Testing

@testable import PRism

/// Konverzaci drží store, ne view — a načítá se při výběru řádku, ne pollingem.
@Suite("AppStore — konverzace")
@MainActor
struct AppStoreConversationTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
    private let pr = PRIdentifier("cli/cli#1")!

    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = sources
        return configuration
    }

    private func summary(_ id: PRIdentifier? = nil, updatedAt: TimeInterval = 100) -> PullRequestSummary {
        let id = id ?? pr
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(gateway: gateway, configuration: configuration, time: FakeTimeSource())
    }

    private func comment(id: String = "c1", author: String = "kolega") -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: "text",
            createdAt: Date(timeIntervalSince1970: 1_000),
            url: URL(string: "https://github.com/cli/cli/pull/1#discussion_\(id)")!
        )
    }

    private func thread(id: String = "t1", line: Int? = 27, resolved: Bool = false) -> ReviewThread {
        ReviewThread(
            id: id,
            path: "Cart.php",
            line: line,
            originalLine: 27,
            side: .right,
            isResolved: resolved,
            isOutdated: line == nil,
            comments: ConversationPage(items: [comment()], total: 1, hasNextPage: false)
        )
    }

    private func conversation(_ threads: [ReviewThread] = [], viewer: String = "ja") -> Conversation {
        Conversation(
            viewer: viewer,
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    private var diffText: String {
        """
        diff --git a/Cart.php b/Cart.php
        --- a/Cart.php
        +++ b/Cart.php
        @@ -25,3 +25,3 @@
         kontext
        -staré
        +nové
         další
        """
    }

    // MARK: - Načtení a cache

    @Test("Výběr PR načte konverzaci")
    func loadsTheConversation() async {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            conversations: [.success(conversation([thread()]))]
        )
        let store = store(gateway)

        await store.loadConversation(for: summary())

        #expect(store.conversation(for: pr)?.threads.items.count == 1)
        #expect(gateway.conversationRequests == [pr])
    }

    /// Přepínání mezi PR je nejčastější pohyb v okně — každé by jinak stálo podproces.
    @Test("Načtená konverzace se drží, dokud se nezmění updatedAt")
    func cachesByUpdatedAt() async {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            conversations: [.success(conversation([thread()]))]
        )
        let store = store(gateway)

        await store.loadConversation(for: summary(updatedAt: 100))
        await store.loadConversation(for: summary(updatedAt: 100))

        #expect(gateway.conversationRequests.count == 1)
    }

    /// Nový komentář změní `updatedAt`, a to je přesně chvíle, kdy se má načíst znovu.
    @Test("Změněné updatedAt konverzaci načte znovu")
    func reloadsAfterUpdate() async {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            conversations: [.success(conversation([thread()])), .success(conversation([]))]
        )
        let store = store(gateway)

        await store.loadConversation(for: summary(updatedAt: 100))
        await store.loadConversation(for: summary(updatedAt: 200))

        #expect(gateway.conversationRequests.count == 2)
        #expect(store.conversation(for: pr)?.threads.items.isEmpty == true)
    }

    /// Kolega odpoví za minutu, ale seznam se obnovuje po minutách — tlačítko je levnější
    /// než čekat na tik.
    @Test("Ruční obnovení načte i při stejném updatedAt")
    func refreshIgnoresTheCache() async {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            conversations: [.success(conversation([thread()])), .success(conversation([]))]
        )
        let store = store(gateway)

        await store.loadConversation(for: summary())
        await store.refreshConversation(for: summary())

        #expect(gateway.conversationRequests.count == 2)
        #expect(store.conversation(for: pr)?.threads.items.isEmpty == true)
    }

    @Test("Selhání je vidět a dá se zkusit znovu")
    func reportsAFailure() async {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            conversations: [
                .failure(GitHubError.network("bez sítě")),
                .success(conversation([thread()])),
            ]
        )
        let store = store(gateway)

        await store.loadConversation(for: summary())
        #expect(store.conversationState(for: pr) == .failed(GitHubError.network("bez sítě").userDescription))

        await store.refreshConversation(for: summary())
        #expect(store.conversation(for: pr)?.threads.items.count == 1)
    }

    // MARK: - Kotvení

    @Test("Zakotví se jen vlákna, jejichž řádek v diffu je")
    func anchorsOnlyThreadsInTheDiff() async {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            diffs: [.success(diffText)],
            conversations: [.success(conversation([
                thread(id: "v-diffu", line: 27),
                thread(id: "zastaralé", line: nil),
                thread(id: "mimo-hunky", line: 900),
            ]))]
        )
        let store = store(gateway)

        await store.loadDiff(for: summary())
        await store.loadConversation(for: summary())

        #expect(store.anchoredThreads(for: pr).map(\.id) == ["v-diffu"])
    }

    /// Dokud diff není, nemá se kde kotvit — ale konverzace se tím nesmí zahodit.
    @Test("Bez diffu se nezakotví nic, konverzace ale zůstane")
    func anchorsNothingWithoutADiff() async {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            conversations: [.success(conversation([thread()]))]
        )
        let store = store(gateway)

        await store.loadConversation(for: summary())

        #expect(store.anchoredThreads(for: pr).isEmpty)
        #expect(store.conversation(for: pr)?.threads.items.count == 1)
    }

    // MARK: - Rozbalení

    @Test("Vyřešené vlákno je sbalené, nevyřešené rozbalené")
    func usesResolutionAsTheDefault() async {
        let gateway = FakeGitHubGateway(always: .success([]))
        let store = store(gateway)

        #expect(store.isThreadExpanded(thread(resolved: false)))
        #expect(!store.isThreadExpanded(thread(resolved: true)))
    }

    @Test("Překliknutí drží a jde vrátit")
    func togglesAndBack() {
        let store = store(FakeGitHubGateway(always: .success([])))
        let resolved = thread(resolved: true)

        store.toggleThread(resolved)
        #expect(store.isThreadExpanded(resolved))

        store.toggleThread(resolved)
        #expect(!store.isThreadExpanded(resolved))
    }

    @Test("Překliknutí jednoho vlákna nesahá na druhé")
    func togglesOneThreadOnly() {
        let store = store(FakeGitHubGateway(always: .success([])))

        store.toggleThread(thread(id: "a", resolved: true))

        #expect(store.isThreadExpanded(thread(id: "a", resolved: true)))
        #expect(!store.isThreadExpanded(thread(id: "b", resolved: true)))
    }

    /// Ruční obnovení nesmí uživateli zahodit, co si zavřel — proto se drží odchylka, ne
    /// seznam rozbalených.
    @Test("Obnovení konverzace překliknutí nezahodí")
    func keepsTheToggleAcrossRefresh() async {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            conversations: [.success(conversation([thread(resolved: true)])), .success(conversation([thread(resolved: true)]))]
        )
        let store = store(gateway)
        await store.loadConversation(for: summary())
        store.toggleThread(thread(resolved: true))

        await store.refreshConversation(for: summary())

        #expect(store.isThreadExpanded(thread(resolved: true)))
    }

    // MARK: - Úklid

    @Test("Konverzace PR, které zmizelo ze seznamu, se zahodí")
    func forgetsConversationsOfVanishedPullRequests() async {
        let other = PRIdentifier("cli/cli#2")!
        let gateway = FakeGitHubGateway(
            [.success([summary(), summary(other)]), .success([summary(other)])],
            conversations: [.success(conversation([thread()]))]
        )
        let store = store(gateway)

        await store.refresh()
        await store.loadConversation(for: summary())
        #expect(store.conversation(for: pr) != nil)

        await store.refresh()

        #expect(store.conversation(for: pr) == nil)
    }

    /// `id` vlákna svoje PR nenese, takže bez úklidu podle zbylých konverzací by množina
    /// překliknutých rostla donekonečna.
    @Test("Překliknutá vlákna zmizelého PR se uklidí")
    func forgetsTogglesOfVanishedPullRequests() async {
        let other = PRIdentifier("cli/cli#2")!
        let gateway = FakeGitHubGateway(
            [.success([summary(), summary(other)]), .success([summary(other)])],
            conversations: [.success(conversation([thread(id: "t1", resolved: true)]))]
        )
        let store = store(gateway)

        await store.refresh()
        await store.loadConversation(for: summary())
        store.toggleThread(thread(id: "t1", resolved: true))
        #expect(store.toggledThreads == ["t1"])

        await store.refresh()

        #expect(store.toggledThreads.isEmpty)
    }
}
