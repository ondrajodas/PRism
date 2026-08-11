import Foundation
import Testing

@testable import PRism

/// Co se stane s běžícími review, když se zavírá aplikace (#264).
///
/// Skoro všechno tady tvrdí, že se něco **nestalo**: že nezůstal běžet žádný běh, že se
/// nespustil nový a že se nesmazala značka, na které visí dotažení nálezů po startu. Takové
/// věci se rozbijí potichu — na obrazovce se zavírající aplikace už nic nepozná.
@Suite("AppStore — zavření aplikace")
@MainActor
struct AppStoreTerminationTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 43)

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

    /// Store v **automatickém** režimu, i když se většina testů spouští ručně: plánovač
    /// automatu je druhá cesta, kterou se během zavírání dá utratit session, a s vypnutým
    /// automatem (`autoRuns: nil`) by se test o ní netvrdil nic — vypadl by na první závoře.
    private func store(
        reviewer: any ReviewRunning,
        interrupted: InterruptedRuns? = nil
    ) -> AppStore {
        var configuration = Configuration.standard
        configuration.repositories = [pr.repo: RepositoryConfig(mode: .automatic)]
        return AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            autoRuns: AutoRunLedger(layout: layout, time: FakeTimeSource()),
            interrupted: interrupted
        )
    }

    private func summary(of pr: PRIdentifier) -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    @Test("Zavření aplikace ukončí všechna běžící review")
    func closingTheAppStopsEveryRun() async throws {
        let reviewer = FakeReviewRunner(holdsUntilRelease: true)
        let store = store(reviewer: reviewer)

        store.startReview(for: pr)
        store.startReview(for: other)
        await reviewer.waitForStarts(2)
        #expect(store.runningReviews == 2)

        await store.stopReviewsBeforeTermination()

        // Nezůstalo běžet nic — a nezůstalo to na volajícím, který by musel ještě čekat.
        #expect(store.runningReviews == 0)
        // A nic dalšího se nespustilo: dvě zadání, dvě session.
        #expect(reviewer.requests.count == 2)
    }

    @Test("Během zavírání se nespustí nové review")
    func nothingNewStartsWhileClosing() async throws {
        let reviewer = FakeReviewRunner(holdsUntilRelease: true)
        let store = store(reviewer: reviewer)

        store.startReview(for: pr)
        await reviewer.waitForStarts(1)
        await store.stopReviewsBeforeTermination()

        // Ruční cesta: tlačítko po zavření nesmí utratit session, kterou nikdo nezabije.
        store.startReview(for: other)
        // A automat taky ne. Tik pollingu dorazí i uprostřed zavírání a jeho běh by aplikaci
        // přežil — zabíjení už proběhlo, takže by na něj nikdo nesáhl.
        await store.startAutomaticReviews(for: [summary(of: other)])

        #expect(store.runningReviews == 0)
        #expect(reviewer.requests.count == 1)
    }

    @Test("Zavření aplikace nic neuloží jako doběhlé")
    func closingSavesNoResult() async throws {
        let reviewer = FakeReviewRunner(findings: [finding()], holdsUntilRelease: true)
        let store = store(reviewer: reviewer)

        store.startReview(for: pr)
        await reviewer.waitForStarts(1)
        await store.stopReviewsBeforeTermination()

        // Zabitý běh není doběhlý běh: `clean` ani počet nálezů by nad ním lhaly.
        #expect(store.reviewRecord(for: pr) == nil)
        #expect(store.reviewState(for: pr) == .notStarted)
    }

    /// Tohle je ta ztráta, kvůli které se ukončení nesmí chovat jako zrušení.
    ///
    /// Značka je jediné, podle čeho se po startu pozná, že v transcriptu leží nálezy
    /// z nedoběhlé session (#97). Zavření aplikace je pro běh totéž jako pád, takže značka
    /// musí zůstat — jinak by se z „přerušeno se dvěma nálezy“ stalo „neběželo“.
    @Test("Zavření aplikace nesmaže značku rozdělaného běhu")
    func closingKeepsTheInterruptedMark() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        let reviewer = FakeReviewRunner(
            holdsUntilRelease: true,
            progress: [.started(sessionID: "session-1")]
        )
        let store = store(reviewer: reviewer, interrupted: interrupted)

        store.startReview(for: pr)
        try await waitForMark(in: interrupted)

        await store.stopReviewsBeforeTermination()

        #expect(await interrupted.pending().map(\.sessionID) == ["session-1"])
    }

    /// Protějšek předchozího testu: u zrušení se značka mazat **má**.
    ///
    /// Bez tohohle by „nemazat při zavírání“ šlo splnit tím, že se nemaže nikdy — a příští
    /// start by dotahoval nálezy z běhu, který si člověk sám zrušil.
    @Test("Zrušení člověkem značku smaže")
    func cancellingForgetsTheMark() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        let reviewer = FakeReviewRunner(
            holdsUntilRelease: true,
            progress: [.started(sessionID: "session-1")]
        )
        let store = store(reviewer: reviewer, interrupted: interrupted)

        store.startReview(for: pr)
        try await waitForMark(in: interrupted)

        store.cancelReview(for: pr)
        for _ in 0..<100_000 where store.isReviewing(pr) { await Task.yield() }
        #expect(!store.isReviewing(pr))

        #expect(await interrupted.pending().isEmpty)
    }

    /// Počká, až si běh poznamená rozdělanou session — ale ne donekonečna.
    private func waitForMark(in interrupted: InterruptedRuns) async throws {
        for _ in 0..<100_000 {
            if await !interrupted.pending().isEmpty { return }
            await Task.yield()
        }
        Issue.record("Značka rozdělaného běhu se nezapsala.")
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
}
