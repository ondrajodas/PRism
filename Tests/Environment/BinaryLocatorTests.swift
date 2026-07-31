import Foundation
import Testing

@testable import PRism

@Suite("BinaryLocator")
struct BinaryLocatorTests {
    @Test("Najde všechny nástroje na známých místech")
    func findsToolsInKnownLocations() async {
        let states = await locate(onDisk: KnownPath.all)

        #expect(states[.gh]?.path == KnownPath.gh)
        #expect(states[.git]?.path == KnownPath.git)
        #expect(states[.claude]?.path == KnownPath.claude)
        #expect(states.values.allSatisfy { $0.source == .knownLocation })
    }

    @Test("Login shell nespouští, když je všechno nalezené")
    func doesNotConsultLoginShellWhenAllToolsAreFound() async {
        let shell = FakeShellPathReader(path: ["/custom/bin"])
        let locator = BinaryLocator(probe: FakeExecutableProbe(KnownPath.all), shellPath: shell)

        _ = await locator.locate()

        #expect(shell.callCount == 0)
    }

    @Test("Co není na známém místě, dohledá v PATH login shellu")
    func fallsBackToLoginShellPath() async {
        let states = await locate(
            onDisk: [KnownPath.gh, KnownPath.git, "/custom/bin/claude"],
            shellPath: ["/custom/bin"]
        )

        #expect(states[.claude]?.path == "/custom/bin/claude")
        #expect(states[.claude]?.source == .loginShellPath)
    }

    @Test("Známé místo má přednost před PATH login shellu")
    func prefersKnownLocationOverLoginShellPath() async {
        // `claude` chybí všude, takže se login shell spustí — a přesto musí `gh` vyjít
        // z Homebrew, ne z cesty, kterou shell nabízí dřív.
        let states = await locate(
            onDisk: [KnownPath.gh, KnownPath.git, "/custom/bin/gh"],
            shellPath: ["/custom/bin"]
        )

        #expect(states[.gh]?.path == KnownPath.gh)
        #expect(states[.gh]?.source == .knownLocation)
        #expect(states[.claude] == .missing)
    }

    @Test("Pořadí známých míst rozhoduje, která instalace vyhraje")
    func respectsOrderOfKnownLocations() async {
        let states = await locate(onDisk: ["/usr/local/bin/gh", KnownPath.gh])

        #expect(states[.gh]?.path == KnownPath.gh)
    }

    @Test("Nástroj, který nikde není, hlásí jako chybějící")
    func reportsMissingToolWhenNowhereOnDisk() async {
        let states = await locate(onDisk: [])

        #expect(states[.gh] == .missing)
        #expect(states[.git] == .missing)
        #expect(states[.claude] == .missing)
    }

    @Test("Login shell spustí jednou i pro několik chybějících nástrojů")
    func consultsLoginShellOnceForSeveralMissingTools() async {
        let shell = FakeShellPathReader()
        let locator = BinaryLocator(probe: FakeExecutableProbe([]), shellPath: shell)

        _ = await locator.locate()

        #expect(shell.callCount == 1)
    }

    private func locate(onDisk paths: [String], shellPath: [String] = []) async -> [Tool: ToolState] {
        let locator = BinaryLocator(
            probe: FakeExecutableProbe(paths),
            shellPath: FakeShellPathReader(path: shellPath)
        )
        return await locator.locate()
    }
}
