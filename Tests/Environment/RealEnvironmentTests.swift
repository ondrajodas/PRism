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

    /// **Zabití se ověřuje na PID, ne na naměřeném čase volání** (#296, mění #220). Do #296 tady
    /// stálo `elapsed < .seconds(5)` — tedy hodnota odvozená od volného stroje, kde celé kolo trvá
    /// 0,3 s. Při souběžném buildu tří slotů vycházelo **5,95 / 8,23 / 11,03 s**, po zvětšení stropu
    /// na 15 s pak **17,7 / 19,4 / 20,4 / 26,7 s**: měřený čas volání je pod zátěží nečitelný a
    /// zvětšování stropu je hra, ve které zátěž pokaždé přesáhne poslední odhad.
    ///
    /// Zmizelý PID je navíc **silnější tvrzení**: naměřený čas říká jen „vrátilo se to brzo“, takže
    /// by prošla i implementace, která na proces zapomene a nechá ho běžet dál. Tady se ptáme přímo
    /// na to, co od zrušení chceme — proces už neexistuje. Je to tatáž cesta, jakou to od #101 dělá
    /// `SubprocessStreamerTests`; ta pod zátěží prošla 5× z 5.
    @Test("Zrušené volání proces zabije, místo aby čekalo, až doběhne sám", .timeLimit(.minutes(3)))
    func runnerKillsProcessOnCancellation() async throws {
        // Bez zabití by `run()` čekalo na EOF na pipách — čtení skončí teprve tím, že proces
        // pipy zavře, tedy až mu doběhne `sleep`.
        let pidFile = temporaryPIDFile("runner-cancel")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let script = "echo $$ > '\(pidFile.path(percentEncoded: false))'; exec sleep 300"

        let running = Task {
            try? await runner.run(
                URL(filePath: "/bin/sh"),
                arguments: ["-c", script],
                timeout: Self.generousTimeout
            )
        }
        // Rušit se má proces, který **doopravdy běží** — jinak by test prošel i tehdy, kdyby se
        // nespustil vůbec. `exec` je tam proto, aby PID patřil tomu procesu, který má umřít,
        // a nezůstal pod ním potomek, který by výsledek rozmazal.
        let pid = try await processID(writtenTo: pidFile)

        running.cancel()

        // **Pořadí je tady podstatná část testu.** Na proces se musí kouknout **dřív**, než se
        // počká na `running.value`: to čekání totiž skončí i tím, že procesu doběhne `sleep`, a
        // „zmizel“ pak platí samo, bez ohledu na to, jestli ho někdo zabil. Změřeno vloženou
        // regresí — s vyndaným `requestKill()` test v opačném pořadí **prošel** za 300 s. Je to
        // tatáž past, kterou `docs/testovani.md` popisuje u `AppStoreTerminationProcessTests`.
        #expect(await processHasGone(pid), "proces \(pid) po zrušení pořád běží")

        // `.timeLimit` u testu je tu proto, že tohle čekání je v **rozbitém** stavu dlouhé: když
        // se nezabíjí, vrátí se teprve po `sleep`u. Zelený běh se jím nezdrží ani o milisekundu.
        _ = await running.value
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
