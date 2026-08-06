import Foundation
import Testing

@testable import PRism

/// Opakování jednoho revieweera (#149). Fake reviewer si pamatuje **každé** zadání, takže se
/// dá dokázat to hlavní: ostatní skilly se nespustily, tedy se za ně nezaplatilo znovu.
@Suite("AppStore — opakování jednoho revieweera")
@MainActor
struct AppStoreRerunTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let skills = ["reviewer-a", "reviewer-b", "reviewer-c"]

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

    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.skills = skills
        return configuration
    }

    private func store(
        reviewer: FakeReviewRunner,
        reviews: ReviewStore? = nil
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: reviews ?? ReviewStore(layout: layout, time: FakeTimeSource())
        )
    }

    private func waitUntilIdle(_ store: AppStore) async throws {
        for _ in 0..<100_000 where store.isReviewing(pr) { await Task.yield() }
        #expect(!store.isReviewing(pr))
    }

    private func finding(_ summary: String) -> ReportedFinding {
        ReportedFinding(
            file: "Cart.swift",
            line: 13,
            category: "correctness",
            verdict: .confirmed,
            shortSummary: nil,
            summary: summary,
            failureScenario: nil
        )
    }

    /// Zadání #149: za dva výsledky, které už leží na disku, se nemá platit znovu.
    @Test("Opakování pustí jen svého revieweera")
    func runsOnlyTheChosenReviewer() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(reviewer: reviewer)

        store.startReview(for: pr, skills: ["reviewer-b"])
        try await waitUntilIdle(store)

        #expect(reviewer.requests.map(\.key.skillID) == ["reviewer-b"])
    }

    @Test("Bez podmnožiny se pustí celá sada")
    func runsEverythingByDefault() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(reviewer: reviewer)

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(Set(reviewer.requests.map(\.key.skillID)) == Set(skills))
    }

    /// `ReviewRecord.replace(_:)` je klíčovaný skillem, takže datová vrstva to unese už dneska
    /// — ale kdyby se opakování spustilo přes celou sadu, ostatní běhy by se přepsaly prázdnými.
    @Test("Uložené nálezy ostatních reviewerů zůstanou")
    func keepsTheOtherReviewersFindings() async throws {
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        let first = store(reviewer: FakeReviewRunner(findings: [finding("první")]), reviews: reviews)

        first.startReview(for: pr)
        try await waitUntilIdle(first)
        #expect(first.reviewRecord(for: pr)?.runs.count == 3)

        let again = store(reviewer: FakeReviewRunner(findings: [finding("druhý")]), reviews: reviews)
        await again.loadStoredReviews()
        again.startReview(for: pr, skills: ["reviewer-b"])
        try await waitUntilIdle(again)

        let record = try #require(again.reviewRecord(for: pr))
        #expect(record.runs.count == 3)
        #expect(record.runs.first { $0.skillID == "reviewer-a" }?.findings.first?.reported.summary == "první")
        #expect(record.runs.first { $0.skillID == "reviewer-b" }?.findings.first?.reported.summary == "druhý")
    }

    /// Osa se u nového review nuluje celá — u opakování jednoho revieweera by tím zmizel
    /// průběh ostatních, tedy to, kvůli čemu se do tabu chodí.
    @Test("Osa ostatních reviewerů zůstane")
    func keepsTheOtherTimelines() async throws {
        let store = store(reviewer: FakeReviewRunner())

        store.startReview(for: pr)
        try await waitUntilIdle(store)
        #expect(store.timelines(for: pr).count == 3)

        store.startReview(for: pr, skills: ["reviewer-b"])
        try await waitUntilIdle(store)

        let timelines = store.timelines(for: pr)
        #expect(Set(timelines.map(\.skill)) == Set(skills))
        // A ta jeho začíná načisto: míchat dva běhy do jedné osy by z ní udělalo nesmysl.
        #expect(timelines.filter { $0.skill == "reviewer-b" }.count == 1)
    }

    /// Chip revieweera, který neběží, musí dál ukazovat svůj uložený výsledek — ne spinner.
    @Test("Za běžící se považuje jen opakovaný reviewer")
    func onlyTheRerunReviewerCountsAsRunning() async throws {
        let reviewer = FakeReviewRunner(holdsUntilRelease: true)
        let store = store(reviewer: reviewer)

        store.startReview(for: pr, skills: ["reviewer-b"])
        await reviewer.waitForStarts(1)

        #expect(store.runningReviewers(for: pr) == ["reviewer-b"])

        reviewer.releaseAll()
        try await waitUntilIdle(store)
    }

    /// Je to jedna úloha na PR, takže se do běžícího review nedá vklínit další běh.
    @Test("Dokud review běží, opakování nic nespustí")
    func doesNothingWhileAReviewIsRunning() async throws {
        let reviewer = FakeReviewRunner(holdsUntilRelease: true)
        let store = store(reviewer: reviewer)

        store.startReview(for: pr)
        await reviewer.waitForStarts(3)
        store.startReview(for: pr, skills: ["reviewer-b"])

        reviewer.releaseAll()
        try await waitUntilIdle(store)
        #expect(reviewer.requests.count == 3)
    }

    /// Běh bez jediného revieweera by utratil checkout a nic nezjistil.
    @Test("Prázdná podmnožina nespustí nic")
    func doesNothingWithoutASkill() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(reviewer: reviewer)

        store.startReview(for: pr, skills: [])

        #expect(!store.isReviewing(pr))
        #expect(reviewer.requests.isEmpty)
    }
}
