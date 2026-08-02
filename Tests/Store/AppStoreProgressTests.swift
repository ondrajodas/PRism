import Foundation
import Testing

@testable import PRism

/// Časová osa toho, co reviewer dělal. Drží ji store, aby zůstala i po doběhnutí běhu —
/// právě tehdy se k ní člověk vrací.
@Suite("AppStore — průběh review")
@MainActor
struct AppStoreProgressTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
    private let pr = PRIdentifier("cli/cli#1")!

    private func detail() -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "head123",
            baseSha: "base456",
            url: URL(string: "https://github.com/cli/cli/pull/1")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(_ reviewer: FakeReviewRunner, reviews: ReviewStore) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail())),
            sources: sources,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(outcome: .success(URL(filePath: "/tmp/clone.git"))),
            reviewer: reviewer,
            reviews: reviews,
            skills: ["code-review"]
        )
    }

    private func runReview(_ store: AppStore) async {
        store.startReview(for: pr)
        for _ in 0..<400 where store.isReviewing(pr) {
            await Task.yield()
        }
    }

    @Test("Průběh běhu se zaznamená v pořadí")
    func recordsProgressInOrder() async throws {
        let workspace = try TemporaryDirectory()
        let reviewer = FakeReviewRunner(
            progress: [
                .queued,
                .started(sessionID: "session-abc"),
                .attemptedTool(ToolAttempt(name: "Read", detail: "App/Main.swift")),
                .findings(count: 2),
            ]
        )
        let store = store(reviewer, reviews: ReviewStore(layout: CacheLayout(root: workspace.url)))

        await runReview(store)

        let timeline = try #require(store.timelines(for: pr).first)
        #expect(timeline.skill == "code-review")
        #expect(timeline.sessionID == "session-abc")
        // Pořadí je to hlavní, co časová osa říká.
        #expect(timeline.entries.map(\.kind) == [
            .queued,
            .started,
            .tool(ToolAttempt(name: "Read", detail: "App/Main.swift")),
            .findings(count: 2),
            .finished(.finished),
        ])
    }

    /// K průběhu se člověk vrací **po** doběhnutí — „co to vlastně četlo?“.
    @Test("Časová osa zůstane i po doběhnutí")
    func keepsTheTimelineAfterTheRun() async throws {
        let workspace = try TemporaryDirectory()
        let store = store(
            FakeReviewRunner(progress: [.queued, .started(sessionID: "s")]),
            reviews: ReviewStore(layout: CacheLayout(root: workspace.url))
        )

        await runReview(store)

        #expect(!store.isReviewing(pr))
        #expect(store.timelines(for: pr).first?.entries.isEmpty == false)
    }

    @Test("Nový běh začíná s čistou osou")
    func startsAFreshTimelineForEveryRun() async throws {
        let workspace = try TemporaryDirectory()
        let store = store(
            FakeReviewRunner(progress: [.queued, .started(sessionID: "s")]),
            reviews: ReviewStore(layout: CacheLayout(root: workspace.url))
        )

        await runReview(store)
        let first = store.timelines(for: pr).first?.entries.count
        await runReview(store)

        #expect(store.timelines(for: pr).first?.entries.count == first)
    }

    @Test("Průběh PR, které zmizelo ze seznamu, se zahodí")
    func forgetsTheTimelineOfAPullRequestThatLeftTheList() async throws {
        let workspace = try TemporaryDirectory()
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail())),
            sources: sources,
            time: FakeTimeSource(stopAfter: 1),
            checkout: FakeRepoCheckout(outcome: .success(URL(filePath: "/tmp/clone.git"))),
            reviewer: FakeReviewRunner(progress: [.queued]),
            reviews: ReviewStore(layout: CacheLayout(root: workspace.url)),
            skills: ["code-review"]
        )

        await runReview(store)
        #expect(!store.timelines(for: pr).isEmpty)

        await store.keepFresh()   // tik, ve kterém to PR není

        #expect(store.timelines(for: pr).isEmpty)
    }
}
