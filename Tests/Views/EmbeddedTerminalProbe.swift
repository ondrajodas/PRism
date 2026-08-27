import AppKit
import Darwin
import Foundation
import Testing

@testable import PRism

/// Sonda, ne test (#459): **spustí skutečný login shell** v pty a zase ho zabije.
///
/// Existuje proto, že tři nejrizikovější věci na celém #459 se přečtením kódu ověřit nedají:
/// jestli se shell vůbec spustí, jestli stojí **v tom adresáři, který dostal**, a jestli po
/// `kill()` **doopravdy** neběží. Ta poslední je celý závazek z #264 a #351.
///
/// **V běžném běhu se nepouští** (`PRISM_MEASURE`), a je to podmínka, ne opatrnost: spuštěný shell
/// je proces, který umí běh testů přežít — a `xcodebuild test` běží i souběžně ve třech slotech.
///
/// ```bash
/// TEST_RUNNER_PRISM_MEASURE=1 xcodebuild -project PRism.xcodeproj -scheme PRism \
///     -derivedDataPath build.noindex test -only-testing:PRismTests/EmbeddedTerminalProbe
/// ```
///
/// **Co sonda ověřit nemůže, a je to změřené, ne odhad: obsah emulátoru.** `LocalProcess` doručuje
/// přečtené bajty přes `DispatchQueue.main`, a **hlavní dispatch fronta se v testovacím hostu
/// nedrání vůbec** — naměřeno tak, že se z pozadí zavolalo `DispatchQueue.main.async` a `.sync`
/// a ani jedno neproběhlo (`hits == 0`) za pět sekund, přestože sonda běží na hlavním vlákně
/// (`Thread.isMainThread == true`) a točí `RunLoop.main.run(until:)`. Za běhu aplikace ten stav
/// nenastane; v hostu z toho plyne, že buffer emulátoru zůstane prázdný, ať shell vypíše cokoli.
///
/// Sonda proto **nic nečte z emulátoru** a všechno si zjišťuje z jádra: adresář přes `lsof`, běh
/// a zánik přes `ps`. Že se do pty dá **psát**, se pozná tím, že shell po `exit` skončí — což je
/// pozorovatelné taky bez hlavní fronty. Jak plocha doopravdy vypadá, ověřuje člověk na běžící
/// aplikaci (postup je v `docs/testovani.md`).
@MainActor
@Suite(
    "Sonda vestavěného terminálu (#459)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct EmbeddedTerminalProbe {
    @Test("Shell stojí v tom adresáři, který dostal, a čte, co mu píšeme")
    func startsWhereItWasToldAndReadsInput() throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let view = EmbeddedTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 300))
        view.font = TerminalHost.font
        var states: [TerminalRunState] = []
        view.stateChanged = { states.append($0) }
        view.start(in: directory)

        guard let pid = view.shellPid else {
            Issue.record("shell se nespustil")
            return
        }
        print("SONDA shell pid=\(pid), stav \(Self.state(of: pid) ?? "—")")
        #expect(states == [.running])
        #expect(Self.isAlive(pid), "shell neběží hned po startu")

        // **Adresář z jádra, ne z výpisu**: `pwd` v terminálu by se muselo přečíst z bufferu,
        // a ten v hostu zůstává prázdný (viz hlavička).
        // **Obě cesty přes `resolvingSymlinksInPath`**, protože `TMPDIR` je na macOS symlink:
        // jádro hlásí `/private/var/folders/…`, kdežto `FileManager` vydává `/var/folders/…`.
        // Bez toho by tvrzení padalo na rozdíl, který o adresáři shellu nevypovídá nic.
        let cwd = Self.workingDirectory(of: pid).map { ($0 as NSString).resolvingSymlinksInPath }
        let wanted = (directory.path(percentEncoded: false) as NSString).resolvingSymlinksInPath
        print("SONDA cwd=\(cwd ?? "—")")
        #expect(cwd == wanted)

        // Psaní do pty **tou cestou, kterou jde vstup v aplikaci**. Že bajty dorazily, se pozná
        // tím, že shell skončí — na to hlavní fronta potřeba není.
        view.send(source: view, data: ArraySlice("exit\n".utf8))
        #expect(
            Self.wait(until: { !Self.isAlive(pid) }, limit: 15),
            "shell nereagoval na `exit` — do pty se nezapisuje"
        )
        // Sirotek by tu neměl co dělat ani po řádném ukončení.
        view.kill()
    }

    @Test("kill() zabije běžící shell")
    func killLeavesNothingBehind() throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let view = EmbeddedTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 300))
        view.font = TerminalHost.font
        view.start(in: directory)

        guard let pid = view.shellPid else {
            Issue.record("shell se nespustil")
            return
        }
        #expect(Self.isAlive(pid))

        view.kill()

        // **Tohle je to podstatné tvrzení**: po `kill()` nesmí zbýt nic, co by se přerodilo
        // na `launchd` (#264, #351).
        #expect(
            Self.wait(until: { !Self.isAlive(pid) }, limit: 10),
            "shell přežil kill(): stav \(Self.state(of: pid) ?? "—")"
        )
        #expect(!view.isRunning)
        print("SONDA po kill: pid=\(pid) stav=\(Self.state(of: pid) ?? "—")")
    }

    // MARK: - Čekání

    private static func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "prism-terminal-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Čeká **na jev se stropem** (#269) a **bez `await`u**: čeká se na stav v jádře, ne na práci
    /// v aplikaci, takže tu není co uspávat kooperativně — a `Task.sleep` by tu byl jen dražší
    /// způsob, jak stát na místě.
    private static func wait(until condition: () -> Bool, limit: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(limit)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition()
    }

    // MARK: - Co říká jádro

    /// Stav procesu podle `ps`; `nil` = pod tím PID nic není.
    private static func state(of pid: pid_t) -> String? {
        let text = run("/bin/ps", ["-o", "state=", "-p", String(pid)])
        return text.isEmpty ? nil : text
    }

    /// **Zombie se počítá jako mrtvý.** Nesklizený potomek zabírá v tabulce procesů řádek, ale
    /// neběží — a `kill(pid, 0)` na něm pořád vrací nulu, takže by samo o sobě tvrdilo, že shell
    /// přežil. Sklidí ho `LocalProcess.processTerminated` svým `waitpid`em, jakmile se hlavní
    /// fronta dostane ke slovu; v aplikaci hned, v hostu nikdy (viz hlavička).
    private static func isAlive(_ pid: pid_t) -> Bool {
        guard let state = state(of: pid) else { return false }
        return !state.hasPrefix("Z")
    }

    /// Pracovní adresář procesu z jádra.
    private static func workingDirectory(of pid: pid_t) -> String? {
        let text = run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"])
        return TextLines.content(text).first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
    }

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
