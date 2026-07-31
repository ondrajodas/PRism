import Foundation
import Testing

@testable import PRism

@Suite("GhAuthCheck")
struct GhAuthCheckTests {
    private let gh = URL(filePath: KnownPath.gh)

    @Test("Nulový exit kód znamená přihlášeno")
    func loggedInOnExitZero() async {
        let state = await GhAuthCheck(runner: FakeProcessRunner(exitCode: 0)).check(gh: gh)

        #expect(state == .loggedIn)
    }

    @Test("Exit kód 1 znamená nepřihlášeno")
    func loggedOutOnExitOne() async {
        let runner = FakeProcessRunner(
            exitCode: 1,
            standardOutput: "You are not logged into any GitHub hosts."
        )

        let state = await GhAuthCheck(runner: runner).check(gh: gh)

        #expect(state == .loggedOut)
    }

    @Test("Ptá se přes gh auth status na zadané binárce")
    func runsAuthStatusOnGivenBinary() async {
        let runner = FakeProcessRunner(exitCode: 0)

        _ = await GhAuthCheck(runner: runner).check(gh: gh)

        #expect(runner.invocations == [.init(executable: gh, arguments: ["auth", "status"])])
    }

    @Test("Neočekávaný exit kód nese stderr")
    func checkFailedCarriesStandardError() async {
        let runner = FakeProcessRunner(exitCode: 2, standardError: "dyld: chybí knihovna\n")

        let state = await GhAuthCheck(runner: runner).check(gh: gh)

        #expect(state == .checkFailed("dyld: chybí knihovna"))
    }

    @Test("Když stderr mlčí, vezme stdout")
    func checkFailedFallsBackToStandardOutput() async {
        let runner = FakeProcessRunner(exitCode: 2, standardOutput: "something went wrong")

        let state = await GhAuthCheck(runner: runner).check(gh: gh)

        #expect(state == .checkFailed("something went wrong"))
    }

    @Test("Když mlčí obojí, řekne alespoň exit kód")
    func checkFailedReportsExitCodeWhenOutputIsEmpty() async {
        let state = await GhAuthCheck(runner: FakeProcessRunner(exitCode: 42)).check(gh: gh)

        #expect(state == .checkFailed("gh auth status skončil s kódem 42."))
    }

    @Test("Nespustitelné gh nekončí pádem, ale rozlišitelným stavem")
    func checkFailedWhenGhCannotBeLaunched() async {
        let runner = FakeProcessRunner(failing: .launchFailed("Permission denied"))

        let state = await GhAuthCheck(runner: runner).check(gh: gh)

        #expect(state == .checkFailed("Permission denied"))
    }

    @Test("Timeout se od nepřihlášení odliší")
    func checkFailedOnTimeout() async {
        let runner = FakeProcessRunner(failing: .timedOut)

        let state = await GhAuthCheck(runner: runner, timeout: .seconds(15)).check(gh: gh)

        #expect(state == .checkFailed("gh auth status nedoběhl do 15 s."))
    }
}
