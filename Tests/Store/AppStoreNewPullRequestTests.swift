import Foundation
import Testing

@testable import PRism

/// Notifikace o novém PR ve frontě (#85) ze strany store.
///
/// Proti **skutečnému** `AnnouncedPullRequests` nad dočasnou složkou: na disku je to, co
/// rozhoduje o lavině po restartu, takže fake by ověřoval sám sebe.
///
/// To hlavní tady jsou dvě věci: že **první tik po startu neohlásí nic** a že se snímek
/// **nepřepíše po selhaném doručení** — jinak by se ta notifikace už nikdy neposlala.
@Suite("AppStore — notifikace o novém PR")
@MainActor
struct AppStoreNewPullRequestTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private var sources: [Source] {
        [Source(name: "Moje", query: "review-requested:@me is:open")]
    }

    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = sources
        return configuration
    }

    private func summary(_ text: String, title: String = "titulek") -> PullRequestSummary {
        let id = PRIdentifier(text)!
        return PullRequestSummary(
            id: id,
            title: title,
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(
        _ gateway: FakeGitHubGateway,
        center: FakeNotificationCenter,
        announced: AnnouncedPullRequests? = nil
    ) -> AppStore {
        AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(),
            notifications: center,
            announced: announced ?? AnnouncedPullRequests(layout: layout)
        )
    }

    @Test("První tik po startu neohlásí nic")
    func staysQuietOnTheFirstTick() async {
        // Jinak by po každém spuštění přišlo deset notifikací naráz — a to je konec notifikací,
        // protože si je uživatel vypne.
        let center = FakeNotificationCenter()
        let store = store(
            FakeGitHubGateway(always: .success([summary("cli/cli#1"), summary("cli/cli#2")])),
            center: center
        )

        await store.refresh()

        #expect(center.delivered.isEmpty)
    }

    @Test("Druhý tik ohlásí, co přibylo")
    func announcesWhatArrivedLater() async {
        let center = FakeNotificationCenter()
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1")]),
            .success([summary("cli/cli#1"), summary("cli/cli#2", title: "Opravit součet")]),
        ])
        let store = store(gateway, center: center)

        await store.refresh()
        await store.refresh()

        #expect(center.delivered.count == 1)
        #expect(center.delivered.first?.pullRequest == PRIdentifier("cli/cli#2"))
        #expect(center.delivered.first?.body == "Opravit součet")
        #expect(center.delivered.first?.title.contains("cli/cli#2") == true)
    }

    @Test("Už ohlášené PR se neohlašuje pořád dokola")
    func doesNotRepeatItself() async {
        let center = FakeNotificationCenter()
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let store = store(gateway, center: center)

        await store.refresh()
        await store.refresh()
        await store.refresh()

        #expect(center.delivered.isEmpty)
    }

    @Test("Lavina po restartu nenastane")
    func doesNotFloodAfterARestart() async {
        // Snímek je na disku právě kvůli tomuhle: nová instance store nad tou samou cache už
        // ví, co se ohlásilo.
        let listed = [summary("cli/cli#1"), summary("cli/cli#2")]
        let center = FakeNotificationCenter()
        let first = store(FakeGitHubGateway(always: .success(listed)), center: center)
        await first.refresh()
        await first.refresh()

        let afterRestart = FakeNotificationCenter()
        let second = store(FakeGitHubGateway(always: .success(listed)), center: afterRestart)
        await second.refresh()

        #expect(afterRestart.delivered.isEmpty)
    }

    @Test("Selhaný tik snímek nevyprázdní")
    func aFailedTickDoesNotResetTheSnapshot() async {
        // Po výpadku sítě je seznam prázdný. Kdyby se snímek přepsal, při zotavení by přišlo
        // úplně všechno — tatáž past jako u `CacheEviction` a `ReviewStore.cleanUp`.
        let center = FakeNotificationCenter()
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1")]),
            .failure(GitHubError.network("bez sítě")),
            .success([summary("cli/cli#1")]),
        ])
        let store = store(gateway, center: center)

        await store.refresh()
        await store.refresh()
        await store.refresh()

        #expect(center.delivered.isEmpty)
    }

    @Test("Po selhaném doručení se to zkusí znovu")
    func retriesAfterAFailedDelivery() async {
        // Snímek se zapisuje **až po doručení**. Opačné pořadí by znamenalo, že se PR zapíše
        // jako ohlášené, notifikace se nepovede a už nikdy nepřijde — a je to zadání #85.
        let center = FakeNotificationCenter(outcome: .failed("centrum neodpovědělo"))
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1")]),
            .success([summary("cli/cli#1"), summary("cli/cli#2")]),
            .success([summary("cli/cli#1"), summary("cli/cli#2")]),
        ])
        let store = store(gateway, center: center)

        await store.refresh()
        await store.refresh()
        #expect(center.delivered.count == 1)

        center.answer(with: .delivered)
        await store.refresh()

        #expect(center.delivered.count == 2)
        #expect(center.delivered.allSatisfy { $0.pullRequest == PRIdentifier("cli/cli#2") })
    }

    @Test("Snímek nese celou frontu, ne jen ohlášené")
    func remembersTheWholeQueue() async {
        // Kdyby se zapisovalo jen to, co se doručilo, vypadlo by z něj PR, které tam bylo už
        // minule — a ohlásilo by se podruhé.
        let center = FakeNotificationCenter()
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1")]),
            .success([summary("cli/cli#1"), summary("cli/cli#2")]),
            .success([summary("cli/cli#1"), summary("cli/cli#2")]),
        ])
        let store = store(gateway, center: center)

        await store.refresh()
        await store.refresh()
        await store.refresh()

        #expect(center.delivered.count == 1)
    }

    @Test("Bez notifikačního centra se snímek nezakládá")
    func doesNothingWithoutACenter() async {
        // Kdyby se snímek plnil i bez centra, po zapnutí notifikací by se první nová PR
        // neohlásila — vypadala by jako už ohlášená.
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([summary("cli/cli#1")])),
            configuration: configuration,
            time: FakeTimeSource(),
            announced: AnnouncedPullRequests(layout: layout)
        )

        await store.refresh()

        #expect(!FileManager.default.fileExists(atPath: layout.announcedFile.path))
    }
}
