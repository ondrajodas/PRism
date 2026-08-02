import Foundation

@testable import PRism

/// Reviewer, který nic nespouští — vrátí, co si test předepsal, a pamatuje si zadání.
///
/// Umí běh **pozdržet**, aby šlo zkontrolovat stav „běží“ a zrušení. Čeká se točením přes
/// `Task.yield()`, ne na continuation: zrušený běh musí z čekání vypadnout sám, jinak by
/// test na cancel visel místo aby spadl.
final class FakeReviewRunner: ReviewRunning, @unchecked Sendable {
    private let outcome: ReviewRunOutcome
    private let findings: [ReportedFinding]
    private let calledReportFindings: Bool
    private let failure: (any Error)?
    private let holds: Bool
    /// Co běh nahlásí jako průběh. Prázdné u testů, které se na časovou osu neptají —
    /// samotné `.queued` hlásí runner vždycky.
    private let reported: [ReviewProgress]
    private let lock = NSLock()
    private var recorded: [ReviewRequest] = []
    private var released = false

    init(
        outcome: ReviewRunOutcome = .finished,
        findings: [ReportedFinding] = [],
        calledReportFindings: Bool = true,
        failing failure: (any Error)? = nil,
        holdsUntilRelease: Bool = false,
        progress reported: [ReviewProgress] = []
    ) {
        self.outcome = outcome
        self.findings = findings
        self.calledReportFindings = calledReportFindings
        self.failure = failure
        holds = holdsUntilRelease
        self.reported = reported
    }

    var requests: [ReviewRequest] { lock.withLock { recorded } }

    func releaseAll() { lock.withLock { released = true } }

    func waitForStarts(_ count: Int) async {
        while requests.count < count { await Task.yield() }
    }

    func run(
        _ request: ReviewRequest,
        progress: @escaping ReviewProgressHandler
    ) async throws -> ReviewRun {
        lock.withLock { recorded.append(request) }
        // `.queued` hlásí skutečný runner **vždycky**, i když je slot volný hned. Fake,
        // který ho u vlastního seznamu vynechá, by pouštěl testy popisující průběh, jaký
        // v provozu nevznikne.
        progress(.queued)
        for event in reported { progress(event) }

        while holds, !isReleased, !Task.isCancelled { await Task.yield() }
        try Task.checkCancellation()
        if let failure { throw failure }

        var summary = StreamSummary()
        summary.sessionID = "session-\(request.key.skillID)"
        summary.calledReportFindings = calledReportFindings
        summary.findings = findings
        return ReviewRun(key: request.key, summary: summary, outcome: outcome)
    }

    private var isReleased: Bool { lock.withLock { released } }
}
