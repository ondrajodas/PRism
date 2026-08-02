import Foundation

/// `ReviewRunning` nad `claude` CLI.
///
/// Jeden běh = jedna headless session na jeden skill v jednom pracovním stromě. Stream se
/// čte průběžně, takže zabitý běh si nálezy, které stihl vypsat, **nechá** — a UI ví
/// o postupu dřív, než session skončí.
struct ClaudeReviewRunner: ReviewRunning {
    /// Patnáct minut. Delší běh už nedává smysl hlídat: buď se reviewer zacyklil, nebo
    /// analyzuje něco, na co se stejně nedá čekat u otevřeného okna.
    static let defaultTimeout = Duration.seconds(15 * 60)
    /// Tři souběžné session. Víc zahltí stroj i účet; konfigurovatelné to bude v #23.
    static let defaultConcurrency = 3

    private let claude: URL
    private let gh: URL
    private let runner: any ProcessStreaming
    private let timeout: Duration
    private let parser = StreamParser()
    /// Stejný klíč se nespouští dvakrát — souběžný požadavek se k běžícímu **připojí**.
    private let coordinator = WorkCoordinator()
    private let slots: ReviewSlots
    /// Volba modelu z konfigurace; `nil` = ten, který si `claude` zvolí sám.
    private let model: @Sendable () -> String?

    init(
        claude: URL,
        gh: URL,
        runner: any ProcessStreaming,
        timeout: Duration = ClaudeReviewRunner.defaultTimeout,
        maxConcurrent: @escaping @Sendable () -> Int = { ClaudeReviewRunner.defaultConcurrency },
        model: @escaping @Sendable () -> String? = { nil }
    ) {
        self.claude = claude
        self.gh = gh
        self.runner = runner
        self.timeout = timeout
        slots = ReviewSlots(limit: maxConcurrent)
        self.model = model
    }

    /// Slučování je **nad** frontou schválně: připojený požadavek nesmí zabrat druhý slot,
    /// když už jeden drží běh, na který čeká.
    /// Po zvýšení limitu se čekatelé musí pustit dál — sami se nevzbudí.
    func configurationChanged() async {
        await slots.admitWaiting()
    }

    func run(
        _ request: ReviewRequest,
        progress: @escaping ReviewProgressHandler
    ) async throws -> ReviewRun {
        try await coordinator.run(key: request.key.description, kind: "review") {
            progress(.queued)
            return try await slots.withSlot {
                try await execute(request, progress: progress)
            }
        }
    }

    private func execute(
        _ request: ReviewRequest,
        progress: @escaping ReviewProgressHandler
    ) async throws -> ReviewRun {
        var summary = StreamSummary()
        var exit: (code: Int32, standardError: String)?

        let events = runner.stream(
            claude,
            arguments: ClaudeCommand.arguments(prompt: ClaudeCommand.prompt(for: request), model: model()),
            environment: ClaudeCommand.environment(gh: gh),
            workingDirectory: request.worktree,
            timeout: timeout
        )

        do {
            for try await event in events {
                switch event {
                case .line(let line):
                    consume(line, into: &summary, reportingTo: progress)
                case .finished(let code, let standardError):
                    exit = (code, standardError)
                }
            }
        } catch ProcessError.timedOut {
            // Částečné nálezy zůstávají — kvůli tomu se stream čte průběžně.
            return ReviewRun(key: request.key, summary: summary, outcome: .timedOut)
        } catch ProcessError.launchFailed(let detail) {
            return ReviewRun(key: request.key, summary: summary, outcome: .failed(detail: detail))
        }

        // Zrušený proud skončí **bez chyby**, takže bez téhle kontroly by ze zrušeného
        // review vypadl výsledek, jako by doběhlo.
        try Task.checkCancellation()

        return ReviewRun(key: request.key, summary: summary, outcome: Self.outcome(of: exit))
    }

    /// Průběh se hlásí z rozdílu proti stavu před řádkem. Parser sám nic neoznamuje —
    /// je to čistý překlad textu na data a takový má zůstat.
    private func consume(
        _ line: String,
        into summary: inout StreamSummary,
        reportingTo progress: ReviewProgressHandler
    ) {
        let hadSession = summary.sessionID != nil
        let tools = summary.attemptedTools.count
        let findings = summary.findings.count

        parser.consume(line, into: &summary)

        if !hadSession, let sessionID = summary.sessionID {
            progress(.started(sessionID: sessionID))
        }
        for tool in summary.attemptedTools[tools...] {
            progress(.attemptedTool(tool))
        }
        if summary.findings.count != findings {
            progress(.findings(count: summary.findings.count))
        }
    }

    private static func outcome(of exit: (code: Int32, standardError: String)?) -> ReviewRunOutcome {
        // Proud vždycky končí buď událostí o konci procesu, nebo chybou. Že by nedorazilo
        // ani jedno, znamená chybu v implementaci `ProcessStreaming` — ohlásit se to ale
        // musí líp než tím, že se běh bude tvářit jako úspěšný.
        guard let exit else { return .failed(detail: "Session skončila bez výsledku.") }
        guard exit.code != 0 else { return .finished }

        let detail = exit.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(
            detail: detail.isEmpty ? "Session skončila návratovým kódem \(exit.code)." : detail
        )
    }
}
