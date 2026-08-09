import Foundation
import Testing

@testable import PRism

/// Psaní komentáře do diskuze pod PR, jak ho skládá store (#216).
///
/// **Nic neodchází na GitHub**: `gh` je podstrčený shell skript v dočasné složce, který vypíše
/// připravenou odpověď. Fake publisher by se sem podstrčit nedal — `AppStore` si ho podle tvrdé
/// podmínky č. 1 nesmí držet ani jako továrnu, takže se testuje celá cesta včetně čtení výstupu.
/// Skript navíc zapisuje, kolikrát byl spuštěn, což je jediný způsob, jak ověřit, že se
/// **nevolalo nic**. Stejné uspořádání jako u odpovědí do vláken v #73.
@Suite("AppStore — komentář pod PR")
@MainActor
struct AppStoreCommentTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier("ondrajodas/prism-review-sandbox#4")!
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

    /// Konverzace s jedním komentářem **a jednou událostí**. Událost tam je schválně: po
    /// zápisu odeslaného komentáře se osa nesmí vyprázdnit, a bez události v datech by to
    /// test nepoznal.
    private func conversation() -> Conversation {
        Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(
                items: [ThreadComment(
                    id: "IC_1",
                    author: "kolega",
                    body: "díky za PR",
                    createdAt: Date(timeIntervalSince1970: 50),
                    url: URL(string: "https://github.com/o/r/pull/4#issuecomment-1")!
                )],
                total: 1,
                hasNextPage: false
            ),
            events: ConversationPage(
                items: [TimelineEvent(
                    id: "e1",
                    kind: .commit(oid: "aaaa1111", headline: "feat: něco"),
                    actor: EventActor(login: "autor", avatarURL: nil, isBot: false),
                    at: Date(timeIntervalSince1970: 60)
                )],
                total: 1,
                hasNextPage: false
            )
        )
    }

    private let commentOutput = """
    {"id":5158771955,
     "html_url":"https://github.com/o/r/pull/4#issuecomment-5158771955",
     "created_at":"2026-08-09T21:10:38Z","body":"mrknu na to zítra",
     "user":{"login":"ondrajodas"}}
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

    private func prepared(
        gh: URL,
        configuration: Configuration? = nil
    ) async -> (AppStore, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(
            always: .success([summary()]),
            detail: .success(detail()),
            conversations: [.success(conversation())]
        )
        let store = AppStore(
            gateway: gateway,
            configuration: configuration ?? publishing,
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: layout),
            gh: gh
        )
        await store.loadConversation(for: summary())
        return (store, gateway)
    }

    // MARK: - Komentář se objeví bez dalšího načtení

    @Test("Odeslaný komentář je v konverzaci bez dalšího dotazu")
    func showsTheCommentWithoutRefetching() async throws {
        let (store, gateway) = await prepared(gh: try fakeGh(commentOutput))
        let loaded = gateway.conversationRequests.count
        store.setPullRequestComment("mrknu na to zítra", for: pr)

        await store.sendPullRequestComment(for: summary())

        let conversation = try #require(store.conversation(for: pr))
        #expect(conversation.comments.items.map(\.id) == ["IC_1", "5158771955"])
        #expect(conversation.comments.total == 2)
        #expect(gateway.conversationRequests.count == loaded, "konverzace se načítala znovu")
        #expect(try ghCalls() == 1)
    }

    /// **Osa se odesláním komentáře nesmí vyprázdnit.** `Conversation.init` má `events`
    /// s výchozí prázdnou hodnotou, takže zapomenout je při přeskládání není chyba překladu —
    /// jen z osy tiše zmizí commity, pushe a vyžádaná review. Přesně ten druh ztráty, který
    /// v okně vypadá jako „nic tu nebylo“.
    @Test("Po odeslání komentáře zůstanou události na ose")
    func keepsTheTimelineEvents() async throws {
        let (store, _) = await prepared(gh: try fakeGh(commentOutput))
        store.setPullRequestComment("mrknu na to zítra", for: pr)

        await store.sendPullRequestComment(for: summary())

        let conversation = try #require(store.conversation(for: pr))
        #expect(conversation.events.items.map(\.id) == ["e1"])
    }

    @Test("Po úspěchu se rozepsaný text smaže")
    func clearsTheTextAfterSuccess() async throws {
        let (store, _) = await prepared(gh: try fakeGh(commentOutput))
        store.setPullRequestComment("mrknu na to zítra", for: pr)

        await store.sendPullRequestComment(for: summary())

        #expect(store.pullRequestComment(for: pr).isEmpty)
        #expect(store.pullRequestCommentState(for: pr) == nil)
    }

    // MARK: - Selhání

    /// **Text zůstává** — tatáž pojistka jako u odpovědi do vlákna: rozepsaná věta se nesmí
    /// ztratit kvůli chvilkovému výpadku.
    @Test("Po selhání text zůstane")
    func keepsTheTextAfterFailure() async throws {
        let (store, _) = await prepared(gh: try fakeGh("gh: nope", exitCode: 1))
        store.setPullRequestComment("mrknu na to zítra", for: pr)

        await store.sendPullRequestComment(for: summary())

        #expect(store.pullRequestComment(for: pr) == "mrknu na to zítra")
        #expect(store.pullRequestCommentState(for: pr)?.failure != nil)
        #expect(store.conversation(for: pr)?.comments.items.count == 1)
    }

    // MARK: - Nic se neodeslalo

    /// Bez povolení v nastavení neodejde nic — a pozná se to na tom, že se `gh` **vůbec
    /// nespustilo**.
    @Test("Bez povolení se neodešle nic")
    func sendsNothingWithoutPermission() async throws {
        let (store, _) = await prepared(gh: try fakeGh(commentOutput), configuration: .standard)
        store.setPullRequestComment("mrknu na to zítra", for: pr)

        await store.sendPullRequestComment(for: summary())

        #expect(try ghCalls() == 0)
        #expect(store.pullRequestComment(for: pr) == "mrknu na to zítra")
    }

    /// Dvojklik je **jeden** komentář, ne dva: druhé odeslání by nebylo oprava prvního,
    /// ale další věta v diskuzi.
    @Test("Dvojklik odešle komentář jednou")
    func sendsOnlyOnceOnADoubleClick() async throws {
        let (store, _) = await prepared(gh: try fakeGh(commentOutput, delay: 0.4))
        store.setPullRequestComment("mrknu na to zítra", for: pr)

        async let first: Void = store.sendPullRequestComment(for: summary())
        async let second: Void = store.sendPullRequestComment(for: summary())
        _ = await (first, second)

        #expect(try ghCalls() == 1)
    }

    /// Rozepsaný komentář jde s PR, ke kterému patří — bez konverzace se nemá kde ukázat
    /// ani odeslat. Bez úklidu by mapa rostla donekonečna.
    @Test("Rozepsaný komentář se uklidí s PR mimo seznam")
    func forgetsTheDraftWhenThePullRequestLeaves() async throws {
        // Druhý tik PR nevrátí — tím ze seznamu vypadne a úklid na něj má sáhnout.
        let gateway = FakeGitHubGateway(
            [.success([summary()]), .success([])],
            detail: .success(detail()),
            conversations: [.success(conversation())]
        )
        let store = AppStore(
            gateway: gateway,
            configuration: publishing,
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: layout),
            gh: try fakeGh(commentOutput)
        )
        await store.refresh()
        store.setPullRequestComment("rozepsáno", for: pr)
        #expect(store.pullRequestComment(for: pr) == "rozepsáno")

        await store.refresh()

        #expect(store.pullRequestComment(for: pr).isEmpty)
    }
}
