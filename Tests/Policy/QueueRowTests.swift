import Foundation
import Testing

@testable import PRism

@Suite("Policy.queueRow")
struct QueueRowTests {
    @Test("PR bez záznamu nemá co ukázat")
    func aPullRequestWithoutARecordHasNothingToShow() {
        // Prázdno, ne nula: řádek se má vykreslit bez proužku i bez počtu, ne s „0 nálezů".
        #expect(Policy.queueRow(for: nil) == .empty)
        #expect(Policy.queueRow(for: makeRecord(runs: [])) == .empty)
        #expect(Policy.queueRow(for: nil).isEmpty)
    }

    @Test("Blokující nález se v řádku spočítá")
    func aBlockingFindingIsCounted() {
        let record = makeRecord(runs: [
            makeStoredRun(findings: [
                makeReported(category: "correctness", verdict: .confirmed),
                makeReported(category: "style", verdict: .confirmed),
            ])
        ])

        let row = Policy.queueRow(for: record)

        #expect(row.blocking == 1)
        #expect(row.spectrum.map(\.outcome) == [.blocking])
    }

    @Test("Odmítnutý nález řádek neblokuje")
    func aDismissedFindingDoesNotBlockTheRow() {
        // Nejdůležitější test v souboru: odmítnutí se dělá **kvůli tomuhle účinku**. Kdyby se
        // odmítnutý blokující nález pořád počítal, řádek by svítil červeně napořád a odmítnutí
        // by nemělo jak se projevit.
        let blocking = makeFinding(category: "correctness", verdict: .confirmed)
        var record = makeRecord(runs: [
            makeStoredRun(findings: [makeReported(category: "correctness", verdict: .confirmed)])
        ])
        record.dismissals = makeDismissals([blocking])

        let row = Policy.queueRow(for: record)

        #expect(row.blocking == 0)
        // A reviewer přestane být červený — proužek nesmí tvrdit něco jiného než odznak.
        // Ale ani zelený: „nic nenašel" a „našel a já to zamítl" jsou dvě tvrzení (#113).
        #expect(row.spectrum.map(\.outcome) == [.dismissed])
    }

    @Test("Každý běh má v proužku svůj díl, v pořadí běhů")
    func everyRunGetsItsShareInOrder() {
        let record = makeRecord(runs: [
            makeStoredRun(skill: "php-review", findings: [
                makeReported(category: "correctness", verdict: .confirmed),
                makeReported(category: "style", verdict: .confirmed),
            ]),
            makeStoredRun(skill: "security-review", findings: [
                makeReported(category: "style", verdict: .confirmed)
            ]),
            makeStoredRun(skill: "docs"),
        ])

        let row = Policy.queueRow(for: record)

        #expect(row.spectrum.map(\.reviewer) == ["php-review", "security-review", "docs"])
        #expect(row.spectrum.map(\.outcome) == [.blocking, .findings, .clean])
    }

    @Test("Čistý reviewer má v proužku váhu, ne nulu")
    func aCleanReviewerStillHasWeight() {
        // S nulovou váhou by z proužku zmizel — a zmizela by s ním informace, že vůbec běžel.
        let record = makeRecord(runs: [makeStoredRun(skill: "docs")])

        #expect(Policy.queueRow(for: record).spectrum.map(\.weight) == [1])
    }

    @Test("Váha dílu je počet platných nálezů")
    func theWeightIsTheNumberOfActiveFindings() {
        // Nálezy musí být rozlišitelné: `Policy.key(of:)` je skládá z revieweera, místa
        // a shrnutí — tři nálezy se stejným shrnutím jsou pro odmítnutí jeden a týž.
        var record = makeRecord(runs: [
            makeStoredRun(skill: "php-review", findings: [
                makeReported(category: "correctness", verdict: .confirmed, summary: "prázdný secret"),
                makeReported(category: "style", verdict: .confirmed, summary: "dlouhá metoda"),
                makeReported(category: "performance", verdict: .confirmed, summary: "N+1 dotaz"),
            ])
        ])

        #expect(Policy.queueRow(for: record).spectrum.map(\.weight) == [3])

        record.dismissals = makeDismissals([
            makeFinding(category: "style", verdict: .confirmed, summary: "dlouhá metoda", reviewer: "php-review")
        ])
        #expect(Policy.queueRow(for: record).spectrum.map(\.weight) == [2])
        // Blokující nález zůstal, takže díl zůstává červený.
        #expect(Policy.queueRow(for: record).spectrum.map(\.outcome) == [.blocking])
    }

    @Test("Čisté a nepovedené se v proužku nesmí slít")
    func cleanAndInconclusiveNeverMerge() {
        // Tatáž dvojice jako u `ReviewerChip`: reviewer, který nereportoval, nebo kterému se
        // ztratil nález, nesmí být zelený — jinak proužek tvrdí klid tam, kde se nálezy nemají
        // kde vzít.
        let clean = makeRecord(runs: [makeStoredRun(calledReportFindings: true)])
        let silent = makeRecord(runs: [makeStoredRun(calledReportFindings: false)])
        let dropped = makeRecord(runs: [makeStoredRun(droppedFindings: 2)])

        #expect(Policy.queueRow(for: clean).spectrum.map(\.outcome) == [.clean])
        #expect(Policy.queueRow(for: silent).spectrum.map(\.outcome) == [.inconclusive])
        #expect(Policy.queueRow(for: dropped).spectrum.map(\.outcome) == [.inconclusive])
    }

    @Test("Nedoběhlý běh si nálezy nechává, ale bez nich je nejistý")
    func anUnfinishedRunKeepsWhatItFound() {
        let withFindings = makeRecord(runs: [
            makeStoredRun(outcome: .timedOut, findings: [
                makeReported(category: "correctness", verdict: .confirmed)
            ])
        ])
        let empty = makeRecord(runs: [makeStoredRun(outcome: .timedOut)])
        let crashed = makeRecord(runs: [makeStoredRun(outcome: .failed(detail: "boom"))])

        #expect(Policy.queueRow(for: withFindings).spectrum.map(\.outcome) == [.blocking])
        #expect(Policy.queueRow(for: withFindings).blocking == 1)
        // Zabitý běh bez nálezů není čistý — o tom, co nestihl, nevíme nic.
        #expect(Policy.queueRow(for: empty).spectrum.map(\.outcome) == [.inconclusive])
        #expect(Policy.queueRow(for: crashed).spectrum.map(\.outcome) == [.inconclusive])
    }

    @Test("Blokující sada per repo se propíše do řádku")
    func theRepositoryBlockingSetAppliesToTheRow() {
        let record = makeRecord(runs: [
            makeStoredRun(findings: [makeReported(category: "style", verdict: .confirmed)])
        ])

        #expect(Policy.queueRow(for: record).blocking == 0)
        #expect(Policy.queueRow(for: record, categories: ["style"]).blocking == 1)
        #expect(Policy.queueRow(for: record, categories: ["style"]).spectrum.map(\.outcome) == [.blocking])
    }

    @Test("Nález cizího revieweera nezčervená jiný díl")
    func aFindingOnlyColoursItsOwnReviewer() {
        // Odmítnutí i nálezy visí na záznamu, takže se musí protnout se skillem běhu.
        // Bez toho by stačil jeden blokující nález, aby byl červený celý proužek.
        let record = makeRecord(runs: [
            makeStoredRun(skill: "php-review", findings: [
                makeReported(category: "correctness", verdict: .confirmed)
            ]),
            makeStoredRun(skill: "docs"),
        ])

        #expect(Policy.queueRow(for: record).spectrum.map(\.outcome) == [.blocking, .clean])
    }
}
