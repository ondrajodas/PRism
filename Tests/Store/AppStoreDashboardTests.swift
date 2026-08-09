import Foundation
import Testing

@testable import PRism

/// Co dashboard bere ze store (#181).
///
/// Dvě tvrzení, na kterých to stojí: fronta se řadí **podle závažnosti**, ne podle času (v seznamu
/// je to naopak, a kdyby si store spletl getter, nikdo by si toho nevšiml), a hromadné spuštění
/// sáhne **jen na to, co neběželo**.
@Suite("AppStore — dashboard")
@MainActor
struct AppStoreDashboardTests {
    private func summary(_ identifier: String, updatedAt: TimeInterval = 100) -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    private func store(_ pullRequests: [PullRequestSummary]) async -> AppStore {
        let store = AppStore(gateway: FakeGitHubGateway(always: .success(pullRequests)), time: FakeTimeSource())
        await store.refresh()
        return store
    }

    /// Seznam v záložce `Fronta` je od naposledy změněného; dashboard odpovídá na jinou otázku,
    /// takže nahoru patří blokující nález, i když je to nejstarší PR ve frontě.
    @Test("Fronta dashboardu se řadí podle závažnosti, ne podle času")
    func ordersTheQueueByUrgency() async {
        let blocking = summary("cli/cli#1", updatedAt: 100)
        let newest = summary("cli/cli#2", updatedAt: 900)
        let store = await store([blocking, newest])
        store.reviewRecords[blocking.id] = makeRecord(
            runs: [makeStoredRun(findings: [makeReported(category: "correctness", verdict: .confirmed)])]
        )

        #expect(store.pullRequests.map(\.id) == [newest.id, blocking.id])
        #expect(store.dashboardQueue.map(\.id) == [blocking.id, newest.id])
    }

    /// Zúžený seznam čte jedině seznam a detail (#117). Dashboard je tvrzení o tom, co ve frontě
    /// **je** — kdyby četl filtr, zapnutí filtru by z něj udělalo jiná čísla než ze stavového řádku.
    @Test("Filtr seznamu frontu v dashboardu nezúží")
    func ignoresTheListFilter() async {
        let store = await store([summary("cli/cli#1"), summary("cli/cli#2")])

        store.setFilter(PullRequestFilter(repositories: [RepoID("cli/other")!]))

        #expect(store.visiblePullRequests.isEmpty)
        #expect(store.dashboardQueue.count == 2)
        #expect(store.dashboard.queue.pullRequests == 2)
    }

    @Test("Řádek fronty nese stav, blokující i tužku draftu")
    func carriesTheRowState() async throws {
        let pullRequest = summary("cli/cli#1")
        let store = await store([pullRequest])
        store.reviewRecords[pullRequest.id] = makeRecord(
            runs: [makeStoredRun(findings: [makeReported(category: "correctness", verdict: .confirmed)])]
        )

        // `try #require`, ne `try?`: s optionalem by test nad prázdnou frontou prošel naprázdno.
        let entry = try #require(store.dashboardQueue.first)
        #expect(entry.state == .completed(findings: 1))
        #expect(entry.row.blocking == 1)
        #expect(entry.hasDraft == false)
    }

    // MARK: - Pustit review na vše, co neběželo

    @Test("Bez záznamu je PR ve výčtu toho, co neběželo")
    func listsPullRequestsWithoutARun() async {
        let clean = summary("cli/cli#1")
        let fresh = summary("cli/cli#2")
        let store = await store([clean, fresh])
        store.reviewRecords[clean.id] = makeRecord(runs: [makeStoredRun(findings: [])])

        #expect(store.pullRequestsNotReviewed == [fresh.id])
    }

    /// **Nejcennější test téhle sady.** Hromadné spuštění bez reviewera nesmí nic naplánovat —
    /// jinak by z jednoho kliknutí zůstala fronta běhů, které nemá kdo spustit.
    @Test("Bez reviewera se hromadným spuštěním nic nespustí")
    func startsNothingWithoutAReviewer() async {
        let store = await store([summary("cli/cli#1"), summary("cli/cli#2")])

        store.startReviewsForNotReviewed()

        #expect(store.runningReviews == 0)
    }
}

/// Osa běhu po restartu (#203).
@Suite("AppStore — uložená osa")
@MainActor
struct AppStoreTimelineTests {
    private let pullRequest = PRIdentifier("cli/cli#1")!

    private func store() -> AppStore {
        AppStore(gateway: FakeGitHubGateway([.success([])]), time: FakeTimeSource())
    }

    private func stored(_ detail: String) -> StoredTimeline {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: detail)), at: Date())
        return timeline.stored()
    }

    @Test("Bez živé osy se vezme ta z uloženého záznamu")
    func fallsBackToTheStoredTimeline() {
        let store = store()
        store.reviewRecords[pullRequest] = makeRecord(runs: [makeStoredRun(timeline: stored("z disku.php"))])

        #expect(store.timelines(for: pullRequest).count == 1)
        #expect(store.timelines(for: pullRequest).first?.entries.count == 1)
    }

    /// **Nejcennější test téhle sady.** Běžící review si osu drží v paměti a uložená patří
    /// předchozímu běhu — přebít živou tou z disku by nad novým během ukázalo starý průběh.
    @Test("Živá osa přebíjí tu uloženou")
    func prefersTheLiveTimeline() {
        let store = store()
        store.reviewRecords[pullRequest] = makeRecord(runs: [makeStoredRun(timeline: stored("z disku.php"))])
        var live = ReviewerTimeline(skill: "code-review")
        live.record(.attemptedTool(ToolAttempt(name: "Read", detail: "živý.php")), at: Date())
        store.reviewTimelines[pullRequest] = [live]

        let timelines = store.timelines(for: pullRequest)
        #expect(timelines.count == 1)
        if case .tool(let tool) = timelines.first?.entries.first?.kind {
            #expect(tool.detail == "živý.php")
        } else {
            Issue.record("osa není z paměti")
        }
    }
}
