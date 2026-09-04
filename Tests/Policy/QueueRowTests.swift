import Foundation
import Testing

@testable import PRism

/// `Policy.queueRow` — odvozená čísla pro jeden řádek seznamu (#172).
///
/// **Od #502 je to jedno číslo, ne dvě.** Druhým bylo `spectrum`, tedy podíl reviewerů na
/// výsledku; v řádku ho vystřídala mapa PR, takže se ta část odsud vypustila. Nezmizelo s ní
/// pokrytí, jen se přestalo tvrdit dvakrát:
///
/// - **rozhodnutí „čisto versus nemám co říct“** (a `dismissed` mezi nimi) drží `Policy.chips`
///   a testuje se u chipu revieweera — `ReviewerChipTests` a `UnreadCodeStateTests`. Proužek si
///   ho počítal **znovu**, což byla ta vada, kterou #383 muselo opravovat na dvou místech;
/// - **že nález cizího revieweera nezčervená jiný díl** bylo tvrzení o proužku, tedy o kresbě,
///   která odešla. Nad mapou je jeho protějšek jinde a je to jiná otázka: že nález obarví jen
///   **svůj soubor** (`PullRequestMapTests`).
@Suite("Policy.queueRow")
struct QueueRowTests {
    @Test("PR bez záznamu nemá co ukázat")
    func aPullRequestWithoutARecordHasNothingToShow() {
        // Prázdno, ne nula: řádek se má vykreslit bez pásu i bez počtu, ne s „0 nálezů".
        #expect(Policy.queueRow(for: nil) == .empty)
        #expect(Policy.queueRow(for: makeRecord(runs: [])) == .empty)
    }

    @Test("Blokující nález se v řádku spočítá")
    func aBlockingFindingIsCounted() {
        let record = makeRecord(runs: [
            makeStoredRun(findings: [
                makeReported(category: "correctness", verdict: .confirmed),
                makeReported(category: "style", verdict: .confirmed),
            ])
        ])

        #expect(Policy.queueRow(for: record).blocking == 1)
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

        #expect(Policy.queueRow(for: record).blocking == 0)
    }

    @Test("Nedoběhlý běh si nálezy nechává")
    func anUnfinishedRunKeepsWhatItFound() {
        // Blokující nález platí i z poloviny běhu: co našel, se počítá, i když nedoběhl.
        let withFindings = makeRecord(runs: [
            makeStoredRun(outcome: .timedOut, findings: [
                makeReported(category: "correctness", verdict: .confirmed)
            ])
        ])
        let empty = makeRecord(runs: [makeStoredRun(outcome: .timedOut)])

        #expect(Policy.queueRow(for: withFindings).blocking == 1)
        // Zabitý běh bez nálezů nic neblokuje — ale **prázdný záznam to není**: běh v něm je,
        // takže se řádek od PR bez review pořád pozná (a mapa PR se u něj kreslí).
        #expect(Policy.queueRow(for: empty).blocking == 0)
        #expect(Policy.queueRow(for: empty) == .empty)
    }

    @Test("Blokující sada per repo se propíše do řádku")
    func theRepositoryBlockingSetAppliesToTheRow() {
        let record = makeRecord(runs: [
            makeStoredRun(findings: [makeReported(category: "style", verdict: .confirmed)])
        ])

        #expect(Policy.queueRow(for: record).blocking == 0)
        #expect(Policy.queueRow(for: record, categories: ["style"]).blocking == 1)
    }
}
