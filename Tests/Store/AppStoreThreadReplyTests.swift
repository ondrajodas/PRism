import Foundation
import Testing

@testable import PRism

/// Odpovídání do vláken, jak ho skládá store (#73).
///
/// **Nic neodchází na GitHub**: `gh` je podstrčený shell skript v dočasné složce, který vypíše
/// připravenou odpověď. Fake publisher by se sem podstrčit nedal — `AppStore` si ho podle tvrdé
/// podmínky č. 1 nesmí držet ani jako továrnu, takže se testuje celá cesta včetně čtení výstupu.
/// Skript navíc zapisuje, kolikrát byl spuštěn, což je jediný způsob, jak ověřit, že se
/// **nevolalo nic**.
@Suite("AppStore — odpovídání do vláken")
@MainActor
struct AppStoreThreadReplyTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier("ondrajodas/prism-review-sandbox#3")!
    private let threadID = "PRRT_kwDOTrIEts6WHlSg"
    private let calls: URL

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        calls = directory.url.appending(path: "gh-calls.log")
    }

    // MARK: - Prostředí testu

    private var publishing: Configuration {
        var configuration = Configuration.standard
        configuration.setRepository(RepositoryConfig(allowsPublishing: true), for: pr.repo)
        return configuration
    }

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func detail() -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func thread(isResolved: Bool = false) -> ReviewThread {
        ReviewThread(
            id: threadID,
            path: "src/Cart.php",
            line: 5,
            originalLine: 5,
            side: .right,
            isResolved: isResolved,
            isOutdated: false,
            comments: ConversationPage(
                items: [ThreadComment(
                    id: "PRRC_1",
                    author: "kolega",
                    body: "tady chybí test",
                    createdAt: Date(timeIntervalSince1970: 50),
                    url: URL(string: "https://github.com/o/r/pull/3#discussion_r1")!
                )],
                total: 1,
                hasNextPage: false
            )
        )
    }

    private func conversation(isResolved: Bool = false) -> Conversation {
        Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [thread(isResolved: isResolved)], total: 1, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    private let replyOutput = """
    {"data":{"addPullRequestReviewThreadReply":{"comment":{
      "id":"PRRC_moje","body":"díky, opravím","createdAt":"2026-08-04T06:54:10Z",
      "url":"https://github.com/o/r/pull/3#discussion_r2",
      "author":{"login":"ondrajodas"},"replyTo":{"id":"PRRC_1"}}}}}
    """

    private let resolveOutput = """
    {"data":{"resolveReviewThread":{"thread":{
      "id":"PRRT_kwDOTrIEts6WHlSg","isResolved":true,
      "viewerCanResolve":false,"viewerCanUnresolve":true}}}}
    """

    /// Skript, který se tváří jako `gh`: zapíše, že byl spuštěn, a vypíše připravený výstup.
    ///
    /// `delay` je tam kvůli testu dvojkliku — bez něj by první volání doběhlo dřív, než druhé
    /// začne, a závod, který má ochrana zavřít, by v testu vůbec nenastal.
    private func fakeGh(_ output: String, exitCode: Int32 = 0, delay: Double = 0) throws -> URL {
        let script = directory.url.appending(path: "gh-\(UUID().uuidString).sh")
        let redirect = exitCode == 0 ? "" : ">&2"
        let text = """
        #!/bin/sh
        echo "call" >> "\(calls.path(percentEncoded: false))"
        \(delay > 0 ? "sleep \(delay)" : "")
        cat \(redirect) <<'PRISMJSON'
        \(output)
        PRISMJSON
        exit \(exitCode)
        """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path(percentEncoded: false)
        )
        return script
    }

    /// Kolikrát se `gh` doopravdy spustilo. Nula znamená „neodeslalo se nic“.
    private func ghCalls() throws -> Int {
        guard let text = try? String(contentsOf: calls, encoding: .utf8) else { return 0 }
        return text.split(whereSeparator: \.isNewline).count
    }

    private func store(
        gh: URL,
        configuration: Configuration? = nil,
        conversations: [Result<Conversation, any Error>]? = nil
    ) -> (AppStore, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(
            always: .success([summary()]),
            detail: .success(detail()),
            conversations: conversations ?? [.success(conversation())]
        )
        let store = AppStore(
            gateway: gateway,
            configuration: configuration ?? publishing,
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: layout),
            gh: gh
        )
        return (store, gateway)
    }

    private func prepared(
        gh: URL,
        configuration: Configuration? = nil,
        conversations: [Result<Conversation, any Error>]? = nil
    ) async -> (AppStore, FakeGitHubGateway) {
        let (store, gateway) = store(gh: gh, configuration: configuration, conversations: conversations)
        await store.loadConversation(for: summary())
        return (store, gateway)
    }

    // MARK: - Odpověď se objeví bez dalšího načtení

    /// **Nejdůležitější test #73 na úrovni store.** Odeslaná odpověď je ve vlákně hned a
    /// konverzace se **nenačítá znovu** — kolo po síti kvůli komentáři, který už máme, by
    /// v okně vypadalo jako sekání.
    @Test("Odeslaná odpověď je ve vlákně bez dalšího dotazu")
    func showsTheReplyWithoutRefetching() async throws {
        let (store, gateway) = await prepared(gh: try fakeGh(replyOutput))
        let loaded = gateway.conversationRequests.count
        store.setThreadReply("díky, opravím", for: threadID, in: pr)

        await store.sendThreadReply(to: thread(), in: summary())

        let thread = try #require(store.conversation(for: pr)?.threads.items.first)
        #expect(thread.comments.items.map(\.id) == ["PRRC_1", "PRRC_moje"])
        #expect(thread.comments.total == 2)
        #expect(gateway.conversationRequests.count == loaded, "konverzace se načítala znovu")
        #expect(try ghCalls() == 1)
    }

    @Test("Po úspěchu se rozepsaný text smaže")
    func clearsTheTextAfterSuccess() async throws {
        let (store, _) = await prepared(gh: try fakeGh(replyOutput))
        store.setThreadReply("díky, opravím", for: threadID, in: pr)

        await store.sendThreadReply(to: thread(), in: summary())

        #expect(store.threadReply(for: threadID, in: pr).isEmpty)
        #expect(store.threadState(for: threadID, in: pr) == nil)
    }

    // MARK: - Selhání

    /// **Text zůstává** — to je zadání #73 a jediná pojistka proti tomu, aby se rozepsaná věta
    /// ztratila kvůli chvilkovému výpadku.
    @Test("Selhání nechá text na místě")
    func keepsTheTextAfterFailure() async throws {
        let gh = try fakeGh("gh: could not connect to api.github.com", exitCode: 1)
        let (store, _) = await prepared(gh: gh)
        store.setThreadReply("díky, opravím", for: threadID, in: pr)

        await store.sendThreadReply(to: thread(), in: summary())

        #expect(store.threadReply(for: threadID, in: pr) == "díky, opravím")
        #expect(store.threadState(for: threadID, in: pr)?.failure != nil)
        // A komentář se do vlákna **nepřidal** — jinak by v okně viselo něco, co na GitHubu není.
        let thread = try #require(store.conversation(for: pr)?.threads.items.first)
        #expect(thread.comments.items.count == 1)
    }

    /// Selhání **nese, co selhalo** — a na tom visí věta v okně: u odpovědi končí hláška „text
    /// zůstal“, u vyřešení by to byla nepravda, protože není co zachraňovat. Chytila to vlastní
    /// revize diffu, kdy se ta věta lepila k obojímu.
    @Test("Po selhání je poznat, jestli zůstal text")
    func distinguishesWhichActionFailed() async throws {
        let gh = try fakeGh("gh: could not connect to api.github.com", exitCode: 1)
        let (store, _) = await prepared(gh: gh)
        store.setThreadReply("díky", for: threadID, in: pr)

        await store.sendThreadReply(to: thread(), in: summary())
        #expect(store.threadState(for: threadID, in: pr)?.keptText == true)

        await store.setThreadResolved(true, of: thread(), in: summary())
        #expect(store.threadState(for: threadID, in: pr)?.keptText == false)
        // Chyba je v obou případech k dispozici, jen se u ní říká něco jiného.
        #expect(store.threadState(for: threadID, in: pr)?.failure != nil)
    }

    /// Prázdná odpověď **nesmí sáhnout na síť**: GitHub ji tiše zahodí, takže by okno hlásilo
    /// úspěch nad komentářem, který nevznikl.
    @Test("Prázdná odpověď se nevolá")
    func doesNotSendABlankReply() async throws {
        let (store, _) = await prepared(gh: try fakeGh(replyOutput))

        await store.sendThreadReply(to: thread(), in: summary())

        #expect(try ghCalls() == 0)
        #expect(store.threadState(for: threadID, in: pr)?.failure == .blankReply)
    }

    /// Bez povolení v nastavení se neodešle nic — tatáž brána jako u review.
    @Test("Bez povolení se neodešle nic")
    func refusesWithoutPermission() async throws {
        let (store, _) = await prepared(gh: try fakeGh(replyOutput), configuration: .standard)
        store.setThreadReply("díky", for: threadID, in: pr)

        #expect(!store.canPublishToThreads(in: pr.repo))
        await store.sendThreadReply(to: thread(), in: summary())

        #expect(try ghCalls() == 0)
        #expect(store.threadReply(for: threadID, in: pr) == "díky")
    }

    /// Dvě kliknutí za sebou nesmí poslat dvě odpovědi — druhá by nebyla opravou první, ale
    /// duplikátem ve vlákně. Ochrana leží **před** prvním `await`, takže se testuje závodem;
    /// sekvenční test by prošel i bez ní.
    @Test("Dvojklik pošle jednu odpověď")
    func sendsOneReplyOnDoubleClick() async throws {
        let (store, _) = await prepared(gh: try fakeGh(replyOutput, delay: 0.3))
        store.setThreadReply("díky", for: threadID, in: pr)

        async let first: Void = store.sendThreadReply(to: thread(), in: summary())
        async let second: Void = store.sendThreadReply(to: thread(), in: summary())
        _ = await (first, second)

        #expect(try ghCalls() == 1)
    }

    // MARK: - Vyřešení

    @Test("Vyřešení se zapíše do konverzace i s právy")
    func writesTheResolution() async throws {
        let (store, gateway) = await prepared(gh: try fakeGh(resolveOutput))
        let loaded = gateway.conversationRequests.count

        await store.setThreadResolved(true, of: thread(), in: summary())

        let thread = try #require(store.conversation(for: pr)?.threads.items.first)
        #expect(thread.isResolved)
        #expect(!thread.canResolve)
        #expect(thread.canUnresolve)
        #expect(gateway.conversationRequests.count == loaded, "konverzace se načítala znovu")
    }

    @Test("Selhané vyřešení nechá vlákno být a chybu ukáže")
    func keepsTheThreadAfterAFailedResolution() async throws {
        let gh = try fakeGh("gh: Could not resolve to a node with the global id of 'PRRT_x'", exitCode: 1)
        let (store, _) = await prepared(gh: gh)

        await store.setThreadResolved(true, of: thread(), in: summary())

        let thread = try #require(store.conversation(for: pr)?.threads.items.first)
        #expect(!thread.isResolved)
        #expect(store.threadState(for: threadID, in: pr)?.failure == .threadNotFound(
            "gh: Could not resolve to a node with the global id of 'PRRT_x'"
        ))
    }

    // MARK: - Rozepsaný text

    @Test("Prázdný text se z mapy maže")
    func dropsAnEmptyText() {
        let (store, _) = store(gh: URL(filePath: "/usr/bin/true"))

        store.setThreadReply("něco", for: threadID, in: pr)
        #expect(store.threadReply(for: threadID, in: pr) == "něco")

        store.setThreadReply("", for: threadID, in: pr)
        #expect(store.threadReplies.isEmpty)
    }

    /// Rozepsaná odpověď se drží **per PR i per vlákno** — dvě vlákna si nesmí přepsat text.
    @Test("Dvě vlákna mají každé svůj text")
    func keepsTextPerThread() {
        let (store, _) = store(gh: URL(filePath: "/usr/bin/true"))

        store.setThreadReply("první", for: threadID, in: pr)
        store.setThreadReply("druhé", for: "PRRT_jine", in: pr)

        #expect(store.threadReply(for: threadID, in: pr) == "první")
        #expect(store.threadReply(for: "PRRT_jine", in: pr) == "druhé")
    }
}
