import Foundation
import Testing

@testable import PRism

/// Ukládání kontroly nálezů (#150).
///
/// Nejcennější test je tady ten, který tvrdí, že se něco **nestalo**: kontrola se nesmí uložit
/// jako běh reviewera. Kdyby se to povedlo, přepsala by běh téhož skillu, přidala si chip
/// a v návrhu verdiktu by mluvila nálezy, které nikdy nenahlásila.
@Suite("ReviewStore — kontrola nálezů")
struct ReviewStoreRecheckTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let store: ReviewStore
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        store = ReviewStore(layout: layout, time: FakeTimeSource(start: now))
    }

    private func run(headSha: String, findings: [ReportedFinding] = []) -> ReviewRun {
        var summary = StreamSummary()
        summary.findings = findings
        summary.calledReportFindings = true
        return ReviewRun(
            key: ReviewRunKey(pullRequest: pr, headSha: headSha, skillID: "code-review"),
            summary: summary,
            outcome: .finished
        )
    }

    private func recheck(_ statuses: [FindingKey: RecheckStatus] = [:]) -> StoredRecheck {
        StoredRecheck(
            againstHeadSha: "new2222",
            outcome: .finished,
            sessionID: "session-1",
            statuses: statuses,
            finishedAt: now
        )
    }

    @Test("Kontrola se uloží k nálezům, na které se ptala")
    func theRecheckLandsOnTheFindingsRecord() async throws {
        let reported = makeReported(file: "Cart.swift", line: 13, summary: "chybí kontrola")
        try await store.save(run(headSha: "old1111", findings: [reported]))
        let finding = try #require(await store.record(for: pr, at: "old1111")?.findings.first)

        let record = try await store.saveRecheck(
            recheck([Policy.key(of: finding): RecheckStatus(verdict: .resolved, note: "opraveno")]),
            for: pr,
            at: "old1111"
        )

        #expect(record.recheck?.againstHeadSha == "new2222")
        #expect(record.recheck?.statuses[Policy.key(of: finding)]?.verdict == .resolved)
        // A po restartu je to pořád tam — kontrola stojí peníze, takže ji nesmí sebrat zavření okna.
        let reloaded = await store.record(for: pr, at: "old1111")
        #expect(reloaded?.recheck?.statuses.count == 1)
        // Nálezy zůstávají **všechny**: „vyřešeno“ nic neschovává.
        #expect(reloaded?.activeFindings.count == 1)
    }

    /// Zastaralost je vlastnost nálezů, ne kontroly: pořád patří ke staršímu commitu, i když se
    /// na ně někdo ptal. `save` ji srovnává, tohle ne.
    @Test("Kontrola nesrovná zastaralost záznamu")
    func theRecheckKeepsTheRecordStale() async throws {
        try await store.save(run(headSha: "old1111", findings: [makeReported()]))
        // Druhý běh nad novou hlavou označí ten starší za zastaralý.
        try await store.save(run(headSha: "new2222"))

        let record = try await store.saveRecheck(recheck(), for: pr, at: "old1111")

        #expect(record.isStale)
    }

    /// Nálezy, na které se kontrola ptala, byly vidět v okně — takže na disku být musí. Nový
    /// prázdný záznam by je všechny zahodil a kontrola by v něm mluvila o nálezech, které v něm
    /// nejsou. Tatáž úvaha jako u odmítnutí (#113).
    @Test("Chybějící záznam je chyba, ne nový soubor")
    func aMissingRecordIsAnError() async throws {
        await #expect(throws: ReviewStoreError.recordNotFound(pr, headSha: "old1111")) {
            try await store.saveRecheck(recheck(), for: pr, at: "old1111")
        }
        #expect(await store.record(for: pr, at: "old1111") == nil)
    }

    /// Odkaz je totéž co chybějící soubor (#106): **náš** záznam tam není a přečíst cizí kvůli
    /// zápisu do něj je to poslední, co chceme.
    @Test("Do odkazu se nezapisuje")
    func aSymlinkIsNotWritten() async throws {
        let outside = directory.url.appendingPathComponent("cizi.json")
        try Data("{}".utf8).write(to: outside)
        let url = layout.reviewFile(for: pr, at: "old1111")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)

        await #expect(throws: ReviewStoreError.recordNotFound(pr, headSha: "old1111")) {
            try await store.saveRecheck(recheck(), for: pr, at: "old1111")
        }
        #expect(try Data(contentsOf: outside) == Data("{}".utf8))
    }

    /// Kontrola **není běh reviewera** a `save` ji nesmí pustit do `runs`.
    @Test("Kontrola se neuloží jako běh reviewera")
    func aRecheckRunIsNotSavedAsAReview() async throws {
        try await store.save(run(headSha: "old1111", findings: [makeReported()]))
        let before = await store.record(for: pr, at: "old1111")

        let recheckRun = ReviewRun(
            key: .recheck(of: pr, at: "old1111"),
            summary: StreamSummary(),
            outcome: .finished
        )
        await #expect(throws: ReviewStoreError.notAReviewRun(kind: .recheck)) {
            try await store.save(recheckRun)
        }

        // A záznam zůstal, jaký byl — žádný běh navíc, žádný přepsaný.
        let after = await store.record(for: pr, at: "old1111")
        #expect(after == before)
        #expect(after?.runs.map(\.skillID) == ["code-review"])
    }
}
