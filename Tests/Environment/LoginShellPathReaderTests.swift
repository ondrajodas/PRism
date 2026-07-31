import Foundation
import Testing

@testable import PRism

@Suite("LoginShellPathReader")
struct LoginShellPathReaderTests {
    @Test("Rozdělí PATH na složky")
    func splitsPathIntoDirectories() async {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: "/opt/homebrew/bin:/usr/bin:/Users/ondra/.local/bin\n"
        )

        let directories = await LoginShellPathReader(runner: runner).loginShellPath()

        #expect(
            directories.map { $0.path(percentEncoded: false) } == [
                "/opt/homebrew/bin",
                "/usr/bin",
                "/Users/ondra/.local/bin",
            ]
        )
    }

    @Test("Prázdné části PATH zahodí")
    func ignoresEmptySegments() async {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "/a::/b:\n")

        let directories = await LoginShellPathReader(runner: runner).loginShellPath()

        #expect(directories.map { $0.path(percentEncoded: false) } == ["/a", "/b"])
    }

    @Test("Ptá se login shellu na PATH")
    func asksLoginShellForPath() async {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "/a\n")

        _ = await LoginShellPathReader(runner: runner).loginShellPath()

        #expect(runner.invocations.count == 1)
        #expect(runner.invocations.first?.arguments == ["-lc", "echo $PATH"])
    }

    @Test("Nenulový exit kód znamená prázdný výsledek, ne pád")
    func emptyWhenShellExitsNonZero() async {
        let runner = FakeProcessRunner(exitCode: 1, standardOutput: "/a\n")

        let directories = await LoginShellPathReader(runner: runner).loginShellPath()

        #expect(directories.isEmpty)
    }

    @Test("Zaseknutý shell nesmí zablokovat start")
    func emptyWhenShellTimesOut() async {
        let runner = FakeProcessRunner(failing: .timedOut)

        let directories = await LoginShellPathReader(runner: runner).loginShellPath()

        #expect(directories.isEmpty)
    }

    @Test("Nespustitelný shell znamená prázdný výsledek")
    func emptyWhenShellCannotBeLaunched() async {
        let runner = FakeProcessRunner(failing: .launchFailed("No such file"))

        let directories = await LoginShellPathReader(runner: runner).loginShellPath()

        #expect(directories.isEmpty)
    }
}
