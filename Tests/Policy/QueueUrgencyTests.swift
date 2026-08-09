import Foundation
import Testing

@testable import PRism

/// Pořadí fronty na dashboardu (#181). Čistá funkce nad výčtem stavů, takže vyčerpávajícím výčtem.
///
/// Co se tu dá pokazit potichu: **prohodit dvě patra** (běžící review nad nálezy vypadá jako
/// řazení podle času a nikdo si toho nevšimne) a **rozhoupat pořadí** — bez druhého kritéria by
/// řádky mezi tiky poskakovaly pod rukama.
@Suite("Pořadí fronty podle závažnosti")
struct QueueUrgencyTests {
    private func entry(
        _ number: Int,
        state: ReviewState,
        blocking: Int = 0,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> QueueEntry {
        QueueEntry(
            pullRequest: PullRequestSummary(
                id: PRIdentifier(repo: RepoID("cli/cli")!, number: number),
                title: "PR \(number)",
                author: "kdosi",
                url: URL(string: "https://github.com/cli/cli/pull/\(number)")!,
                updatedAt: updatedAt,
                state: .open
            ),
            state: state,
            row: QueueRow(blocking: blocking, spectrum: []),
            hasDraft: false
        )
    }

    /// Celá škála naráz, od nejnaléhavějšího po to, co po mně nechce nic. Vstup je schválně
    /// obrácený, ať se pozná i pořadí, které by prošlo bez řazení.
    @Test("Celá škála od blokujícího po čisté")
    func ordersTheWholeScale() {
        let scale: [QueueEntry] = [
            entry(1, state: .completed(findings: 3), blocking: 1),
            entry(2, state: .completed(findings: 2)),
            entry(3, state: .failed(detail: "spadlo")),
            entry(4, state: .stale),
            entry(5, state: .notStarted),
            entry(6, state: .running(finished: 1, total: 3)),
            entry(7, state: .dismissed(findings: 2)),
            entry(8, state: .clean),
        ]

        let sorted = Policy.byUrgency(scale.reversed())

        #expect(sorted.map(\.pullRequest.number) == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    /// **Blokující nález přebíjí i to, že jich je míň.** Řádek s jedním blokujícím je práce, kterou
    /// nejde odložit; pět kosmetických počká.
    @Test("Jeden blokující je výš než pět nálezů")
    func putsBlockingFirst() {
        let sorted = Policy.byUrgency([
            entry(1, state: .completed(findings: 5)),
            entry(2, state: .completed(findings: 1), blocking: 1),
        ])

        #expect(sorted.map(\.pullRequest.number) == [2, 1])
    }

    /// Blokující nález platí i z půlky session, takže nedoběhlý běh s ním patří nahoru — bez něj
    /// je to zpráva o běhu, ne výsledek.
    @Test("Nedoběhlý běh jde nahoru jen s blokujícím nálezem")
    func liftsAnInterruptedRunOnlyWhenItBlocks() {
        let sorted = Policy.byUrgency([
            entry(1, state: .completed(findings: 1)),
            entry(2, state: .timedOut(findings: 2)),
            entry(3, state: .interrupted(findings: 1), blocking: 1),
        ])

        #expect(sorted.map(\.pullRequest.number) == [3, 1, 2])
    }

    /// **Nejcennější test téhle sady.** Nálezy zastaralého záznamu patří ke staršímu `headSha`
    /// (tvrdá podmínka č. 5), takže o dnešním kódu netvrdí nic — a pořadí na nich stavět nesmí.
    @Test("Zastaralé nejde nahoru, ani když nese blokující nález")
    func doesNotLiftStaleFindings() {
        let sorted = Policy.byUrgency([
            entry(1, state: .stale, blocking: 3),
            entry(2, state: .completed(findings: 1)),
            entry(3, state: .notStarted),
        ])

        #expect(sorted.map(\.pullRequest.number) == [2, 1, 3])
    }

    @Test("Uvnitř patra rozhoduje čas změny")
    func ordersByTimeInsideARank() {
        let old = Date(timeIntervalSince1970: 900_000)
        let sorted = Policy.byUrgency([
            entry(1, state: .notStarted, updatedAt: old),
            entry(2, state: .notStarted, updatedAt: old.addingTimeInterval(3600)),
        ])

        #expect(sorted.map(\.pullRequest.number) == [2, 1])
    }

    /// Bez druhého kritéria by se pořadí dvou PR se stejným razítkem měnilo mezi tiky a řádky by
    /// pod rukou poskakovaly.
    @Test("Při shodě času rozhoduje identifikátor")
    func breaksTiesDeterministically() {
        let sorted = Policy.byUrgency([entry(7, state: .clean), entry(3, state: .clean)])

        #expect(sorted.map(\.pullRequest.number) == [3, 7])
    }

    @Test("Prázdná fronta zůstane prázdná")
    func handlesAnEmptyQueue() {
        #expect(Policy.byUrgency([]).isEmpty)
    }
}
