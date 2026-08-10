import Foundation
import Testing

@testable import PRism

/// Proč je prázdno v nálezech (#242).
///
/// Testy tvrdí hlavně to, co se **nesmí** stát: že se `clean` nikdy nezamění za schované filtrem
/// ani za spadlou session. Prázdná obrazovka se čte jako „čisto“, a schválený PR s neohlášenou
/// chybou je nejdražší chyba, kterou tahle aplikace umí udělat.
@Suite("Policy — prázdné nálezy")
struct FindingsEmptyReasonTests {
    @Test("Když je co ukázat, žádný důvod není")
    func nonEmpty() {
        let reason = Policy.findingsEmptyReason(
            visible: [makeFinding(file: "a.php", line: 1)],
            record: nil,
            isRunning: false
        )

        #expect(reason == nil)
    }

    @Test("Bez záznamu a bez běhu se nic nespustilo")
    func nothingRan() {
        #expect(Policy.findingsEmptyReason(visible: [], record: nil, isRunning: false) == .nothingRan)
    }

    @Test("Bez záznamu za běhu se čeká na nálezy")
    func running() {
        #expect(Policy.findingsEmptyReason(visible: [], record: nil, isRunning: true) == .running)
    }

    /// Schované nálezy nejsou žádné nálezy. Kdyby tahle věta chyběla, zapnutý filtr reviewerů by
    /// vypadal jako čisté review — tedy jako PR bez nálezů.
    @Test("Nálezy schované filtrem se nesmí splést s čistým review")
    func hiddenByFilter() {
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported(file: "a.php", line: 1)])])

        let reason = Policy.findingsEmptyReason(visible: [], record: record, isRunning: false)

        #expect(reason == .hiddenByReviewerFilter)
    }

    @Test("Doběhlé review s prázdným seznamem je čisto")
    func clean() {
        let record = makeRecord(runs: [makeStoredRun(findings: [])])

        #expect(Policy.findingsEmptyReason(visible: [], record: record, isRunning: false) == .clean)
    }

    @Test("Spadlá session není čisto a nese svůj důvod")
    func failed() {
        let record = makeRecord(runs: [
            makeStoredRun(outcome: .failed(detail: "Unknown skill: perf-review")),
        ])

        #expect(Policy.findingsEmptyReason(visible: [], record: record, isRunning: false)
            == .failed("Unknown skill: perf-review"))
    }

    /// Regrese, kterou by šlo zavést jedním řádkem: kdyby se u záznamu bez nálezů ptalo dřív na
    /// běh než na stav, spadlá session by se za běhu ohlásila jako „review běží“.
    @Test("Spadlá session zůstane spadlá i tehdy, když jiný reviewer ještě běží")
    func failedWhileRunning() {
        let record = makeRecord(runs: [makeStoredRun(outcome: .failed(detail: "kód 1"))])

        #expect(Policy.findingsEmptyReason(visible: [], record: record, isRunning: true)
            == .failed("kód 1"))
    }
}
