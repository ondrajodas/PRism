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
    failureScenario: String? = nil,
    shortSummary: String? = nil
) -> ReportedFinding {
    ReportedFinding(
        file: file,
        line: line,
        category: category,
        verdict: verdict,
        shortSummary: shortSummary,
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
    shortSummary: String? = nil,
    reviewer: String = "code-review",
    headSha: String = "aaaa1111",
    translation: FindingTranslation? = nil,
    carriedFrom: String? = nil
) -> Finding {
    Finding(
        reported: makeReported(
            file: file,
            line: line,
            category: category,
            verdict: verdict,
            summary: summary,
            failureScenario: failureScenario,
            shortSummary: shortSummary
        ),
        reviewer: reviewer,
        headSha: headSha,
        translation: translation,
        carriedFrom: carriedFrom
    )
}

/// Odmítnutí nálezů (#113) klíčované **produkční** funkcí, ne vlastním skládáním klíče —
/// jinak by testy ověřovaly svoji kopii pravidla místo toho pravidla.
func makeDismissals(
    _ findings: [Finding],
    reason: FindingDismissal.Reason = .invalid,
    at date: Date = Date(timeIntervalSince1970: 1_000_000)
) -> [FindingKey: FindingDismissal] {
    Dictionary(
        uniqueKeysWithValues: findings.map {
            (Policy.key(of: $0), FindingDismissal(reason: reason, dismissedAt: date))
        }
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
    finishedAt: Date = Date(timeIntervalSince1970: 1_000_000),
    timeline: StoredTimeline? = nil,
    sessionID: String? = nil,
    usage: RunUsage? = nil,
    increment: IncrementalReviewOutcome? = nil
) -> StoredReviewRun {
    var summary = StreamSummary()
    summary.sessionID = sessionID
    summary.findings = findings
    summary.calledReportFindings = calledReportFindings
    summary.droppedFindings = droppedFindings
    summary.usage = usage

    var run = ReviewRun(
        key: ReviewRunKey(
            pullRequest: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42),
            headSha: headSha,
            skillID: skill
        ),
        summary: summary,
        outcome: outcome
    )
    // Přírůstek (#517) jde do běhu **tou cestou, jakou vzniká doopravdy** — přes `ReviewRun`,
    // takže se přenesené nálezy do uloženého běhu složí `StoredReviewRun.init`, ne test.
    run.increment = increment
    return StoredReviewRun(run, finishedAt: finishedAt, timeline: timeline)
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
