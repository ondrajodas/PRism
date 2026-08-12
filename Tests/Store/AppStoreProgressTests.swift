import Foundation
import Testing

@testable import PRism

@Suite("ReviewerTimeline — nejnovější událost")
struct NewestEntryTests {
    private func timeline(_ skill: String, seconds: [TimeInterval]) -> ReviewerTimeline {
        var timeline = ReviewerTimeline(skill: skill)
        for second in seconds {
            timeline.record(.queued, at: Date(timeIntervalSince1970: second))
        }
        return timeline
    }

    /// Auto-scroll na konec se řídí tou **nejnovější** událostí. Brát ji z poslední osy
    /// v poli by u dvou souběžných reviewerů znamenalo, že se osa přestane posouvat,
    /// jakmile píše ten dřívější.
    @Test("Nejnovější událost se hledá napříč reviewery")
    func findsTheNewestEntryAcrossReviewers() throws {
        let timelines = [
            timeline("code-review", seconds: [10, 40]),
            timeline("security", seconds: [20]),
        ]

        let newest = try #require(ReviewerTimeline.newestEntry(in: timelines))

        #expect(newest.skill == "code-review")
        #expect(newest.entry == 1)
    }

    @Test("Bez událostí není co hledat")
    func findsNothingWithoutEntries() {
        #expect(ReviewerTimeline.newestEntry(in: [ReviewerTimeline(skill: "code-review")]) == nil)
        #expect(ReviewerTimeline.newestEntry(in: []) == nil)
    }
}

/// Časová osa toho, co reviewer dělal. Drží ji store, aby zůstala i po doběhnutí běhu —
/// právě tehdy se k ní člověk vrací.
@Suite("AppStore — průběh review")
@MainActor
struct AppStoreProgressTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]

    /// Zdroje i sada skillů se berou z konfigurace, takže si ji test postaví.
    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = sources
        return configuration
    }
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
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(outcome: .success(URL(filePath: "/tmp/clone.git"))),
            reviewer: reviewer,
            reviews: reviews,
        )
    }

    private func runReview(_ store: AppStore) async {
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(pr) }
    }

    /// Nastavené id, které na nic nemapuje, si model nahradí nejbližším — a hlavička osy
    /// by pak tvrdila, že běžel nastavený skill. Ověřeno u #78 na skutečném běhu.
    @Test("Načtený jiný skill se pozná")
    func spotsADifferentSkill() {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(
            .attemptedTool(ToolAttempt(name: "Skill", detail: "code-review:code-review")),
            at: Date(timeIntervalSince1970: 0)
        )

        #expect(timeline.loadedSkill == "code-review:code-review")
        #expect(timeline.loadedADifferentSkill)
    }

    @Test("Načtený správný skill se za záměnu nepovažuje")
    func acceptsTheRequestedSkill() {
        var timeline = ReviewerTimeline(skill: "code-review:code-review")
        timeline.record(
            .attemptedTool(ToolAttempt(name: "Skill", detail: "code-review:code-review")),
            at: Date(timeIntervalSince1970: 0)
        )

        #expect(!timeline.loadedADifferentSkill)
    }

    /// Běh, který si skill nevzal vůbec, udělal obecné review — jiná situace než záměna,
    /// a hlásit u něj „běžel jiný“ by bylo matoucí.
    @Test("Běh bez skillu není záměna")
    func aRunWithoutASkillIsNotAMismatch() {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(
            .attemptedTool(ToolAttempt(name: "Read", detail: "App/Main.swift")),
            at: Date(timeIntervalSince1970: 0)
        )

        #expect(timeline.loadedSkill == nil)
        #expect(!timeline.loadedADifferentSkill)
    }

    @Test("Průběh běhu se zaznamená v pořadí")
    func recordsProgressInOrder() async throws {
        let workspace = try TemporaryDirectory()
        // `.queued` hlásí runner sám, tady se dopisuje zbytek.
        let reviewer = FakeReviewRunner(
            progress: [
                .started(sessionID: "session-abc"),
                .attemptedTool(ToolAttempt(name: "Read", detail: "App/Main.swift")),
                .findings(count: 2),
            ]
        )
        let store = store(reviewer, reviews: ReviewStore(layout: CacheLayout(root: workspace.url)))

        await runReview(store)

        let timeline = try #require(store.timelines(for: pr).first)
        #expect(timeline.skill == Configuration.standard.global.skills.first)
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
            FakeReviewRunner(progress: [.started(sessionID: "s")]),
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
            FakeReviewRunner(progress: [.started(sessionID: "s")]),
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
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            checkout: FakeRepoCheckout(outcome: .success(URL(filePath: "/tmp/clone.git"))),
            reviewer: FakeReviewRunner(progress: [.started(sessionID: "s")]),
            reviews: ReviewStore(layout: CacheLayout(root: workspace.url)),
        )

        await runReview(store)
        #expect(!store.timelines(for: pr).isEmpty)

        await store.keepFresh()   // tik, ve kterém to PR není

        #expect(store.timelines(for: pr).isEmpty)
    }
}
