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
        // Pět uložených událostí a k nim doplněný konec z běhu (nahlášení nálezů a výsledek),
        // takže při stropu dva se z těch sedmi ořeže pět.
        #expect(restored.entries.count == 7)
        #expect(restored.stored(limit: 2).dropped == 16 + 5)
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
        // Tři uložené události plus doplněný konec z běhu — viz sekce *Doplněný konec* níž.
        #expect(restored.first?.entries.count == 5)
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

    // MARK: - Doplněný konec

    /// **Uložená osa svůj konec neobsahuje** — snímek pro zápis se bere dřív, než proud událostí
    /// dojede. Změřeno na skutečné cache: **7 ze 7** os po skutečném běhu je bez `doběhlo`
    /// i bez `hlásí nálezy`; osy vyrobené v testech ho mají, proto to testy nechytily. Bez doplnění
    /// tab `Průběh` po restartu tvrdí `nedoběhlo — běh někdo zrušil` nad doběhlým review.
    @Test("Uložená osa bez konce si ho doplní z běhu, pod kterým leží")
    func completesTheTailFromTheRun() throws {
        let stored = timeline(entries: 2).stored()
        #expect(!stored.entries.contains { if case .finished = $0.kind { true } else { false } })

        let restored = ReviewerTimeline(
            makeStoredRun(
                findings: [makeReported(summary: "nález")],
                timeline: stored,
                sessionID: "abc123"
            )
        )

        #expect(restored.isFinished)
        #expect(restored.entries.suffix(2).map(\.kind) == [.findings(count: 1), .finished(.finished)])
        // Identita nesmí být z počtu: zkrácená osa si nechává původní čísla, takže by doplněný
        // konec dostal číslo menší než jeho předchůdce.
        let ids = restored.entries.map(\.id)
        #expect(ids == ids.sorted())
        #expect(Set(ids).count == ids.count)
    }

    /// Nahlášený počet, ne jen uložený: nález, který se nepodařilo přečíst, reviewer nahlásil.
    @Test("Doplněný počet nálezů bere i ty, které se nepodařilo přečíst")
    func countsDroppedFindingsIntoTheTail() {
        let restored = ReviewerTimeline(
            makeStoredRun(
                findings: [makeReported(summary: "nález")],
                droppedFindings: 2,
                timeline: timeline(entries: 1).stored()
            )
        )

        #expect(restored.entries.dropLast().last?.kind == .findings(count: 3))
    }

    /// Reviewer, který `ReportFindings` nezavolal, o kódu neřekl nic — a `hlásí nálezy` u něj musí
    /// zůstat nedotčené, jinak by tab tvrdil, že nahlásil prázdný seznam, tedy čisto.
    @Test("Běh, který nálezy nenahlásil, doplněnou fázi hlášení nedostane")
    func doesNotInventAReport() {
        let restored = ReviewerTimeline(
            makeStoredRun(calledReportFindings: false, timeline: timeline(entries: 1).stored())
        )

        #expect(!restored.entries.contains { if case .findings = $0.kind { true } else { false } })
        #expect(restored.isFinished)
    }

    /// A **prázdná osa se nedoplňuje**: běh, jehož osa se vůbec neuložila, musí zůstat bez osy —
    /// v tabu je z něj `bez průběhu`, ne vymyšlený průběh o dvou událostech.
    @Test("Chybějící osa se nedoplní na dvě události")
    func doesNotInventATimeline() {
        #expect(Policy.timelines(of: record(with: nil)).isEmpty)
        #expect(ReviewerTimeline(makeStoredRun(timeline: nil)).entries.isEmpty)
        #expect(ReviewerTimeline(makeStoredRun(timeline: StoredTimeline())).entries.isEmpty)
    }

    /// Osa, která svůj konec **má**, se nesmí doplnit podruhé — dvě `doběhlo` pod sebou.
    @Test("Osa s koncem se nedoplňuje")
    func doesNotDuplicateTheTail() {
        var source = timeline(entries: 1)
        source.record(.findings(count: 4), at: Date(timeIntervalSince1970: 1_000_050))
        source.finish(.timedOut, at: Date(timeIntervalSince1970: 1_000_060))

        let restored = ReviewerTimeline(makeStoredRun(outcome: .timedOut, timeline: source.stored()))

        #expect(restored.entries.count == source.entries.count)
        #expect(restored.entries.count { if case .finished = $0.kind { true } else { false } } == 1)
    }
}
