import Foundation
import Testing

@testable import PRism

/// Integrační testy proti skutečnému filesystému a skutečným procesům. Malý počet — kryjí
/// právě to, co se fake implementacemi ověřit nedá. Nic z nich nechodí na síť.
@Suite("Environment proti skutečnému systému")
struct RealEnvironmentTests {
    private let probe = FileSystemExecutableProbe()
    private let runner = SubprocessRunner()

    @Test("Spustitelná složka se nesmí splést s binárkou")
    func probeRejectsDirectory() {
        // `/usr/bin` má spustitelný bit — u složky znamená „průchozí", ne „binárka".
        #expect(probe.isExecutable(at: URL(filePath: "/usr/bin")) == false)
        #expect(probe.isExecutable(at: URL(filePath: "/bin/zsh")))
    }

    @Test("Symlink na binárku projde — takhle je nainstalovaný claude")
    func probeFollowsSymlinkToExecutable() throws {
        let directory = URL.temporaryDirectory.appending(path: "prism-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let link = directory.appending(path: "zsh-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(filePath: "/bin/zsh"))

        #expect(probe.isExecutable(at: link))
    }

    @Test("Nenalezne binárku, která neexistuje")
    func probeRejectsMissingFile() {
        #expect(probe.isExecutable(at: URL(filePath: "/usr/bin/prism-neexistuje")) == false)
    }

    @Test("Runner posbírá stdout a exit kód")
    func runnerCollectsStandardOutputAndExitCode() async throws {
        let result = try await runner.run(
            URL(filePath: "/bin/echo"),
            arguments: ["ahoj"],
            timeout: .seconds(10)
        )

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "ahoj\n")
        #expect(result.standardError.isEmpty)
    }

    @Test("Runner posbírá stderr i nenulový exit kód")
    func runnerCollectsStandardError() async throws {
        let result = try await runner.run(
            URL(filePath: "/bin/sh"),
            arguments: ["-c", "echo chyba >&2; exit 3"],
            timeout: .seconds(10)
        )

        #expect(result.exitCode == 3)
        #expect(result.standardError == "chyba\n")
        #expect(result.standardOutput.isEmpty)
    }

    @Test("Runner zabije proces, který nedoběhl v limitu")
    func runnerReportsTimeout() async {
        await #expect(throws: ProcessError.timedOut) {
            try await runner.run(
                URL(filePath: "/bin/sleep"),
                arguments: ["30"],
                timeout: .milliseconds(200)
            )
        }
    }

    @Test("Zrušené volání proces zabije, místo aby čekalo, až doběhne sám")
    func runnerKillsProcessOnCancellation() async throws {
        // Bez zabití by `run()` čekalo na EOF na pipách, tedy plných 30 s — čtení skončí
        // teprve tím, že proces pipy zavře.
        let elapsed = await ContinuousClock().measure {
            let running = Task {
                try? await runner.run(
                    URL(filePath: "/bin/sleep"),
                    arguments: ["30"],
                    timeout: .seconds(60)
                )
            }
            try? await Task.sleep(for: .milliseconds(300))
            running.cancel()
            _ = await running.value
        }

        #expect(elapsed < .seconds(5))
    }

    @Test("Runner ohlásí, že binárku nešlo spustit")
    func runnerReportsLaunchFailure() async {
        do {
            _ = try await runner.run(
                URL(filePath: "/usr/bin/prism-neexistuje"),
                arguments: [],
                timeout: .seconds(10)
            )
            Issue.record("Spuštění neexistující binárky mělo selhat.")
        } catch ProcessError.launchFailed {
            // Očekávaný stav.
        } catch {
            Issue.record("Neočekávaná chyba: \(error)")
        }
    }

    @Test("Login shell vrátí neprázdný PATH")
    func loginShellReportsNonEmptyPath() async {
        let directories = await LoginShellPathReader(runner: runner).loginShellPath()

        #expect(directories.isEmpty == false)
    }
}
