import Foundation
import Testing

@testable import PRism

@Suite("ClaudeReviewRunner")
struct ClaudeReviewRunnerTests {
    private let claude = URL(filePath: "/usr/local/bin/claude")
    private let gh = URL(filePath: "/opt/homebrew/bin/gh")

    private func request(
        skill: String = "code-review",
        pr number: Int = 42,
        headSha: String = "aaaa1111"
    ) -> ReviewRequest {
        ReviewRequest(
            key: ReviewRunKey(
                pullRequest: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: number),
                headSha: headSha,
                skillID: skill
            ),
            worktree: URL(filePath: "/tmp/prism/worktrees/cli/cli/\(number)-\(headSha)"),
            baseSha: "bbbb2222"
        )
    }

    private func lines(of fixture: String) throws -> [String] {
        try Fixture.text("stream-json/\(fixture).jsonl")
            .split(separator: "\n")
            .map(String.init)
    }

    private func runner(
        _ streamer: FakeProcessStreamer,
        maxConcurrent: Int = 3
    ) -> ClaudeReviewRunner {
        ClaudeReviewRunner(claude: claude, gh: gh, runner: streamer, maxConcurrent: { maxConcurrent })
    }

    // MARK: - Výsledek běhu

    @Test("Z úspěšného běhu vypadnou nálezy i session id")
    func aSuccessfulRunYieldsFindings() async throws {
        let streamer = FakeProcessStreamer(lines: try lines(of: "review-with-findings"))

        let run = try await runner(streamer).run(request())

        #expect(run.outcome == .finished)
        #expect(run.findings.count == 4)
        #expect(run.sessionID?.isEmpty == false)
        #expect(run.summary.calledReportFindings)
        // Nález nese, kdo ho našel a proti čemu — to ve streamu není a vědět to může jen
        // aplikace.
        let first = try #require(run.findings.first)
        #expect(first.reviewer == "code-review")
        #expect(first.headSha == "aaaa1111")
    }

    @Test("Doběhlá session bez nálezů není selhání")
    func aCleanRunIsNotAFailure() async throws {
        // `clean` a `failed` říkají opak jedno o druhém — kdyby se slily, schválil by se PR
        // s neohlášenou chybou.
        let streamer = FakeProcessStreamer(lines: try lines(of: "review-clean"))

        let run = try await runner(streamer).run(request())

        #expect(run.outcome == .finished)
        #expect(run.findings.isEmpty)
        #expect(run.summary.calledReportFindings)
    }

    @Test("Nenulový kód je selhání a stderr se uchová")
    func aNonZeroExitFails() async throws {
        let streamer = FakeProcessStreamer(
            [.output(lines: [], exitCode: 1, standardError: "Invalid API key\n")]
        )

        let run = try await runner(streamer).run(request())

        #expect(run.outcome == .failed(detail: "Invalid API key"))
    }

    @Test("Selhání bez stderru vysvětlí aspoň návratový kód")
    func aSilentFailureStillSaysSomething() async throws {
        let streamer = FakeProcessStreamer([.output(lines: [], exitCode: 127)])

        let run = try await runner(streamer).run(request())

        #expect(run.outcome == .failed(detail: "Session skončila návratovým kódem 127."))
    }

    @Test("Nespuštěná binárka je selhání běhu, ne chyba volání")
    func aFailedLaunchIsAFailedRun() async throws {
        let streamer = FakeProcessStreamer([.launchFailure("claude nejde spustit")])

        let run = try await runner(streamer).run(request())

        #expect(run.outcome == .failed(detail: "claude nejde spustit"))
    }

    @Test("Timeout zachová nálezy, které do té doby dorazily")
    func aTimeoutKeepsPartialFindings() async throws {
        // Zabitý běh nemá `result` event (ověřeno u #12) — nálezy z něj tedy nemá kdo
        // potvrdit a jediné, co po něm zbylo, je to, co stihl vypsat.
        let streamer = FakeProcessStreamer(
            [.timeout(after: try lines(of: "review-with-findings"))]
        )

        let run = try await runner(streamer).run(request())

        #expect(run.outcome == .timedOut)
        #expect(run.findings.count == 4)
    }

    // MARK: - Volání `claude`

    @Test("Session běží ve worktree a s ověřenými flagy")
    func theInvocationMatchesTheVerifiedCommand() async throws {
        let streamer = FakeProcessStreamer(lines: try lines(of: "review-clean"))
        let target = request()

        _ = try await runner(streamer).run(target)

        let invocation = try #require(streamer.invocations.first)
        #expect(invocation.executable == claude)
        #expect(invocation.workingDirectory == target.worktree)
        #expect(invocation.arguments.contains("--verbose"))
        #expect(invocation.arguments.contains("stream-json"))
        #expect(invocation.arguments.contains(ClaudeCommand.allowedTools))
        #expect(invocation.environment["GIT_TERMINAL_PROMPT"] == "0")
    }

    // MARK: - Průběh

    @Test("Průběh chodí ven, jak stream přichází")
    func progressArrivesWhileTheStreamRuns() async throws {
        let streamer = FakeProcessStreamer(lines: try lines(of: "review-with-findings"))
        let collected = Collector()

        _ = try await runner(streamer).run(request()) { collected.append($0) }

        let events = collected.events
        #expect(events.first == .queued)
        #expect(events.contains { if case .started = $0 { true } else { false } })
        #expect(events.contains { event in
            guard case .attemptedTool(let tool) = event else { return false }
            return tool.name == "ReportFindings"
        })
        #expect(events.last == .findings(count: 4))
    }

    // MARK: - Souběh a slučování

    @Test("Nad limit souběhu se běhy zařadí do fronty")
    func runsOverTheLimitWaitInLine() async throws {
        let streamer = FakeProcessStreamer(
            [.output(lines: try lines(of: "review-clean"))],
            holdsUntilRelease: true
        )
        let runner = runner(streamer, maxConcurrent: 3)

        let runs = (1...4).map { number in
            Task { try await runner.run(self.request(pr: number)) }
        }

        await streamer.waitForStarts(3)
        // Čtvrtý běh by se při rozbitém limitu rozjel spolu s ostatními; odmlka mu na to dá
        // příležitost.
        await settle()
        #expect(streamer.startedCount == 3)

        streamer.releaseAll()
        for run in runs { _ = try await run.value }

        #expect(streamer.startedCount == 4)
        #expect(streamer.peakConcurrency == 3)
    }

    @Test("Stejný klíč se nespustí dvakrát")
    func theSameKeyRunsOnce() async throws {
        let streamer = FakeProcessStreamer(
            [.output(lines: try lines(of: "review-with-findings"))],
            holdsUntilRelease: true
        )
        let runner = runner(streamer)
        let target = request()

        let first = Task { try await runner.run(target) }
        await streamer.waitForStarts(1)
        let second = Task { try await runner.run(target) }
        await settle()

        streamer.releaseAll()
        let results = try await (first.value, second.value)

        // Druhý požadavek se připojil k běžícímu — jeden proces, dva stejné výsledky.
        #expect(streamer.invocations.count == 1)
        #expect(results.0 == results.1)
    }

    @Test("Zrušení běh ukončí a session zabije")
    func cancellingStopsTheSession() async throws {
        let streamer = FakeProcessStreamer(
            [.output(lines: try lines(of: "review-clean"))],
            holdsUntilRelease: true
        )
        let runner = runner(streamer)

        let run = Task { try await runner.run(request()) }
        await streamer.waitForStarts(1)
        run.cancel()

        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(streamer.cancellationCount == 1)
    }
}

/// Sběrač událostí o průběhu. Handler je `@Sendable` a volá se z běžícího tasku, takže
/// zámek, ne pole v testu.
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ReviewProgress] = []

    var events: [ReviewProgress] { lock.withLock { recorded } }

    func append(_ event: ReviewProgress) { lock.withLock { recorded.append(event) } }
}
