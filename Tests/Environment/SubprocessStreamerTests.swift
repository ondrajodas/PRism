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

    @Test("Zrušení proces zabije")
    func cancellationKillsTheProcess() async throws {
        // Bez toho by session běžela dál i poté, co uživatel zavřel okno.
        let marker = URL(
            filePath: NSTemporaryDirectory()
        ).appending(path: "prism-streamer-\(UUID().uuidString)")
        let path = marker.path(percentEncoded: false)

        let task = Task {
            for try await _ in streamer.stream(
                shell,
                arguments: ["-c", "sleep 1; touch '\(path)'"],
                environment: [:],
                workingDirectory: nil,
                timeout: .seconds(30)
            ) {}
        }

        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        _ = try? await task.value

        // Kdyby zrušení proces nezabilo, doběhl by sám a soubor by po sobě nechal.
        try await Task.sleep(for: .milliseconds(1500))
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
