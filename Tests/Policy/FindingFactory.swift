import Foundation

@testable import PRism

/// Nálezy a běhy na jeden řádek, ať je v testech vidět jen to, na čem záleží.
///
/// `Policy` se netestuje proti mockům — jsou to čisté funkce. Tohle není fake, jen zkratka
/// pro data.
func makeReported(
    file: String? = nil,
    line: Int? = nil,
    category: String? = "correctness",
    verdict: FindingVerdict? = .confirmed,
    summary: String = "nález",
    failureScenario: String? = nil
) -> ReportedFinding {
    ReportedFinding(
        file: file,
        line: line,
        category: category,
        verdict: verdict,
        shortSummary: nil,
        summary: summary,
        failureScenario: failureScenario
    )
}

func makeFinding(
    file: String? = nil,
    line: Int? = nil,
    category: String? = "correctness",
    verdict: FindingVerdict? = .confirmed,
    summary: String = "nález",
    failureScenario: String? = nil,
    reviewer: String = "code-review",
    headSha: String = "aaaa1111"
) -> Finding {
    Finding(
        reported: makeReported(
            file: file,
            line: line,
            category: category,
            verdict: verdict,
            summary: summary,
            failureScenario: failureScenario
        ),
        reviewer: reviewer,
        headSha: headSha
    )
}

/// Uložený běh se staví přes `ReviewRun`, tedy tou cestou, kterou vzniká i doopravdy —
/// vlastní init jen pro testy by dovolil poskládat stav, do kterého se aplikace nedostane.
func makeStoredRun(
    skill: String = "code-review",
    outcome: ReviewRunOutcome = .finished,
    findings: [ReportedFinding] = [],
    calledReportFindings: Bool = true,
    droppedFindings: Int = 0,
    headSha: String = "aaaa1111",
    finishedAt: Date = Date(timeIntervalSince1970: 1_000_000)
) -> StoredReviewRun {
    var summary = StreamSummary()
    summary.findings = findings
    summary.calledReportFindings = calledReportFindings
    summary.droppedFindings = droppedFindings

    let run = ReviewRun(
        key: ReviewRunKey(
            pullRequest: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42),
            headSha: headSha,
            skillID: skill
        ),
        summary: summary,
        outcome: outcome
    )
    return StoredReviewRun(run, finishedAt: finishedAt)
}

func makeRecord(
    runs: [StoredReviewRun],
    isStale: Bool = false,
    headSha: String = "aaaa1111"
) -> ReviewRecord {
    ReviewRecord(
        pullRequest: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42),
        headSha: headSha,
        runs: runs,
        isStale: isStale
    )
}
