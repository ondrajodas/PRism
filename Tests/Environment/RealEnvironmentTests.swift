import Foundation
import Testing

@testable import PRism

/// Integrační testy proti skutečnému filesystému a skutečným procesům. Malý počet — kryjí
/// právě to, co se fake implementacemi ověřit nedá. Nic z nich nechodí na síť.
///
/// **Timeouty se sem předávají velkorysé a je to strop proti zátěži, ne míra rychlosti** (#296).
/// Testy spouštějí `/bin/echo` a `/bin/sh`, tedy práci na jednotky milisekund — ale při souběžném
/// buildu tří slotů se `/bin/echo` nestihl spustit a posbírat do **10 s** a suita hlásila
/// `.timedOut` u tří testů naráz. Timeout tady tedy nic netvrdí; je tu proto, aby zaseknutý
/// podproces test položil, ne aby držel běh navěky.
@Suite("Environment proti skutečnému systému")
struct RealEnvironmentTests {
    private let probe = FileSystemExecutableProbe()
    private let runner = SubprocessRunner()

    /// Kolik času dostane podproces, po kterém se čeká výsledek. Viz komentář u suity.
    private static let generousTimeout: Duration = .seconds(60)

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
            timeout: Self.generousTimeout
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
            timeout: Self.generousTimeout
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

    /// **Strop se odvozuje od těch 30 s, které by proces žil sám** (#296), ne od toho, jak rychle
    /// zabití obvykle proběhne. Rozhoduje se totiž mezi „zabilo se“ a „čekalo se na EOF“, a to jsou
    /// desetiny vteřiny proti třiceti — cokoli mezi tím je pořád odpověď „zabilo se“. Do #296 tu
    /// stálo 5 s, tedy hodnota odvozená od volného stroje: při souběžném buildu tří slotů vycházelo
    /// **5,95 / 8,23 / 11,03 s** a suita byla červená, přitom aplikace fungovala.
    @Test("Zrušené volání proces zabije, místo aby čekalo, až doběhne sám")
    func runnerKillsProcessOnCancellation() async throws {
        // Bez zabití by `run()` čekalo na EOF na pipách, tedy plných 30 s — čtení skončí
        // teprve tím, že proces pipy zavře.
        let lifetime = Duration.seconds(30)
        let elapsed = await ContinuousClock().measure {
            let running = Task {
                try? await runner.run(
                    URL(filePath: "/bin/sleep"),
                    arguments: ["\(lifetime.components.seconds)"],
                    timeout: Self.generousTimeout
                )
            }
            try? await Task.sleep(for: .milliseconds(300))
            running.cancel()
            _ = await running.value
        }

        #expect(elapsed < lifetime / 2, "trvalo to \(elapsed.milliseconds)")
    }

    @Test("Runner ohlásí, že binárku nešlo spustit")
    func runnerReportsLaunchFailure() async {
        do {
            _ = try await runner.run(
                URL(filePath: "/usr/bin/prism-neexistuje"),
                arguments: [],
                timeout: Self.generousTimeout
            )
            Issue.record("Spuštění neexistující binárky mělo selhat.")
        } catch ProcessError.launchFailed {
            // Očekávaný stav.
        } catch {
            Issue.record("Neočekávaná chyba: \(error)")
        }
    }

    /// **Timeout se předává, nebere se výchozí** (#296). Produkční pětisekundový default je
    /// rozhodnutí o startu aplikace („zaseknutý shell nesmí položit start“) a zvětšovat se nemá —
    /// jenže při souběžném buildu tří slotů ho login shell přetáhl a čtení vrátilo prázdno, tedy
    /// pád testu o parsování `PATH`. Test se ptá na to, jestli se skutečný `PATH` přečte a rozebere,
    /// ne na to, jestli se to stihne za produkční rozpočet.
    @Test("Login shell vrátí neprázdný PATH")
    func loginShellReportsNonEmptyPath() async {
        let reader = LoginShellPathReader(runner: runner, timeout: Self.generousTimeout)

        let directories = await reader.loginShellPath()

        #expect(directories.isEmpty == false)
    }
}
