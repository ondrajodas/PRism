import Foundation
import Testing

@testable import PRism

/// Proti skutečné dočasné složce, ne proti fake filesystému.
///
/// Stejná úvaha jako u `CacheEviction`: kořen je injektovatelný, takže testům stačí pár
/// kilobajtů — a zároveň se ověřuje to, na čem store opravdu stojí, tedy chování
/// `FileManageru` a `Codable` cesta na disk a zpět.
@Suite("ReviewStore")
struct ReviewStoreTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let time: FakeTimeSource

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        time = FakeTimeSource()
    }

    private func store(retention: TimeInterval = ReviewStore.defaultRetention) -> ReviewStore {
        ReviewStore(layout: layout, retention: retention, time: time)
    }

    private var pullRequest: PRIdentifier {
        PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    }

    private func run(
        skill: String = "code-review",
        pr: PRIdentifier? = nil,
        headSha: String = "aaaa1111",
        findings: [String] = ["total() ignoruje množství"],
        outcome: ReviewRunOutcome = .finished
    ) -> ReviewRun {
        var summary = StreamSummary()
        summary.sessionID = "session-\(skill)"
        summary.calledReportFindings = true
        summary.findings = findings.map {
            ReportedFinding(
                file: "Cart.swift",
                line: 13,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: nil,
                summary: $0,
                failureScenario: nil
            )
        }
        return ReviewRun(
            key: ReviewRunKey(
                pullRequest: pr ?? pullRequest,
                headSha: headSha,
                skillID: skill
            ),
            summary: summary,
            outcome: outcome
        )
    }

    /// Posune fake hodiny — ten je umí posunout jen uspáním.
    private func advance(days: Int) async throws {
        try await time.sleep(for: .seconds(days * 24 * 60 * 60))
    }

    // MARK: - Uložit a načíst

    @Test("Uložený běh přežije cestu na disk a zpět")
    func aSavedRunSurvivesTheRoundTrip() async throws {
        let store = store()

        try await store.save(run())
        let loaded = try await store.load()

        #expect(loaded.unreadable == 0)
        let record = try #require(loaded.records.first)
        #expect(record.pullRequest == pullRequest)
        #expect(record.headSha == "aaaa1111")
        #expect(record.isStale == false)
        let stored = try #require(record.runs.first)
        #expect(stored.skillID == "code-review")
        #expect(stored.outcome == .finished)
        #expect(stored.sessionID == "session-code-review")
        #expect(stored.calledReportFindings)
        #expect(stored.findings.map(\.summary) == ["total() ignoruje množství"])
        #expect(stored.findings.first?.headSha == "aaaa1111")
        #expect(stored.finishedAt == time.now)
    }

    @Test("Selhaný běh si nese stderr")
    func aFailedRunKeepsItsStderr() async throws {
        // `failed` a „nic nenašel" se nesmí slít, takže se musí uložit i důvod.
        let store = store()

        try await store.save(run(findings: [], outcome: .failed(detail: "Invalid API key")))
        let loaded = try await store.load()

        let stored = try #require(loaded.records.first?.runs.first)
        #expect(stored.outcome == .failed(detail: "Invalid API key"))
        #expect(stored.findings.isEmpty)
    }

    @Test("Dva skilly nad jedním commitem jsou jeden záznam")
    func twoSkillsShareOneRecord() async throws {
        let store = store()

        try await store.save(run(skill: "code-review"))
        try await store.save(run(skill: "security-review"))
        let loaded = try await store.load()

        #expect(loaded.records.count == 1)
        #expect(loaded.records.first?.runs.map(\.skillID) == ["code-review", "security-review"])
    }

    @Test("Opakované review stejným skillem předchozí nahradí")
    func rerunningTheSameSkillReplacesTheOldResult() async throws {
        let store = store()

        try await store.save(run(findings: ["první pokus"]))
        try await store.save(run(findings: ["druhý pokus"]))
        let loaded = try await store.load()

        let record = try #require(loaded.records.first)
        #expect(record.runs.count == 1)
        #expect(record.findings.map(\.summary) == ["druhý pokus"])
    }

    @Test("Rozbitý soubor se nezamlčí")
    func anUnreadableFileIsCounted() async throws {
        // Ztracené nálezy se v UI nesmí tvářit jako „review neběželo".
        let store = store()
        try await store.save(run())
        let broken = layout.reviewFile(for: pullRequest, at: "bbbb2222")
        try Data("{tohle není JSON".utf8).write(to: broken)

        let loaded = try await store.load()

        #expect(loaded.records.count == 1)
        #expect(loaded.unreadable == 1)
    }

    // MARK: - Zastaralost

    @Test("Nový commit označí starší záznamy jako zastaralé")
    func aNewHeadShaMarksOlderRecordsStale() async throws {
        // Tvrdá podmínka: nálezy se nikdy nesmí tiše ukazovat proti kódu, který už není.
        let store = store()
        try await store.save(run(headSha: "aaaa1111"))

        try await store.save(run(headSha: "bbbb2222"))
        let loaded = try await store.load()

        let old = try #require(loaded.records.first { $0.headSha == "aaaa1111" })
        let new = try #require(loaded.records.first { $0.headSha == "bbbb2222" })
        #expect(old.isStale)
        #expect(new.isStale == false)
    }

    @Test("Zastaralé záznamy zůstávají na disku")
    func staleRecordsStayOnDisk() async throws {
        let store = store()
        try await store.save(run(headSha: "aaaa1111"))

        try await store.save(run(headSha: "bbbb2222"))
        let loaded = try await store.load()

        #expect(loaded.records.count == 2)
        #expect(loaded.records.first { $0.headSha == "aaaa1111" }?.findings.isEmpty == false)
    }

    @Test("Zastaralost umí označit i samotné dotažení detailu")
    func fetchingTheDetailAloneMarksRecordsStale() async throws {
        // Nový commit se pozná dřív, než se nad ním něco spustí.
        let store = store()
        try await store.save(run(headSha: "aaaa1111"))

        try await store.markCurrent("bbbb2222", of: pullRequest)
        let loaded = try await store.load()

        #expect(loaded.records.first?.isStale == true)
    }

    @Test("Cizí PR zastaralost nechytne")
    func anotherPullRequestIsLeftAlone() async throws {
        let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 7)
        let store = store()
        try await store.save(run(pr: other, headSha: "aaaa1111"))

        try await store.markCurrent("bbbb2222", of: pullRequest)
        let loaded = try await store.load()

        #expect(loaded.records.first { $0.pullRequest == other }?.isStale == false)
    }

    // MARK: - Úklid

    @Test("Záznam zavřeného PR zmizí až po lhůtě")
    func aClosedPullRequestIsKeptForTheRetentionPeriod() async throws {
        let store = store()
        try await store.save(run())

        try await store.cleanUp(openPullRequests: [])
        try await advance(days: 29)
        try await store.cleanUp(openPullRequests: [])
        #expect(try await store.load().records.count == 1)

        try await advance(days: 2)
        try await store.cleanUp(openPullRequests: [])
        #expect(try await store.load().records.isEmpty)
    }

    @Test("Lhůta běží od zavření, ne od stáří záznamu")
    func theClockStartsWhenThePullRequestCloses() async throws {
        // PR otevřený půl roku by jinak o historii přišel hned, jak se zavře.
        let store = store()
        try await store.save(run())

        try await advance(days: 200)
        try await store.cleanUp(openPullRequests: [pullRequest])
        try await store.cleanUp(openPullRequests: [])

        #expect(try await store.load().records.count == 1)
    }

    @Test("Otevřený PR se neuklízí")
    func anOpenPullRequestIsNeverCleanedUp() async throws {
        let store = store()
        try await store.save(run())

        try await advance(days: 400)
        try await store.cleanUp(openPullRequests: [pullRequest])

        #expect(try await store.load().records.count == 1)
    }

    @Test("PR, který se vrátil do seznamu, začíná lhůtu znovu")
    func aReturningPullRequestResetsTheClock() async throws {
        let store = store()
        try await store.save(run())

        try await store.cleanUp(openPullRequests: [])
        try await advance(days: 29)
        try await store.cleanUp(openPullRequests: [pullRequest])
        try await advance(days: 29)
        try await store.cleanUp(openPullRequests: [])

        #expect(try await store.load().records.count == 1)
    }

    @Test("Nový běh nad zavřeným PR lhůtu zruší")
    func savingAgainClearsTheClock() async throws {
        let store = store()
        try await store.save(run())
        try await store.cleanUp(openPullRequests: [])

        try await store.save(run(skill: "security-review"))
        try await advance(days: 40)
        try await store.cleanUp(openPullRequests: [])

        #expect(try await store.load().records.count == 1)
    }
}
