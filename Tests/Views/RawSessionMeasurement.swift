import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Měření, ne test (#327) — kolik stojí otevřít surovou session nad **velkým** transcriptem. Nic
/// netvrdí, vypisuje čísla.
///
/// Existuje proto, že „nad 53MB transcriptem se sheet otevře bez viditelné prodlevy“ je tvrzení ze
/// zadání issue, a taková se v tomhle repu **měří, ne odhadují** (#275: měř tu cestu, kterou kód
/// doopravdy jde). Časy se nehlídají `#expect`em: na jiném stroji vyjdou jinak a byl by z toho test,
/// který padá bez chyby v kódu.
///
/// **Jak to pustit.** Suita je vypnutá, dokud není `PRISM_MEASURE`, a předává se s prefixem
/// `TEST_RUNNER_` — jen to `xcodebuild` do testovacího procesu pustí:
///
/// ```bash
/// TEST_RUNNER_PRISM_MEASURE=1 \
///     xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test \
///     -only-testing:PRismTests/RawSessionMeasurement > /tmp/mereni.log 2>&1
/// ```
///
/// **Transcript je syntetický, ale podle skutečného** — 53 MB se do repa nepřikládá. Tvar je
/// změřený na 922 souborech pod `~/.claude/projects`: největší 53,3 MB při **2 348 řádcích**,
/// nejdelší řádek 7,5 MB, medián řádku 1 604 B. Právě ten rozdíl (obrovský soubor, málo řádků) je
/// důvod, proč je jednotkou okna bajt a ne řádek. Když je po ruce skutečný, vezme se on:
/// `PRISM_TRANSCRIPT_FILE`.
@Suite(
    "Měření ceny surové session (#327)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil),
    .serialized
)
@MainActor
struct RawSessionMeasurement {
    private let worktree = URL(filePath: "/Users/ondra/cache/worktrees/o/r/6-abc")

    private func ms(_ body: () -> Void) -> String {
        let clock = ContinuousClock()
        let elapsed = clock.measure { body() }
        let millis = Double(elapsed.components.attoseconds) / 1e15
            + Double(elapsed.components.seconds) * 1000
        return String(format: "%.2f", millis)
    }

    /// Syntetický transcript o zadané velikosti: střídají se `tool_use`, `tool_result` s velkým
    /// výstupem, próza a `thinking` — tedy to, co v souboru objem doopravdy dělá (`tool_result`
    /// 19,1 MB z 53, próza 61 kB).
    private func transcript(bytes: Int) -> Data {
        var data = Data(capacity: bytes + 100_000)
        var index = 0
        let payload = String(repeating: "x", count: 22_000)
        while data.count < bytes {
            let stamp = "2026-08-09T21:44:2\(index % 10).241Z"
            let lines = [
                "{\"type\":\"assistant\",\"timestamp\":\"\(stamp)\",\"message\":{\"content\":"
                    + "[{\"type\":\"tool_use\",\"id\":\"t\(index)\",\"name\":\"Bash\","
                    + "\"input\":{\"command\":\"grep -rn cache src\"}}]}}",
                "{\"type\":\"user\",\"timestamp\":\"\(stamp)\",\"message\":{\"content\":"
                    + "[{\"type\":\"tool_result\",\"tool_use_id\":\"t\(index)\",\"content\":\"\(payload)\"}]}}",
                "{\"type\":\"assistant\",\"timestamp\":\"\(stamp)\",\"message\":{\"content\":"
                    + "[{\"type\":\"thinking\",\"thinking\":\"tohle mi nesedí\"}]}}",
                "{\"type\":\"assistant\",\"timestamp\":\"\(stamp)\",\"message\":{\"content\":"
                    + "[{\"type\":\"text\",\"text\":\"Podívám se na to jinudy.\"}]}}",
            ]
            data.append(Data((lines.joined(separator: "\n") + "\n").utf8))
            index += 1
        }
        return data
    }

    private func place(_ data: Data, in directory: TemporaryDirectory, as sessionID: String) throws -> URL {
        let url = TranscriptLocation.transcript(
            ofSession: sessionID,
            in: worktree,
            projects: directory.url
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        return url
    }

    // MARK: - Čtení okna

    /// **Cena, kterou se platí při otevření sheetu.** Rozhoduje o tom, jestli má stav „moc velký“
    /// vůbec smysl — u logu jobu ho vynutila síť (`gh` stahoval 8,78 MB v jednotkách až desítkách
    /// vteřin), tady se čte `seek`em od konce a velikost souboru do toho čísla nemá jak vstoupit.
    @Test("Cena otevření nad velkým transcriptem")
    func openingCost() async throws {
        let directory = try TemporaryDirectory()
        let store = TranscriptStore(projects: directory.url)

        for megabytes in [1, 8, 53] {
            let data = try realTranscript() ?? transcript(bytes: megabytes * 1024 * 1024)
            _ = try place(data, in: directory, as: "s-\(megabytes)")

            let clock = ContinuousClock()
            let started = clock.now
            let snapshot = try await store.snapshot(ofSession: "s-\(megabytes)", in: worktree, at: .now)
            let elapsed = clock.now - started
            let millis = Double(elapsed.components.attoseconds) / 1e15
                + Double(elapsed.components.seconds) * 1000
            print("MĚŘENÍ snímek \(megabytes) MB (\(data.count) B):")
            print("  snapshot:            \(String(format: "%.2f", millis)) ms")
            print("  událostí v okně:     \(snapshot?.events.count ?? -1)")
            print("  nevešlo se:          \(snapshot?.omittedBytes ?? -1) B")
            if try realTranscript() != nil { break }
        }
    }

    /// Z čeho se cena otevření skládá. **Bez rozpadu se optimalizuje naslepo** — a u #327 se to
    /// stalo: ořez těla po znacích vypadal jako ta drahá věc (osm tisíc alokací `String`u na
    /// událost) a jeho odstranění nezměnilo **nic** (627 → 627 ms). Rozpad ukázal, kde cena doopravdy
    /// je: rozbor JSONu stojí **6,9 ms** ze 312, kdežto dělení textu na řádky **216 ms** — tedy ta
    /// jediná věc, která nad megabajty jde po `Character`ech (`TextLines`, kvůli `CRLF`, #295).
    /// Ubralo se proto tam: dělit se přestalo celé tělo a celý zbytek, jen `limit` bajtů
    /// (**428 → 108 ms** za `transcribe`).
    @Test("Z čeho se cena otevření skládá")
    func openingBreakdown() throws {
        let data = try realTranscript() ?? transcript(bytes: 53 * 1024 * 1024)
        let window = Policy.rawSessionWindow(fileBytes: data.count)
        let slice = data.dropFirst(window.offset).prefix(window.length)
        let dropped = Policy.rawSessionPrefixDrop(Data(slice), isTail: window.offset > 0)
        let body = slice.dropFirst(dropped)

        print("MĚŘENÍ rozpad otevření (\(body.count) B okna):")
        print("  String(data:):       \(ms { _ = String(data: body, encoding: .utf8) }) ms")
        let text = String(data: body, encoding: .utf8) ?? ""
        print("  TextLines.content:   \(ms { _ = TextLines.content(text) }) ms")
        let lines = TextLines.content(text)
        print("  řádků v okně:        \(lines.count)")
        let strings = lines.map(String.init)
        let parsing = ms {
            for line in strings { _ = try? JSONSerialization.jsonObject(with: Data(line.utf8)) }
        }
        print("  JSONSerialization:   \(parsing) ms")
        print("  transcribe:          \(ms { _ = TranscriptTranscriber(worktree: worktree).transcribe(lines) }) ms")
    }

    /// Sazba běží **na hlavním vlákně**, protože `NSAttributedString` se skládá až ve view — takže
    /// je to to jediné z celé obrazovky, co umí okno zdržet. Měří se odděleně od čtení, aby se
    /// nezaměnilo jedno za druhé (#274: měřidlo nesmí počítat přípravu).
    @Test("Cena sazby přepisu")
    func typesettingCost() async throws {
        let directory = try TemporaryDirectory()
        let store = TranscriptStore(projects: directory.url)
        let data = try realTranscript() ?? transcript(bytes: 53 * 1024 * 1024)
        _ = try place(data, in: directory, as: "sazba")
        let snapshot = try #require(await store.snapshot(ofSession: "sazba", in: worktree, at: .now))

        print("MĚŘENÍ sazba (\(snapshot.events.count) událostí):")
        print("  lines:               \(ms { _ = RawSessionScript.lines(of: snapshot) }) ms")
        let lines = RawSessionScript.lines(of: snapshot)
        print("  attributed:          \(ms { _ = RawSessionScript.attributed(lines) }) ms")
        print("  plain (kopie):       \(ms { _ = RawSessionScript.plain(lines) }) ms")
        let attributed = RawSessionScript.attributed(lines)
        print("  znaků v přepisu:     \(attributed.length)")
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let sitting = ms { view.textStorage?.setAttributedString(attributed) }
        print("  setAttributedString: \(sitting) ms")
    }

    /// Skutečný transcript, když je po ruce.
    private func realTranscript() throws -> Data? {
        guard let path = ProcessInfo.processInfo.environment["PRISM_TRANSCRIPT_FILE"] else { return nil }
        return try Data(contentsOf: URL(filePath: path))
    }
}
