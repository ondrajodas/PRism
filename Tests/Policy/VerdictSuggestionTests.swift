import Foundation
import Testing

@testable import PRism

@Suite("Policy.suggestedVerdict")
struct VerdictSuggestionTests {
    @Test("Doběhlé review bez nálezů navrhne approve")
    func aCleanRunSuggestsApprove() {
        let record = makeRecord(runs: [makeStoredRun()])

        #expect(Policy.suggestedVerdict(for: record) == .approve)
    }

    @Test("Samotné PLAUSIBLE nálezy approve nezruší")
    func plausibleFindingsDoNotChangeTheVerdict() {
        let record = makeRecord(runs: [
            makeStoredRun(findings: [makeReported(verdict: .plausible)]),
        ])

        #expect(Policy.suggestedVerdict(for: record) == .approve)
    }

    @Test("Blokující nález navrhne request changes")
    func aBlockingFindingSuggestsRequestChanges() {
        let record = makeRecord(runs: [
            makeStoredRun(findings: [makeReported(category: "security", verdict: .confirmed)]),
        ])

        #expect(Policy.suggestedVerdict(for: record) == .requestChanges)
    }

    @Test("Neblokující nálezy approve nezruší")
    func nonBlockingFindingsStillApprove() {
        let record = makeRecord(runs: [
            makeStoredRun(findings: [makeReported(category: "style", verdict: .confirmed)]),
        ])

        #expect(Policy.suggestedVerdict(for: record) == .approve)
    }

    // MARK: - Kdy návrh nevznikne

    @Test("Spadlá session návrh nedá")
    func aFailedRunSuggestsNothing() {
        // Schválit PR proto, že reviewer spadl, je nejdražší chyba, kterou umíme udělat.
        let record = makeRecord(runs: [makeStoredRun(outcome: .failed(detail: "Invalid API key"))])

        #expect(Policy.suggestedVerdict(for: record) == nil)
    }

    @Test("Vytimeoutovaná session sama o sobě návrh nedá")
    func aTimedOutRunAloneSuggestsNothing() {
        let record = makeRecord(runs: [makeStoredRun(outcome: .timedOut)])

        #expect(Policy.suggestedVerdict(for: record) == nil)
    }

    @Test("Nález z vytimeoutované session ale platí")
    func aFindingFromATimedOutRunStillCounts() {
        // Session se nedopočítala; co stihla nahlásit, je pořád pravda.
        let record = makeRecord(runs: [
            makeStoredRun(
                outcome: .timedOut,
                findings: [makeReported(category: "correctness", verdict: .confirmed)]
            ),
        ])

        #expect(Policy.suggestedVerdict(for: record) == .requestChanges)
    }

    @Test("Nález ze spadlé session platí i vedle čistého běhu")
    func aFindingFromAFailedRunOutweighsACleanOne() {
        // Klíčový případ: kdyby se nálezy ze spadlých běhů zahazovaly, tenhle záznam by
        // navrhl **approve** — a to navzdory nahlášené ztrátě dat, kterou má v sobě.
        // Spadlý je *běh*, ne nález; ten dorazil jako celý `ReportFindings` call.
        let record = makeRecord(runs: [
            makeStoredRun(
                skill: "security-review",
                outcome: .failed(detail: "spadlo po nálezu"),
                findings: [makeReported(category: "data-loss", verdict: .confirmed)]
            ),
            makeStoredRun(skill: "code-review"),
        ])

        #expect(Policy.suggestedVerdict(for: record) == .requestChanges)
    }

    @Test("Spadlá session s nálezem sama o sobě blokuje")
    func aFailedRunWithAFindingStillBlocks() {
        let record = makeRecord(runs: [
            makeStoredRun(
                outcome: .failed(detail: "spadlo"),
                findings: [makeReported(category: "correctness", verdict: .confirmed)]
            ),
        ])

        #expect(Policy.suggestedVerdict(for: record) == .requestChanges)
    }

    @Test("Nezavolaný ReportFindings není čisté review")
    func aRunThatNeverReportedSuggestsNothing() {
        // Nálezy se neměly kde vzít — typicky proto, že nástroj chyběl v `--allowedTools`.
        let record = makeRecord(runs: [makeStoredRun(calledReportFindings: false)])

        #expect(Policy.suggestedVerdict(for: record) == nil)
    }

    @Test("Zahozený nález approve zruší")
    func droppedFindingsPreventApprove() {
        // Reviewer něco hlásil a aplikace to nepřečetla. Tvářit se, že je čisto, by z toho
        // udělalo schválený PR s neohlášenou chybou.
        let record = makeRecord(runs: [makeStoredRun(droppedFindings: 1)])

        #expect(Policy.suggestedVerdict(for: record) == nil)
    }

    @Test("Zahozený nález v jednom běhu bere approve celému záznamu")
    func droppedFindingsAnywherePreventApprove() {
        // Čistý výsledek jiného skillu o tom ztraceném nálezu nic neříká — je to známá
        // neznámá, ne důkaz, že je čisto.
        let record = makeRecord(runs: [
            makeStoredRun(skill: "code-review"),
            makeStoredRun(skill: "security-review", droppedFindings: 1),
        ])

        #expect(Policy.suggestedVerdict(for: record) == nil)
    }

    @Test("Blokující nález má přednost i před zahozeným")
    func aBlockingFindingWinsOverADroppedOne() {
        let record = makeRecord(runs: [
            makeStoredRun(
                skill: "code-review",
                findings: [makeReported(category: "correctness", verdict: .confirmed)]
            ),
            makeStoredRun(skill: "security-review", droppedFindings: 1),
        ])

        #expect(Policy.suggestedVerdict(for: record) == .requestChanges)
    }

    @Test("Zastaralý záznam návrh nedá, ani kdyby byl čistý")
    func aStaleRecordSuggestsNothing() {
        // Mluvil by o commitu, který v PR není.
        let clean = makeRecord(runs: [makeStoredRun()], isStale: true)
        let blocking = makeRecord(
            runs: [makeStoredRun(findings: [makeReported(verdict: .confirmed)])],
            isStale: true
        )

        #expect(Policy.suggestedVerdict(for: clean) == nil)
        #expect(Policy.suggestedVerdict(for: blocking) == nil)
    }

    @Test("Záznam bez běhů návrh nedá")
    func anEmptyRecordSuggestsNothing() {
        #expect(Policy.suggestedVerdict(for: makeRecord(runs: [])) == nil)
    }

    @Test("Stačí jeden použitelný běh vedle spadlých")
    func oneConclusiveRunIsEnough() {
        let record = makeRecord(runs: [
            makeStoredRun(skill: "code-review", outcome: .failed(detail: "spadlo")),
            makeStoredRun(skill: "security-review"),
        ])

        #expect(Policy.suggestedVerdict(for: record) == .approve)
    }

    @Test("Blokující sada rozhoduje i o verdiktu")
    func theBlockingSetDecidesTheVerdictToo() {
        let record = makeRecord(runs: [
            makeStoredRun(findings: [makeReported(category: "style", verdict: .confirmed)]),
        ])

        #expect(Policy.suggestedVerdict(for: record, categories: ["style"]) == .requestChanges)
    }
}
