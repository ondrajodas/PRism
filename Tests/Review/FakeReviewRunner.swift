import Foundation
import Testing

@testable import PRism

/// Reviewer, který nic nespouští — vrátí, co si test předepsal, a pamatuje si zadání.
///
/// Umí běh **pozdržet**, aby šlo zkontrolovat stav „běží“ a zrušení. Drží se **odmlkami**, ne na
/// continuation: zrušený běh musí z čekání vypadnout sám, jinak by test na cancel visel místo aby
/// spadl. Odmlka místo `Task.yield()` je z #296 — spin bere procesor ostatním suitám.
final class FakeReviewRunner: ReviewRunning, @unchecked Sendable {
    private let outcome: ReviewRunOutcome
    private let findings: [ReportedFinding]
    private let calledReportFindings: Bool
    private let failure: (any Error)?
    private let holds: Bool
    /// Co běh nahlásí jako cenu (#148). Výchozí `nil` je „cenu nenahlásil“, tedy stav zabitého
    /// běhu — testy, které o útratu nestojí, tím nic netvrdí.
    private let usage: RunUsage?
    /// Co běh nahlásí jako průběh. Prázdné u testů, které se na časovou osu neptají —
    /// samotné `.queued` hlásí runner vždycky.
    private let reported: [ReviewProgress]
    /// Co běh nahlásí **až po tom, co ho test pustí** (#308). Bez toho se všechen průběh hlásí
    /// dřív, než se běh dá pozdržet, takže se nedá vyzkoušet událost, která dorazí až po nějakém
    /// mezitím proběhlém tiku pollingu — a to je zrovna ta situace, ve které se osa nesmí ztratit.
    private let reportedAfterRelease: [ReviewProgress]
    /// Poslední sdělení session, tedy `result` event (#150). `nil` = nedorazil, což je stav
    /// zabitého běhu — kontrola nálezů z něj nevyčte nic, a to je správná odpověď.
    private let resultText: String?
    private let lock = NSLock()
    private var recorded: [ReviewRequest] = []
    private var released = false

    init(
        outcome: ReviewRunOutcome = .finished,
        findings: [ReportedFinding] = [],
        calledReportFindings: Bool = true,
        failing failure: (any Error)? = nil,
        holdsUntilRelease: Bool = false,
        usage: RunUsage? = nil,
        progress reported: [ReviewProgress] = [],
        progressAfterRelease reportedAfterRelease: [ReviewProgress] = [],
        resultText: String? = nil
    ) {
        self.outcome = outcome
        self.findings = findings
        self.calledReportFindings = calledReportFindings
        self.failure = failure
        self.usage = usage
        holds = holdsUntilRelease
        self.reported = reported
        self.reportedAfterRelease = reportedAfterRelease
        self.resultText = resultText
    }

    var requests: [ReviewRequest] { lock.withLock { recorded } }

    func releaseAll() { lock.withLock { released = true } }

    func waitForStarts(_ count: Int) async {
        await waitUntil("rozběhne se \(count) běhů") { self.requests.count >= count }
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

        // Držení, ne čekání na jev — proto bez stropu, ale s odmlkou.
        while holds, !isReleased, !Task.isCancelled { await TestWait.pause() }
        try Task.checkCancellation()
        // Až za kontrolou zrušení: zrušený běh nemá co hlásit, hlásit průběh po `cancel` by
        // z fake udělalo jediného aktéra, který to dělá.
        for event in reportedAfterRelease { progress(event) }
        if let failure { throw failure }

        var summary = StreamSummary()
        summary.sessionID = "session-\(request.key.skillID)"
        summary.calledReportFindings = calledReportFindings
        summary.findings = findings
        summary.usage = usage
        if let resultText {
            summary.outcome = ReviewOutcome(isError: false, subtype: "success", text: resultText)
        }
        return ReviewRun(key: request.key, summary: summary, outcome: outcome)
    }

    private var isReleased: Bool { lock.withLock { released } }
}
