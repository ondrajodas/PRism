import Foundation
import Testing

@testable import PRism

/// Proti skutečným procesům, ne proti fake runneru.
///
/// Fake ověří, co se `claude` posílá; jestli tomu rozumí `Process` — že řádky přijdou
/// v pořadí, že EOF dorazí dřív než konec proudu a že zabitý proces skončí timeoutem —
/// se dá zjistit jen spuštěním. Přesně tohle unit testy `RepoCheckoutu` nechytly.
@Suite("SubprocessStreamer")
struct SubprocessStreamerTests {
    private let shell = URL(filePath: "/bin/sh")
    private let streamer = SubprocessStreamer()

    private func collect(
        _ script: String,
        workingDirectory: URL? = nil,
        timeout: Duration = .seconds(10)
    ) async throws -> [ProcessEvent] {
        var events: [ProcessEvent] = []
        for try await event in streamer.stream(
            shell,
            arguments: ["-c", script],
            environment: [:],
            workingDirectory: workingDirectory,
            timeout: timeout
        ) {
            events.append(event)
        }
        return events
    }

    @Test("Řádky přijdou v pořadí a konec nese kód i stderr")
    func linesArriveInOrder() async throws {
        let events = try await collect("echo prvni; echo druhy; echo chyba >&2; exit 3")

        #expect(events == [
            .line("prvni"),
            .line("druhy"),
            .finished(exitCode: 3, standardError: "chyba\n"),
        ])
    }

    @Test("Nedokončený poslední řádek se doručí, ne zahodí")
    func aTruncatedLastLineIsStillDelivered() async throws {
        // Zabitý proces umí stream useknout uprostřed řádku. Zahodit ho by znamenalo, že
        // se nález bez konce řádku nedá odlišit od nálezu, který nikdy nebyl.
        let events = try await collect("printf 'cely\\nusek'")

        #expect(events.first == .line("cely"))
        #expect(events.dropFirst().first == .line("usek"))
    }

    @Test("Proces běží v předané pracovní složce")
    func theProcessRunsInTheGivenDirectory() async throws {
        // `claude` pracovní složku flagem předat neumí — je to `cwd` procesu.
        // `/bin/pwd`, ne builtin: ten umí vypsat zděděné `PWD`, ne skutečnou složku.
        let directory = URL(filePath: "/usr/lib")
        let events = try await collect("/bin/pwd", workingDirectory: directory)

        #expect(events.first == .line("/usr/lib"))
    }

    @Test("Zaseknutý proces skončí timeoutem")
    func aStuckProcessTimesOut() async throws {
        await #expect(throws: ProcessError.timedOut) {
            _ = try await collect("sleep 30", timeout: .milliseconds(200))
        }
    }

    @Test("Řádky vypsané před timeoutem zůstanou doručené")
    func linesBeforeATimeoutSurvive() async throws {
        var events: [ProcessEvent] = []
        let stream = streamer.stream(
            shell,
            arguments: ["-c", "echo nalez; sleep 30"],
            environment: [:],
            workingDirectory: nil,
            timeout: .milliseconds(300)
        )

        await #expect(throws: ProcessError.timedOut) {
            for try await event in stream { events.append(event) }
        }
        #expect(events == [.line("nalez")])
    }

    @Test("Timeout ukončí proud, i když roura zůstane otevřená")
    func aTimeoutEndsTheStreamEvenWithAnOpenPipe() async throws {
        // Potomek na pozadí zdědí stdout a zabitý shell ho nepřežije — EOF tedy nedorazí.
        // Bez posledního slova timeoutu by proud čekal navždy a review by viselo.
        let streamer = SubprocessStreamer(gracePeriod: .milliseconds(100))

        await #expect(throws: ProcessError.timedOut) {
            for try await _ in streamer.stream(
                shell,
                arguments: ["-c", "sleep 5 & sleep 5"],
                environment: [:],
                workingDirectory: nil,
                timeout: .milliseconds(200)
            ) {}
        }
    }

    /// Bez toho by session běžela dál i poté, co uživatel zavřel okno.
    ///
    /// **Sleduje se PID, ne soubor po procesu** — a je to oprava #101, ne kosmetika. Původní
    /// verze spouštěla `sleep 1; touch <soubor>`, po 200 ms rušila a po dalších 1,5 s ověřovala,
    /// že soubor není. Rezerva proti zpoždění pod zátěží tam byla jen ~800 ms a **nedala se
    /// zvětšit zdarma**: delší `sleep` znamená, že se test musí stejně dlouho dočkat jeho konce.
    /// Padalo to tím spíš, čím víc procesů pouštěly ostatní suity (Swift Testing je pouští
    /// paralelně) — po #73 vycházel jeden pád ze čtyř běhů, na commitu před ním 0 ze 3.
    ///
    /// Na PID se zabití pozná **v okamžiku, kdy nastane**, takže deadline může být klidně
    /// pětisekundový a test přesto skončí v desítkách milisekund. Zároveň testuje víc než dřív:
    /// nepřítomnost souboru dokazovala jen to, že `touch` neproběhl, kdežto zmizelý PID je
    /// přímo to tvrzení, které od zrušení chceme.
    @Test("Zrušení proces zabije")
    func cancellationKillsTheProcess() async throws {
        let pidFile = URL(
            filePath: NSTemporaryDirectory()
        ).appending(path: "prism-streamer-\(UUID().uuidString).pid")
        let path = pidFile.path(percentEncoded: false)
        defer { try? FileManager.default.removeItem(at: pidFile) }

        let task = Task {
            for try await _ in streamer.stream(
                shell,
                arguments: ["-c", "echo $$ > '\(path)'; sleep 30"],
                environment: [:],
                workingDirectory: nil,
                timeout: .seconds(60)
            ) {}
        }

        // Rušit se má proces, který **doopravdy běží** — jinak by test mohl projít i tehdy,
        // kdyby se nespustil vůbec.
        let pid = try await pid(from: pidFile)
        task.cancel()
        _ = try? await task.value

        #expect(await isGone(pid), "proces \(pid) po zrušení pořád běží")
    }

    /// PID z běžícího procesu. Čeká na něj pollingem, ne pevnou odmlkou — start `/bin/sh` trvá
    /// jednotky milisekund, ale pod zátěží klidně stovky.
    /// **Nekladné číslo se nepřijme**, i když ho `echo $$` dát nemůže. `kill(0, …)` míří na celou
    /// **procesovou skupinu** volajícího a negativní PID taky na skupinu — takže hodnota, která
    /// se sem omylem dostane, by z kontroly existence jednoho procesu udělala něco úplně jiného.
    /// Upozornil na to Copilot na #121; past by se tady sice neotevřela (soubor se plní jedním
    /// `echo $$`, a `pid_t(_:)` je failable, takže rozbitý text vede na další kolo pollingu, ne
    /// na nulu), ale stojí to jednu podmínku.
    private func pid(from file: URL) async throws -> pid_t {
        for _ in 0..<250 {
            if let text = try? String(contentsOf: file, encoding: .utf8),
               let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
               pid > 0 {
                return pid
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ProcessTestFailure.processNeverStarted
    }

    /// Zmizel proces? `kill(pid, 0)` jen ověřuje existenci, nic neposílá.
    ///
    /// Čeká se na **výsledek**, ne pevnou dobu: když zrušení zabije proces hned (běžný případ),
    /// vrátí to po prvním kole. Deadline je velkorysý schválně — je tu proti zátěži, ne proti
    /// pomalému zabíjení.
    private func isGone(_ pid: pid_t) async -> Bool {
        for _ in 0..<250 {
            if kill(pid, 0) != 0 { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}

private enum ProcessTestFailure: Error {
    case processNeverStarted
}
