import Foundation
import Testing

@testable import PRism

/// Souhrn nad frontou PR (#155). Čistá funkce, takže vyčerpávajícím výčtem a bez mockování.
///
/// To hlavní, co se tu dá pokazit potichu, jsou dvě věci: **počítat nálezy místo PR** (souhrn by pak
/// tvrdil víc práce, než kolik jí je) a **počítat odmítnuté nálezy** (#113) mezi blokující.
@Suite("Souhrn fronty")
struct QueueSummaryTests {
    private func pullRequest(_ number: Int, repo: String = "cli/cli") -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID(repo)!, number: number),
            title: "PR \(number)",
            author: "kdosi",
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_000_000),
            state: .open
        )
    }

    /// Záznam s jedním blokujícím nálezem (`correctness` je v výchozích blokujících kategoriích).
    private func blockingRecord(dismissed: Bool = false) -> ReviewRecord {
        let finding = makeReported(category: "correctness", verdict: .confirmed)
        var record = makeRecord(runs: [makeStoredRun(findings: [finding])])
        if dismissed {
            record.dismissals = makeDismissals(record.findings)
        }
        return record
    }

    private func cleanRecord() -> ReviewRecord {
        makeRecord(runs: [makeStoredRun(findings: [])])
    }

    private func draft(_ pr: PRIdentifier, body: String = "poznámka") -> ReviewDraft {
        ReviewDraft(pullRequest: pr, headSha: "aaaa1111", body: body)
    }

    private func summary(
        _ pullRequests: [PullRequestSummary],
        records: [PRIdentifier: ReviewRecord] = [:],
        drafts: [PRIdentifier: ReviewDraft] = [:]
    ) -> QueueSummary {
        Policy.summary(of: pullRequests, records: records, drafts: drafts)
    }

    // MARK: - Počty

    @Test("Prázdná fronta dá prázdný souhrn")
    func countsNothingWithoutPullRequests() {
        let result = summary([])

        #expect(result.pullRequests == 0)
        #expect(result.blocking == 0)
        #expect(result.drafts == 0)
        #expect(result.isEmpty)
    }

    @Test("Bez záznamů a draftů se počítají jen PR")
    func countsOnlyPullRequestsWithoutRecords() {
        let result = summary([pullRequest(1), pullRequest(2)])

        #expect(result.pullRequests == 2)
        #expect(result.blocking == 0)
        #expect(result.drafts == 0)
        #expect(!result.isEmpty)
    }

    /// **Počítají se PR, ne nálezy.** Tři blokující nálezy na jednom PR jsou jedna položka práce —
    /// „na kolik věcí se musím podívat“ je otázka, na kterou souhrn odpovídá.
    @Test("Tři blokující nálezy na jednom PR dají jedničku")
    func countsPullRequestsNotFindings() {
        let pr = pullRequest(1)
        let findings = (0..<3).map { makeReported(line: 10 + $0, category: "correctness", verdict: .confirmed) }
        let record = makeRecord(runs: [makeStoredRun(findings: findings)])

        let result = summary([pr], records: [pr.id: record])

        #expect(result.blocking == 1)
        #expect(record.activeFindings.count == 3)
    }

    @Test("Blokující se počítá u každého PR zvlášť")
    func countsBlockingPerPullRequest() {
        let first = pullRequest(1)
        let second = pullRequest(2)
        let third = pullRequest(3)

        let result = summary(
            [first, second, third],
            records: [first.id: blockingRecord(), second.id: cleanRecord(), third.id: blockingRecord()]
        )

        #expect(result.pullRequests == 3)
        #expect(result.blocking == 2)
    }

    /// **Nejcennější test téhle sady.** Odmítnutý nález (#113) není důvod k vyrušení — a kdyby se
    /// počítal, souhrn by se rozešel s řádkem seznamu, který ho už neukazuje.
    @Test("Odmítnutý blokující nález se nepočítá")
    func ignoresDismissedFindings() {
        let pr = pullRequest(1)

        let result = summary([pr], records: [pr.id: blockingRecord(dismissed: true)])

        #expect(result.blocking == 0)
    }

    /// Kategorie se dají přenastavit, takže se musí brát ta předaná — jinak by souhrn tvrdil něco
    /// jiného než řádek seznamu u repa s vlastním nastavením.
    @Test("Blokující kategorie se berou z parametru")
    func honoursTheBlockingCategories() {
        let pr = pullRequest(1)
        let record = blockingRecord()

        let none = Policy.summary(of: [pr], records: [pr.id: record], drafts: [:], categories: [])
        let custom = Policy.summary(
            of: [pr],
            records: [pr.id: record],
            drafts: [:],
            categories: ["correctness"]
        )

        #expect(none.blocking == 0)
        #expect(custom.blocking == 1)
    }

    @Test("Rozdělaná review se počítají")
    func countsDrafts() {
        let first = pullRequest(1)
        let second = pullRequest(2)

        let result = summary([first, second], drafts: [first.id: draft(first.id)])

        #expect(result.drafts == 1)
    }

    /// **Prázdný draft se nepočítá.** Vzniká i tím, že se otevře panel a napíše se do něj znak,
    /// který se pak smaže — „rozdělané review“ má znamenat, že je co poslat.
    @Test("Prázdný draft se za rozdělané review nepočítá")
    func ignoresAnEmptyDraft() {
        let pr = pullRequest(1)

        let result = summary([pr], drafts: [pr.id: draft(pr.id, body: "")])

        #expect(result.drafts == 0)
        #expect(draft(pr.id, body: "").isEmpty)
    }

    // MARK: - Co do souhrnu nepatří

    /// Záznam nebo draft PR, které ve frontě **není** (mezitím se zavřelo, ale na disku zůstalo),
    /// se počítat nesmí: souhrn mluví o tom, co v seznamu leží.
    @Test("Záznam a draft cizího PR se nepřipletou")
    func ignoresEntriesOutsideTheQueue() {
        let inQueue = pullRequest(1)
        let gone = pullRequest(99)

        let result = summary(
            [inQueue],
            records: [gone.id: blockingRecord()],
            drafts: [gone.id: draft(gone.id)]
        )

        #expect(result.pullRequests == 1)
        #expect(result.blocking == 0)
        #expect(result.drafts == 0)
    }

    /// Jedno PR může mít obojí — a nesmí se tím počítat dvakrát jako práce navíc.
    @Test("PR s blokujícím nálezem i draftem je v obou počtech")
    func countsBothForTheSamePullRequest() {
        let pr = pullRequest(1)

        let result = summary([pr], records: [pr.id: blockingRecord()], drafts: [pr.id: draft(pr.id)])

        #expect(result.pullRequests == 1)
        #expect(result.blocking == 1)
        #expect(result.drafts == 1)
    }

    /// Fronta přes víc rep se sčítá dohromady — je to jedna fronta.
    @Test("PR z různých rep se sečtou")
    func countsAcrossRepositories() {
        let first = pullRequest(1)
        let second = pullRequest(2, repo: "ondrajodas/PRism")

        let result = summary([first, second], records: [second.id: blockingRecord()])

        #expect(result.pullRequests == 2)
        #expect(result.blocking == 1)
    }
}
