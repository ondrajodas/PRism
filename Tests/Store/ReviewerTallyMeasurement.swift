import Foundation
import Testing

@testable import PRism

/// Kolik stojí součet odmítnutí (#514) — tedy **druhý průchod výpisem `reviews/`**, který
/// `AppStore.refreshReviewerTallies()` přidává ke startu a k odmítnutí nálezu.
///
/// Proč měření a ne test: otázka zní „je ta cena taková, že se za jedno místo, kde se součet
/// skládá, dá zaplatit“, a odpověď je číslo, ne tvrzení. Číslo se **rozpadá na dvě půlky** —
/// čtení a dekódování (`ReviewStore.load()`) a samotný fold (`Policy.reviewerTallies`) —, protože
/// zlevnit jde jedině ta větší z nich; zlevnění, které práci jen přesune, není zlevnění (#275).
///
/// Velikost vzorku odpovídá skutečné cache (změřeno 17. 9. 2026 na hlavní instanci: **33 souborů,
/// 2,6 MB**), a `findingsPerRun` je nastavené tak, aby vzorek na tu velikost vyšel — **rozhoduje
/// objem, ne počet souborů**: nad třiatřiceti soubory o 372 kB vyšlo `load()` na 3,0 ms, nad
/// týmiž třiatřiceti o 2,5 MB na 11,5 ms.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1` (prefix `TEST_RUNNER_` je to, čím se
/// proměnná dostane do testovacího hosta — bez něj se suite jen přeskočí a vypadá to zeleně).
@Suite(
    "Cena součtu po reviewerech (#514)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct ReviewerTallyMeasurement {
    private let files = 33
    private let findingsPerRun = 84

    @Test("Změřit čtení výpisu a fold")
    func measuresTheWalkAndTheFold() async throws {
        let directory = try TemporaryDirectory()
        let layout = CacheLayout(root: directory.url)
        let time = FakeTimeSource()
        let store = ReviewStore(layout: layout, time: time)
        for index in 0..<files {
            try await store.save(run(number: index))
        }
        let bytes = try size(of: layout.reviews)

        // Střídavě A/B/A/B (#274): první čtení hřeje cache souborového systému, takže by samotné
        // pořadí rozhodlo, která půlka vyjde dráž.
        var walk: [Double] = []
        var fold: [Double] = []
        for _ in 0..<5 {
            let beforeWalk = Date()
            let records = try await store.load().records
            walk.append(Date().timeIntervalSince(beforeWalk))
            let beforeFold = Date()
            _ = Policy.reviewerTallies(from: records, now: time.now)
            fold.append(Date().timeIntervalSince(beforeFold))
        }

        print("MĚŘENÍ souborů=\(files) velikost=\(bytes / 1024) kB")
        print("MĚŘENÍ load() medián=\(median(walk) * 1000) ms")
        print("MĚŘENÍ fold medián=\(median(fold) * 1000) ms")
    }

    private func median(_ samples: [Double]) -> Double {
        samples.sorted()[samples.count / 2]
    }

    private func size(of directory: URL) throws -> Int {
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        var total = 0
        while let url = files?.nextObject() as? URL {
            total += try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        }
        return total
    }

    /// Běh o velikosti, jakou mají soubory ve skutečné cache — nálezy s celými větami. Osa
    /// (`StoredTimeline`) se neskládá: do dekódování vstupuje **objem JSONu**, a ten se stejně
    /// dobře nasype nálezy; skládat kvůli bajtům druhou strukturu by měřidlo jen zesložitilo.
    private func run(number: Int) -> ReviewRun {
        var summary = StreamSummary()
        summary.calledReportFindings = true
        summary.findings = (0..<findingsPerRun).map { index in
            ReportedFinding(
                file: "src/Component/Cart\(index).swift",
                line: index * 7,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: "nález \(index)",
                summary: String(repeating: "Metoda total() ignoruje množství položky. ", count: 6),
                failureScenario: String(repeating: "Košík se dvěma kusy vyjde na cenu jednoho. ", count: 6)
            )
        }
        return ReviewRun(
            key: ReviewRunKey(
                pullRequest: PRIdentifier(repo: RepoID(owner: "keboola", name: "job-queue"), number: number),
                headSha: "aaaa\(number)",
                skillID: "code-review"
            ),
            summary: summary,
            outcome: .finished
        )
    }
}
