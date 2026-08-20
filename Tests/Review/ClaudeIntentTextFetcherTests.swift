import Foundation
import Testing

@testable import PRism

/// Dotažení textu issue jako podproces (#345).
///
/// Nejcennější tvrzení jsou tady dvě a obě jsou o tom, co se **nestane**: session se nepustí, když
/// není na co se ptát, a selhání procesu se nespolkne — nese si důvod dál. `try?` by z chybějící
/// binárky udělal „issue nic neříká“.
@Suite("ClaudeIntentTextFetcher (#345)")
struct ClaudeIntentTextFetcherTests {
    private static let claude = URL(filePath: "/opt/homebrew/bin/claude")
    private static let tool = "mcp__claude_ai_Linear__get_issue"
    private static let link = IntentLink(
        id: "AJDA-3003",
        url: URL(string: "https://linear.app/keboola/issue/AJDA-3003")!
    )

    private func fetcher(_ runner: FakeProcessRunner) -> ClaudeIntentTextFetcher {
        ClaudeIntentTextFetcher(claude: Self.claude, runner: runner)
    }

    /// **Bez odkazů se nespouští nic.** Boot session je reálné peníze (~$0,2), takže běh za nic
    /// není jen neefektivita.
    @Test("Bez odkazů se session nepustí")
    func runsNothingWithoutLinks() async throws {
        let runner = FakeProcessRunner(exitCode: 0)

        let result = try await fetcher(runner).fetchText(of: [], using: Self.tool)

        #expect(runner.invocations.isEmpty)
        #expect(result == IntentTextResult())
    }

    /// Selhání procesu **nese důvod dál**, aby se od „issue nic neříká“ dalo odlišit.
    @Test("Nespuštěná binárka je sessionFailed, ne prázdný výsledek")
    func reportsALaunchFailure() async throws {
        let runner = FakeProcessRunner(failing: .launchFailed("claude se nenašel"))

        let result = try await fetcher(runner).fetchText(of: [Self.link], using: Self.tool)

        #expect(result.gap == .sessionFailed(detail: "claude se nenašel"))
        #expect(result.issues.isEmpty)
    }

    /// Timeout má **vlastní větu**, ne `localizedDescription` z `ProcessError` — z toho by
    /// v okně stálo „The operation couldn't be completed“.
    @Test("Timeout se pojmenuje česky")
    func reportsATimeout() async throws {
        let runner = FakeProcessRunner(failing: .timedOut)

        let result = try await fetcher(runner).fetchText(of: [Self.link], using: Self.tool)

        #expect(result.gap == .sessionFailed(detail: "vypršel čas"))
    }

    /// **Exit kód sám nerozhoduje** a je to změřené: server, který se nespustil, skončí jedničkou,
    /// ale pravda je v `init` eventu — a text, který v odpovědi je, se přesto vzít nesmí.
    @Test("Nenulový exit kód rozbor streamu nepřeskočí")
    func parsesTheStreamEvenAfterANonZeroExit() async throws {
        let stream = try Fixture.text("stream-json/intent-server-failed.jsonl")
        let runner = FakeProcessRunner(exitCode: 1, standardOutput: stream)

        let result = try await fetcher(runner).fetchText(of: [Self.link], using: "mcp__linear__get_issue")

        #expect(result.gap == .serverUnavailable(status: "failed"))
    }

    /// Argumenty jdou do procesu **z `IntentTextCommand`**, ne se skládají tady — jinak by byly dvě
    /// pravdy o tom, s jakými povoleními session běží.
    @Test("Session se pouští s argumenty z IntentTextCommand")
    func passesTheCommandArguments() async throws {
        let runner = FakeProcessRunner(exitCode: 0)

        _ = try await fetcher(runner).fetchText(of: [Self.link], using: Self.tool)

        let invocation = try #require(runner.invocations.first)
        #expect(invocation.executable == Self.claude)
        #expect(invocation.arguments == IntentTextCommand.arguments(
            prompt: IntentTextCommand.prompt(for: [Self.link], tool: Self.tool),
            tool: Self.tool
        ))
    }
}
