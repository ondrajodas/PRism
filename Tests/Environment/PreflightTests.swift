import Foundation
import Testing

@testable import PRism

@Suite("Preflight")
struct PreflightTests {
    @Test("Když je všechno v pořádku, vydá cesty k binárkám")
    func readyWhenAllToolsFoundAndGhLoggedIn() async {
        let report = await run(onDisk: KnownPath.all, ghExitCode: 0)

        #expect(report.problems.isEmpty)
        #expect(report.toolPaths?.gh.path(percentEncoded: false) == KnownPath.gh)
        #expect(report.toolPaths?.git.path(percentEncoded: false) == KnownPath.git)
        #expect(report.toolPaths?.claude.path(percentEncoded: false) == KnownPath.claude)
    }

    @Test("Chybějící nástroj blokuje a cesty nevzniknou")
    func blocksWhenToolIsMissing() async {
        let report = await run(onDisk: [KnownPath.gh, KnownPath.git], ghExitCode: 0)

        #expect(report.problems == [.binaryMissing(.claude)])
        #expect(report.toolPaths == nil)
    }

    @Test("Nepřihlášené gh blokuje")
    func blocksWhenGhIsLoggedOut() async {
        let report = await run(onDisk: KnownPath.all, ghExitCode: 1)

        #expect(report.problems == [.ghLoggedOut])
        #expect(report.toolPaths == nil)
    }

    @Test("Selhaná kontrola přihlášení blokuje zvlášť od nepřihlášení")
    func blocksWithDetailWhenAuthCheckFails() async {
        let report = await run(
            onDisk: KnownPath.all,
            runner: FakeProcessRunner(failing: .launchFailed("Permission denied"))
        )

        #expect(report.problems == [.ghAuthCheckFailed("Permission denied")])
        #expect(report.toolPaths == nil)
    }

    @Test("Když gh chybí, na přihlášení se vůbec neptá")
    func skipsAuthCheckWhenGhIsMissing() async {
        let runner = FakeProcessRunner(exitCode: 0)

        let report = await run(onDisk: [KnownPath.git, KnownPath.claude], runner: runner)

        #expect(report.ghAuth == nil)
        #expect(report.problems == [.binaryMissing(.gh)])
        #expect(runner.invocations.isEmpty)
    }

    @Test("Problémy vypisuje v pevném pořadí")
    func listsProblemsInStableOrder() async {
        let report = await run(onDisk: [], ghExitCode: 0)

        #expect(
            report.problems == [
                .binaryMissing(.gh),
                .binaryMissing(.git),
                .binaryMissing(.claude),
            ]
        )
    }

    private func run(onDisk paths: [String], ghExitCode: Int32) async -> PreflightReport {
        await run(onDisk: paths, runner: FakeProcessRunner(exitCode: ghExitCode))
    }

    private func run(onDisk paths: [String], runner: FakeProcessRunner) async -> PreflightReport {
        let preflight = Preflight(
            locator: BinaryLocator(
                probe: FakeExecutableProbe(paths),
                shellPath: FakeShellPathReader()
            ),
            authCheck: GhAuthCheck(runner: runner)
        )
        return await preflight.run()
    }
}
