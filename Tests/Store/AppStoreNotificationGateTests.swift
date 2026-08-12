import Foundation
import Testing

@testable import PRism

/// Brána z nastavení (#86) na straně store.
///
/// To hlavní jsou dvě věci: že se vypnutá událost **nedoručí** a že se u ní **nežádá
/// o oprávnění** — to druhé je zadání #86 a pozná se jen tím, že se centra nikdo nezeptal.
@Suite("AppStore — brána notifikací")
@MainActor
struct AppStoreNotificationGateTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private var detail: PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func configuration(_ notifications: NotificationSettings) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.notifications = notifications
        configuration.global.sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
        return configuration
    }

    private func summary(_ text: String) -> PullRequestSummary {
        let id = PRIdentifier(text)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(
        _ center: FakeNotificationCenter,
        settings: NotificationSettings,
        reviewer: FakeReviewRunner = FakeReviewRunner(),
        listing: [PullRequestSummary] = []
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success(listing), detail: .success(detail)),
            configuration: configuration(settings),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            notifications: center,
            announced: AnnouncedPullRequests(layout: layout)
        )
    }

    private func finding() -> ReportedFinding {
        ReportedFinding(
            file: "Cart.swift",
            line: 13,
            category: "correctness",
            verdict: .confirmed,
            shortSummary: nil,
            summary: "total() ignoruje množství",
            failureScenario: nil
        )
    }

    private func waitUntilIdle(_ store: AppStore) async {
        await waitUntil("review doběhne") { !store.isReviewing(pr) }
    }

    @Test("S vypnutými notifikacemi se centra nikdo nezeptá")
    func doesNotEvenAskWhenDisabled() async {
        // Zadání #86: o oprávnění se nemá žádat, když jsou notifikace vypnuté — a `deliver`
        // je to, co si o něj říká. Nula doručení je jediný způsob, jak dokázat, že se
        // nezeptalo.
        let center = FakeNotificationCenter()
        let store = store(center, settings: NotificationSettings(isEnabled: false),
                          reviewer: FakeReviewRunner(findings: [finding()]))

        store.startReview(for: pr)
        await waitUntilIdle(store)

        #expect(center.delivered.isEmpty)
    }

    @Test("Vypnuté nálezy nezastaví hlášku o selhání")
    func turningOffFindingsKeepsFailures() async {
        let center = FakeNotificationCenter()
        let store = store(center, settings: NotificationSettings(findings: false),
                          reviewer: FakeReviewRunner(failing: TestFailure()))

        store.startReview(for: pr)
        await waitUntilIdle(store)

        #expect(center.delivered.count == 1)
        #expect(center.delivered.first?.event == .failure)
    }

    @Test("Vypnuté nálezy zastaví notifikaci o nálezech")
    func turningOffFindingsSilencesThem() async {
        let center = FakeNotificationCenter()
        let store = store(center, settings: NotificationSettings(findings: false),
                          reviewer: FakeReviewRunner(findings: [finding()]))

        store.startReview(for: pr)
        await waitUntilIdle(store)

        #expect(center.delivered.isEmpty)
    }

    @Test("Vypnuté čisté review nezastaví nálezy")
    func turningOffCleanKeepsFindings() async {
        let center = FakeNotificationCenter()
        let store = store(center, settings: NotificationSettings(clean: false),
                          reviewer: FakeReviewRunner(findings: [finding()]))

        store.startReview(for: pr)
        await waitUntilIdle(store)

        #expect(center.delivered.first?.event == .findings)
    }

    @Test("Vypnuté čisté review umlčí čistý běh")
    func turningOffCleanSilencesACleanRun() async {
        let center = FakeNotificationCenter()
        let store = store(center, settings: NotificationSettings(clean: false))

        store.startReview(for: pr)
        await waitUntilIdle(store)

        #expect(center.delivered.isEmpty)
    }

    @Test("Vypnutý nový PR nezastaví notifikace o review")
    func turningOffNewPullRequestKeepsReviewNotices() async {
        let center = FakeNotificationCenter()
        let store = store(
            center,
            settings: NotificationSettings(newPullRequest: false),
            reviewer: FakeReviewRunner(findings: [finding()]),
            listing: [summary("cli/cli#7")]
        )

        // Dva tiky by jinak ohlásily nový PR; s vypnutou událostí nesmí přijít nic.
        await store.refresh()
        await store.refresh()
        #expect(center.delivered.isEmpty)

        store.startReview(for: pr)
        await waitUntilIdle(store)

        #expect(center.delivered.count == 1)
        #expect(center.delivered.first?.event == .findings)
    }

    @Test("Vypnutá událost posune snímek, ať se to nezkouší dokola")
    func aDisabledEventStillAdvancesTheSnapshot() async {
        // Vypnutá událost není selhání doručení, takže se nemá opakovat: `notify` vrací `nil`
        // a `isWorthRetrying` proto neplatí. Kdyby se snímek nezapsal, ohlašovalo by se to při
        // každém tiku dokola — jen tiše.
        let center = FakeNotificationCenter()
        let store = store(
            center,
            settings: NotificationSettings(newPullRequest: false),
            listing: [summary("cli/cli#7")]
        )

        await store.refresh()
        await store.refresh()

        let stored = try? JSONDecoder().decode(
            [PRIdentifier].self,
            from: Data(contentsOf: layout.announcedFile)
        )
        #expect(stored == [PRIdentifier("cli/cli#7")!])
    }
}

private struct TestFailure: Error {}
