import Foundation
import Testing

@testable import PRism

@Suite("ReviewRecord")
struct ReviewRecordTests {
    private let pullRequest = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    private func storedRun(
        skill: String,
        outcome: ReviewRunOutcome = .finished,
        findings: [String] = []
    ) -> StoredReviewRun {
        var summary = StreamSummary()
        summary.findings = findings.map {
            ReportedFinding(
                file: nil,
                line: nil,
                category: nil,
                verdict: nil,
                shortSummary: nil,
                summary: $0,
                failureScenario: nil
            )
        }
        let run = ReviewRun(
            key: ReviewRunKey(pullRequest: pullRequest, headSha: "aaaa1111", skillID: skill),
            summary: summary,
            outcome: outcome
        )
        return StoredReviewRun(run, finishedAt: Date(timeIntervalSince1970: 1_000_000))
    }

    @Test("Záznam přežije round-trip", arguments: [
        ReviewRunOutcome.finished,
        .timedOut,
        .failed(detail: "Invalid API key"),
    ])
    func aRecordSurvivesTheRoundTrip(outcome: ReviewRunOutcome) throws {
        // Každý případ zvlášť: `failed` nese asociovanou hodnotu a ta se z JSONu ztratí
        // nejtišeji ze všech.
        let record = ReviewRecord(
            pullRequest: pullRequest,
            headSha: "aaaa1111",
            runs: [storedRun(skill: "code-review", outcome: outcome, findings: ["nález"])],
            isStale: true,
            closedAt: Date(timeIntervalSince1970: 2_000_000)
        )

        #expect(try roundTrip(record) == record)
    }

    @Test("Prázdný záznam se pozná od zavřeného")
    func anEmptyRecordIsNotAClosedOne() throws {
        // `closedAt` je optional a `nil` musí přežít — jinak by se lhůta na úklid rozjela
        // hned po prvním načtení.
        let record = ReviewRecord(pullRequest: pullRequest, headSha: "aaaa1111")

        #expect(try roundTrip(record).closedAt == nil)
    }

    @Test("Nový skill se přidá, stejný se nahradí")
    func replacingKeepsOneRunPerSkill() {
        var record = ReviewRecord(pullRequest: pullRequest, headSha: "aaaa1111")

        record.replace(storedRun(skill: "code-review", findings: ["první"]))
        record.replace(storedRun(skill: "security-review"))
        record.replace(storedRun(skill: "code-review", findings: ["druhý"]))

        #expect(record.runs.map(\.skillID) == ["code-review", "security-review"])
        #expect(record.runs.first?.findings.map(\.summary) == ["druhý"])
    }

    @Test("Nálezy se skládají ze všech reviewerů, ale neslučují")
    func findingsComeFromEveryReviewer() {
        // Nesouhlas dvou reviewerů je informace — texty se nikdy neslévají.
        var record = ReviewRecord(pullRequest: pullRequest, headSha: "aaaa1111")
        record.replace(storedRun(skill: "code-review", findings: ["stejný text"]))
        record.replace(storedRun(skill: "security-review", findings: ["stejný text"]))

        #expect(record.findings.count == 2)
        #expect(record.findings.map(\.reviewer) == ["code-review", "security-review"])
    }
}
