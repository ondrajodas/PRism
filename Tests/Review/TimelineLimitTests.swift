import Foundation
import Testing

@testable import PRism

/// Strop **živé** osy (#325).
///
/// Do #325 platil jen na ukládání: `record` přidával bez omezení, takže patnáctiminutová session
/// držela stovky událostí, které po restartu zmizely — a nikde to nebylo napsané. Se stejným
/// číslem pro obojí platí, že **co bylo vidět za běhu, je vidět i po restartu**.
///
/// Dvě věci se u toho dají pokazit potichu: **oříznout konec místo začátku** (kdo se dívá do
/// běžícího výpisu, kouká na konec) a **zapomenout, čeho se běh dotkl** — ořez zahazuje první
/// události, tedy zrovna `čeká na slot` a `session naběhla`, takže by fáze dráhy po třech stech
/// krocích spadly zpátky na `nedošlo na ni`.
@Suite("Strop živé osy")
struct TimelineLimitTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// Osa s `count` kroky nad rámec `queued` + `started`.
    private func timeline(steps count: Int) -> ReviewerTimeline {
        var timeline = ReviewerTimeline(skill: "code-review", worktree: URL(filePath: "/tmp/wt"))
        timeline.record(.queued, at: start)
        timeline.record(.started(sessionID: "abc123"), at: start + 1)
        for index in 0..<count {
            timeline.record(
                .attemptedTool(ToolAttempt(name: "Read", detail: "soubor\(index).php", id: "t\(index)")),
                at: start + 2 + Double(index)
            )
        }
        return timeline
    }

    @Test("Živá osa se přes strop nepřeleje")
    func liveTimelineStopsAtTheLimit() {
        let timeline = timeline(steps: ReviewerTimeline.entryLimit + 40)

        #expect(timeline.entries.count == ReviewerTimeline.entryLimit)
        // Dvě události navíc (`queued`, `started`) plus 40 kroků nad strop.
        #expect(timeline.droppedEntries == 42)
    }

    /// **Ořezává se začátek**, ne konec.
    @Test("Ořezaná osa si nechá konec")
    func keepsTheEnd() {
        let timeline = timeline(steps: ReviewerTimeline.entryLimit + 40)

        guard case .tool(let last) = timeline.entries.last?.kind else {
            Issue.record("poslední událost není krok")
            return
        }
        #expect(last.detail == "soubor\(ReviewerTimeline.entryLimit + 39).php")
        // A první přeživší je ten, na kterém ořez skončil — ne `queued`, který v ose byl první.
        guard case .tool(let first) = timeline.entries.first?.kind else {
            Issue.record("první přeživší událost není krok")
            return
        }
        #expect(first.detail == "soubor40.php")
    }

    /// **Nejcennější test téhle sady** (že se něco NEstalo): ořez nesmí zapomenout, čím běh prošel.
    /// Kdyby se fáze počítaly průchodem přeživších událostí, dráha po třech stech krocích tvrdí, že
    /// session nenaběhla a že nálezy nenahlásila.
    @Test("Ořez nezapomene, čím běh prošel")
    func trimmingKeepsWhatHappened() {
        var timeline = timeline(steps: ReviewerTimeline.entryLimit)
        timeline.record(.findings(count: 3), at: start + 400)
        // A ještě tolik kroků, aby `findings` z osy vypadly.
        for index in 0..<(ReviewerTimeline.entryLimit + 10) {
            timeline.record(
                .attemptedTool(ToolAttempt(name: "Grep", detail: "vzor\(index)", id: "g\(index)")),
                at: start + 500 + Double(index)
            )
        }

        #expect(!timeline.entries.contains { if case .findings = $0.kind { true } else { false } })
        #expect(timeline.digest.reached == 3)
        #expect(timeline.digest.reportedFindings == 3)
        #expect(timeline.digest.hadQueued)

        let lane = Policy.lanes(of: [timeline], skills: ["code-review"], running: ["code-review"]).first
        #expect(lane?.phases.first?.title == ReviewerLane.Title.waiting)
        // `running`, protože dráha běží dál — rozhoduje, že fáze **není `idle`** a nese svůj
        // počet: to je ten návrat na „nedošlo na ni“, který by průchod ořezanou osou způsobil.
        #expect(lane?.phases.last == ReviewerLane.Phase(
            title: ReviewerLane.Title.findings,
            detail: "3",
            state: .running
        ))
    }

    /// Počet kroků naopak popisuje, co je **vidět** — takže ořezáním klesá. Přesně jak to má
    /// návrh: `prochází kód · 300 kroků` u osy, ze které se 214 nevešlo.
    @Test("Počet kroků popisuje, co je v ose vidět")
    func stepCountShrinksWithTrimming() {
        let timeline = timeline(steps: ReviewerTimeline.entryLimit + 40)

        #expect(timeline.digest.toolSteps == ReviewerTimeline.entryLimit)
    }

    /// Poslední krok ořezem zmizí **jedině tehdy, když byl v ose jediný** — ořez zpředu jiný
    /// poslední krok sebrat nemůže.
    @Test("Poslední krok ořez zpředu nesebere")
    func trimmingKeepsTheLastStep() {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: "první.php", id: "t0")), at: start)
        for index in 0..<ReviewerTimeline.entryLimit {
            timeline.record(.queued, at: start + 1 + Double(index))
        }

        #expect(timeline.digest.toolSteps == 0)
        #expect(timeline.digest.lastTool == nil)
        // A `reached` zůstává na kroku: běh se ke kódu dostal, i když ten krok už v ose není.
        #expect(timeline.digest.reached == 2)
    }

    /// Uložení ořezané osy sečte, co se nevešlo — dřív i teď. Bez toho by druhý zápis téže osy
    /// tvrdil, že chybí jen posledních pár událostí.
    @Test("Uložení ořezané osy zkrácení nesečte dvakrát")
    func storingATrimmedTimelineKeepsTheCount() {
        let timeline = timeline(steps: ReviewerTimeline.entryLimit + 40)

        let stored = timeline.stored()

        #expect(stored.entries.count == ReviewerTimeline.entryLimit)
        #expect(stored.dropped == 42)
    }

    /// Osa z disku dostane strop taky. Soubor ho má mít, ale spolehnout se na cizí data znamená
    /// mít v okně tři tisíce řádků kvůli starému formátu.
    @Test("Přerostlá uložená osa se při načtení ořeže")
    func trimsAnOversizedStoredTimeline() {
        let oversized = StoredTimeline(
            worktree: URL(filePath: "/tmp/wt"),
            entries: (0..<(ReviewerTimeline.entryLimit + 5)).map { index in
                ReviewerTimeline.Entry(id: index, at: start + Double(index), kind: .queued)
            },
            dropped: 7
        )

        let timeline = ReviewerTimeline(makeStoredRun(timeline: oversized, sessionID: "abc123"))

        #expect(timeline.entries.count == ReviewerTimeline.entryLimit)
        // Sedm z minula, pět nad strop a dva za doplněný konec (`hlásí nálezy` + `doběhlo`),
        // který se u načtené osy dopisuje — a i on se do stropu musí vejít.
        #expect(timeline.droppedEntries == 14)
    }
}
