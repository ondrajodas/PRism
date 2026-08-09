import Foundation
import Testing

@testable import PRism

/// Osa běhu, která přežije restart (#203).
///
/// Tři věci se dají pokazit potichu: **uložit prázdnou osu** (po restartu by hlavička revieweera
/// tvrdila, že běh nic neudělal), **oříznout konec místo začátku** (kdo se do osy dívá po
/// restartu, hledá, čím to skončilo) a **zapomenout, že se ořízlo**.
@Suite("Uložená osa běhu")
struct StoredTimelineTests {
    private func timeline(entries: Int, skill: String = "code-review") -> ReviewerTimeline {
        var timeline = ReviewerTimeline(skill: skill, worktree: URL(fileURLWithPath: "/tmp/wt"))
        let start = Date(timeIntervalSince1970: 1_000_000)
        timeline.record(.started(sessionID: "abc123"), at: start)
        for index in 0..<entries {
            timeline.record(
                .attemptedTool(ToolAttempt(name: "Read", detail: "soubor\(index).php")),
                at: start.addingTimeInterval(Double(index))
            )
        }
        return timeline
    }

    private func record(with stored: StoredTimeline?, skill: String = "code-review") -> ReviewRecord {
        makeRecord(runs: [makeStoredRun(skill: skill, timeline: stored, sessionID: "abc123")])
    }

    // MARK: - Ukládání

    @Test("Krátká osa se uloží celá a nic se neořízne")
    func storesAShortTimelineWhole() {
        let stored = timeline(entries: 3).stored()

        #expect(stored.entries.count == 4)
        #expect(stored.dropped == 0)
        #expect(stored.worktree?.path() == "/tmp/wt")
    }

    /// **Nejcennější test téhle sady.** Ořezává se začátek: konec je to, kvůli čemu se do osy po
    /// restartu člověk dívá.
    @Test("Dlouhá osa si nechá konec, ne začátek")
    func keepsTheEndOfALongTimeline() {
        let stored = timeline(entries: 20).stored(limit: 5)

        #expect(stored.entries.count == 5)
        #expect(stored.dropped == 16)
        // Poslední událost dlouhé osy je poslední pokus o nástroj, ne první.
        if case .tool(let tool) = stored.entries.last?.kind {
            #expect(tool.detail == "soubor19.php")
        } else {
            Issue.record("poslední událost není nástroj")
        }
    }

    /// Ořezané kolo se počítá **k tomu, co se ořezalo dřív**, jinak by druhé uložení téže osy
    /// tvrdilo, že chybí jen posledních pár událostí.
    @Test("Ořezané události se sčítají mezi uloženími")
    func addsUpDroppedEntries() {
        let restored = ReviewerTimeline(
            record(with: timeline(entries: 20).stored(limit: 5)).runs[0]
        )

        #expect(restored.droppedEntries == 16)
        #expect(restored.stored(limit: 2).dropped == 16 + 3)
    }

    // MARK: - Skládání zpátky

    /// `sessionID` se bere **z běhu**, ne z uložené osy — v souboru leží jednou. Je to zrovna
    /// ten údaj, kvůli kterému osa po restartu chybět nesmí: bez něj se do session nedá vrátit
    /// přes `claude --resume`.
    @Test("Osa se poskládá z uloženého běhu i se session")
    func restoresFromAStoredRun() {
        let restored = Policy.timelines(of: record(with: timeline(entries: 2).stored()))

        #expect(restored.count == 1)
        #expect(restored.first?.skill == "code-review")
        #expect(restored.first?.sessionID == "abc123")
        #expect(restored.first?.entries.count == 3)
    }

    /// Záznam z doby před #203 osu nemá. Prázdná hlavička revieweera by tvrdila, že běh proběhl,
    /// aniž by cokoli udělal — a to z chybějícího klíče neplyne.
    @Test("Běh bez uložené osy se v tabu neukáže")
    func skipsRunsWithoutATimeline() {
        #expect(Policy.timelines(of: record(with: nil)).isEmpty)
    }

    /// Osa jde na disk jako JSON, takže musí přežít **kolečko přes `Codable`** — události mají
    /// přiřazené hodnoty (nástroj, počet nálezů, výsledek) a právě u nich se dá kódování pokazit,
    /// aniž by o tom kdokoli věděl až do restartu.
    @Test("Uložená osa přežije kolečko přes JSON")
    func survivesAJSONRoundTrip() throws {
        var source = timeline(entries: 2)
        source.record(.findings(count: 3), at: Date(timeIntervalSince1970: 1_000_050))
        source.finish(.failed(detail: "spadlo"), at: Date(timeIntervalSince1970: 1_000_060))

        let data = try JSONEncoder().encode(source.stored())
        let decoded = try JSONDecoder().decode(StoredTimeline.self, from: data)

        #expect(decoded == source.stored())
        #expect(decoded.entries.last?.kind == .finished(.failed(detail: "spadlo")))
    }

    @Test("Bez záznamu není co skládat")
    func handlesAMissingRecord() {
        #expect(Policy.timelines(of: nil).isEmpty)
    }
}
