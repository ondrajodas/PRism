import Foundation
import Testing

@testable import PRism

@Suite("Policy.reviewState z výsledku")
struct ReviewStateFromRecordTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    private func record(
        runs: [StoredReviewRun],
        isStale: Bool = false
    ) -> ReviewRecord {
        ReviewRecord(pullRequest: pr, headSha: "aaaa1111", runs: runs, isStale: isStale)
    }

    private var blocking: ReportedFinding {
        makeReported(file: "Cart.swift", line: 13, category: "correctness", verdict: .confirmed)
    }

    // MARK: - Pořadí kritérií

    @Test("Zastaralost přebíjí všechno")
    func staleWinsOverEverything() {
        let state = Policy.reviewState(
            for: record(runs: [makeStoredRun(findings: [blocking])], isStale: true)
        )

        #expect(state == .stale)
    }

    @Test("Timeout se nesmí tvářit jako doběhlé review")
    func aTimeoutIsNotACompletedReview() {
        // Zabitý běh si nálezy nechává — ale to, že jich mohlo být víc, musí být vidět.
        let state = Policy.reviewState(
            for: record(runs: [makeStoredRun(outcome: .timedOut, findings: [blocking])])
        )

        #expect(state == .timedOut(findings: 1))
    }

    @Test("Nálezy přebíjí spadlý běh")
    func findingsWinOverAFailedRun() {
        // Odznak má říct, že je co číst; že jeden reviewer spadl, ukáže detail.
        let state = Policy.reviewState(for: record(runs: [
            makeStoredRun(skill: "code-review", findings: [blocking]),
            makeStoredRun(skill: "security-review", outcome: .failed(detail: "spadlo")),
        ]))

        #expect(state == .completed(findings: 1))
    }

    @Test("Spadlý běh bez nálezů je selhání se stderrem")
    func aFailedRunKeepsItsDetail() {
        let state = Policy.reviewState(
            for: record(runs: [makeStoredRun(outcome: .failed(detail: "Invalid API key"))])
        )

        #expect(state == .failed(detail: "Invalid API key"))
    }

    @Test("Doběhlé review bez nálezů je čisté")
    func aCleanRunIsClean() {
        #expect(Policy.reviewState(for: record(runs: [makeStoredRun()])) == .clean)
    }

    @Test("Čisté to je, jen když se z běhu dá soudit")
    func cleanRequiresAConclusiveRun() {
        // „Nic jsem nenašel" a „nemám co říct" vypadají v datech stejně a znamenají opak.
        let unreported = Policy.reviewState(
            for: record(runs: [makeStoredRun(calledReportFindings: false)])
        )
        let dropped = Policy.reviewState(for: record(runs: [makeStoredRun(droppedFindings: 1)]))

        #expect(unreported != .clean)
        #expect(dropped != .clean)
        guard case .failed(let detail) = dropped else {
            Issue.record("Očekáváno rozlišené selhání, přišlo \(dropped)")
            return
        }
        #expect(detail.contains("přečíst"))
    }

    @Test("Záznam bez běhů se tváří, že se nespouštělo")
    func anEmptyRecordLooksUnstarted() {
        #expect(Policy.reviewState(for: record(runs: [])) == .notStarted)
    }

    // MARK: - Fáze přebíjí výsledek

    @Test("Co běží, přebíjí to, co doběhlo")
    func theRunningPhaseWins() {
        let done = record(runs: [makeStoredRun(findings: [blocking])])

        #expect(Policy.reviewState(phase: .preparing, record: done, checkout: .absent) == .cloning)
        #expect(
            Policy.reviewState(phase: .running(finished: 1, total: 3), record: done, checkout: .absent)
                == .running(finished: 1, total: 3)
        )
        #expect(
            Policy.reviewState(phase: .failed(detail: "nešlo začít"), record: done, checkout: .absent)
                == .failed(detail: "nešlo začít")
        )
    }

    @Test("Bez fáze i výsledku rozhoduje pracovní kopie")
    func withoutAnythingTheCheckoutDecides() {
        #expect(Policy.reviewState(phase: nil, record: nil, checkout: .preparing) == .cloning)
        #expect(Policy.reviewState(phase: nil, record: nil, checkout: .absent) == .notStarted)
    }

    // MARK: - Který záznam je ten platný

    @Test("Aktuální záznam vyhrává nad zastaralým bez ohledu na čas")
    func theCurrentRecordBeatsAStaleOne() {
        // Historie po commitech leží na disku celá; v okně má být ten, který platí.
        let stale = ReviewRecord(
            pullRequest: pr,
            headSha: "0000dead",
            runs: [makeStoredRun(findings: [blocking])],
            isStale: true
        )
        let current = ReviewRecord(pullRequest: pr, headSha: "aaaa1111", runs: [makeStoredRun()])

        #expect(Policy.currentRecords(from: [stale, current])[pr]?.headSha == "aaaa1111")
        #expect(Policy.currentRecords(from: [current, stale])[pr]?.headSha == "aaaa1111")
    }

    @Test("Mezi zastaralými vyhrává ten novější")
    func amongStaleRecordsTheNewerWins() {
        let older = ReviewRecord(
            pullRequest: pr,
            headSha: "1111",
            runs: [makeStoredRun(finishedAt: Date(timeIntervalSince1970: 100))],
            isStale: true
        )
        let newer = ReviewRecord(
            pullRequest: pr,
            headSha: "2222",
            runs: [makeStoredRun(finishedAt: Date(timeIntervalSince1970: 200))],
            isStale: true
        )

        #expect(Policy.currentRecords(from: [older, newer])[pr]?.headSha == "2222")
        #expect(Policy.currentRecords(from: [newer, older])[pr]?.headSha == "2222")
    }

    @Test("Záznamy různých PR se nepletou")
    func recordsOfDifferentPullRequestsStayApart() {
        let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 7)
        let records = [
            ReviewRecord(pullRequest: pr, headSha: "aaaa", runs: [makeStoredRun()]),
            ReviewRecord(pullRequest: other, headSha: "bbbb", runs: [makeStoredRun()]),
        ]

        #expect(Policy.currentRecords(from: records).count == 2)
    }
}
