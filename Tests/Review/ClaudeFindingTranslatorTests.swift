import Foundation
import Testing

@testable import PRism

/// Překlad nálezů proti fake procesu. Ověřuje hlavně to, co se u překladu nesmí stát:
/// **ztratit nález**.
@Suite("ClaudeFindingTranslator")
struct ClaudeFindingTranslatorTests {
    private let claude = URL(filePath: "/usr/local/bin/claude")

    private func finding(_ summary: String) -> ReportedFinding {
        ReportedFinding(
            file: "Cart.swift",
            line: 13,
            category: "correctness",
            verdict: .confirmed,
            shortSummary: nil,
            summary: summary,
            failureScenario: nil
        )
    }

    private func translator(_ runner: FakeProcessRunner) -> ClaudeFindingTranslator {
        ClaudeFindingTranslator(claude: claude, runner: runner)
    }

    @Test("Přeložené texty dorazí")
    func returnsTranslations() async throws {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: #"[{"id": 0, "summary": "Celkovka ignoruje množství"}]"#
        )

        let translations = try await translator(runner).translate([finding("Total ignores quantity")], to: .czech)

        #expect(translations.map { $0?.summary } == ["Celkovka ignoruje množství"])
    }

    /// Selhání překladu **není** selhání review. Nálezy dorazily a jsou uložené;
    /// nepřeložené se ukážou v originále.
    @Test("Nenulový kód nechá nálezy nepřeložené, ale nevyhodí chybu")
    func aFailedSessionLeavesTheOriginals() async throws {
        let runner = FakeProcessRunner(exitCode: 1, standardError: "Invalid API key")

        let translations = try await translator(runner).translate(
            [finding("A"), finding("B")],
            to: .czech
        )

        #expect(translations == [nil, nil])
    }

    /// Záruka „selhání překladu není selhání review“ nesmí viset na tom, že si volající
    /// vzpomene na `try?`. Nespuštěná binárka i timeout se zachytávají tady.
    @Test("Nespuštěný claude nevyhodí chybu ven")
    func aFailedLaunchDoesNotThrow() async throws {
        let runner = FakeProcessRunner(failing: .launchFailed("claude nejde spustit"))

        let translations = try await translator(runner).translate([finding("A")], to: .czech)

        #expect(translations == [nil])
    }

    @Test("Rozbitá odpověď nechá nálezy nepřeložené")
    func garbageLeavesTheOriginals() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "Promiňte, nerozumím.")

        let translations = try await translator(runner).translate([finding("A")], to: .czech)

        #expect(translations == [nil])
    }

    /// Bez nálezů se nemá co překládat — volat kvůli tomu model by byla session za nic.
    @Test("Prázdný seznam nespustí nic")
    func doesNotRunForNothing() async throws {
        let runner = FakeProcessRunner(exitCode: 0)

        let translations = try await translator(runner).translate([], to: .czech)

        #expect(translations.isEmpty)
        #expect(runner.invocations.isEmpty)
    }

    @Test("Volá se claude s prázdnou sadou nástrojů")
    func invokesClaudeWithoutTools() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")

        _ = try await translator(runner).translate([finding("A")], to: .czech)

        let invocation = try #require(runner.invocations.first)
        #expect(invocation.executable == claude)
        #expect(invocation.arguments.contains("--allowedTools"))
        #expect(invocation.arguments.contains(ClaudeCommand.disallowedTools))
    }
}
