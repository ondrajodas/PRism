import Foundation
import Testing

@testable import PRism

/// Podklad pro startovní obrazovku (#181). Čistá funkce, takže výčtem a bez mockování.
///
/// Tři věci se tu dají pokazit potichu: **počítat drafty jinak než stavový řádek** (karta by pak
/// tvrdila trojku vedle jedničky), **vymyslet stáří draftu**, který razítko nemá, a **spočítat
/// nálezy reviewera z běhů, ze kterých už nic neplatí**.
@Suite("Dashboard")
struct DashboardTests {
    private func pullRequest(
        _ number: Int,
        repo: String = "cli/cli",
        updatedAt: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID(repo)!, number: number),
            title: "PR \(number)",
            author: "kdosi",
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
            updatedAt: updatedAt,
            state: .open
        )
    }

    private func draft(_ pr: PRIdentifier, body: String = "poznámka", updatedAt: Date? = nil) -> ReviewDraft {
        var draft = ReviewDraft(pullRequest: pr, headSha: "aaaa1111", body: body)
        draft.updatedAt = updatedAt
        return draft
    }

    private func blockingRecord(category: String = "correctness") -> ReviewRecord {
        makeRecord(runs: [makeStoredRun(findings: [makeReported(category: category, verdict: .confirmed)])])
    }

    private func dashboard(
        _ pullRequests: [PullRequestSummary],
        records: [PRIdentifier: ReviewRecord] = [:],
        drafts: [PRIdentifier: ReviewDraft] = [:],
        since: Date? = nil
    ) -> Dashboard {
        Policy.dashboard(pullRequests: pullRequests, records: records, drafts: drafts, since: since)
    }

    // MARK: - Fronta

    @Test("Prázdná fronta nemá co počítat")
    func countsNothingWithoutPullRequests() {
        let result = dashboard([])

        #expect(result.queue.pullRequests == 0)
        #expect(result.queue.repositories == 0)
        #expect(result.blocking.pullRequests == 0)
        #expect(result.blocking.detail == nil)
        #expect(result.drafts.pullRequests == 0)
        #expect(result.reviewers.isEmpty)
    }

    @Test("Repozitáře se počítají jednou, i když z nich přijde víc PR")
    func countsRepositoriesOnce() {
        let result = dashboard([
            pullRequest(1),
            pullRequest(2),
            pullRequest(3, repo: "ondrajodas/PRism"),
        ])

        #expect(result.queue.pullRequests == 3)
        #expect(result.queue.repositories == 2)
    }

    // MARK: - Blokující

    @Test("Blokuje se počítá po PR a nese kategorii i repo")
    func describesTheWorstBlockingFinding() {
        let first = pullRequest(1)
        let second = pullRequest(2, repo: "ondrajodas/PRism")

        let result = dashboard(
            [first, second],
            records: [first.id: blockingRecord(), second.id: blockingRecord()]
        )

        #expect(result.blocking.pullRequests == 2)
        #expect(result.blocking.detail == "correctness · cli/cli")
    }

    /// Nález bez kategorie se nedá popsat — a vymyslet mu ji by znamenalo tvrdit, proč se PR
    /// nemerguje, a mýlit se v tom.
    @Test("Bez kategorie zůstane karta u čísla")
    func leavesTheDetailEmptyWithoutACategory() {
        let pr = pullRequest(1)
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported(category: nil, verdict: .confirmed)])])

        let result = dashboard([pr], records: [pr.id: record])

        #expect(result.blocking.pullRequests == 0)
        #expect(result.blocking.detail == nil)
    }

    // MARK: - Rozdělaná review

    /// **Stejné pravidlo jako u souhrnu ve stavovém řádku** (#155): prázdný draft ani draft na PR
    /// mimo frontu se nepočítá. Do #181 se tu počítaly všechny drafty na disku a karta ukazovala
    /// trojku vedle stavového řádku s jedničkou.
    @Test("Počítá jen neprázdné drafty PR, které jsou ve frontě")
    func countsDraftsLikeTheStatusBar() {
        let inQueue = pullRequest(1)
        let empty = pullRequest(2)
        let gone = pullRequest(99)

        let result = dashboard(
            [inQueue, empty],
            drafts: [
                inQueue.id: draft(inQueue.id),
                empty.id: draft(empty.id, body: ""),
                gone.id: draft(gone.id),
            ]
        )

        #expect(result.drafts.pullRequests == 1)
        #expect(result.drafts.pullRequest == inQueue.id)
    }

    @Test("Nejstarší draft je ten s nejstarším razítkem")
    func picksTheOldestDraft() {
        let older = pullRequest(1)
        let newer = pullRequest(2)
        let stamp = Date(timeIntervalSince1970: 900_000)

        let result = dashboard(
            [newer, older],
            drafts: [
                newer.id: draft(newer.id, updatedAt: stamp.addingTimeInterval(3600)),
                older.id: draft(older.id, updatedAt: stamp),
            ]
        )

        #expect(result.drafts.pullRequests == 2)
        #expect(result.drafts.oldest == stamp)
        #expect(result.drafts.pullRequest == older.id)
    }

    /// Draft z doby před #181 razítko nemá. Karta o stáří mlčet musí — ale **pokračovat se v něm
    /// dá**, takže cíl akce `Dopsat review` zůstává vyplněný.
    @Test("Draft bez razítka nemá stáří, ale má se v čem pokračovat")
    func doesNotInventAnAgeForOldDrafts() {
        let pr = pullRequest(1)

        let result = dashboard([pr], drafts: [pr.id: draft(pr.id)])

        #expect(result.drafts.pullRequests == 1)
        #expect(result.drafts.oldest == nil)
        #expect(result.drafts.pullRequest == pr.id)
    }

    /// Orazítkovaný draft je starší **jen tehdy, když se to dá říct**. Neorazítkovaný se řadí za
    /// něj, jinak by karta mlčela o stáří i tam, kde ho zná.
    @Test("Orazítkovaný draft má přednost před tím bez razítka")
    func prefersAStampedDraft() {
        let stamped = pullRequest(1)
        let unstamped = pullRequest(2)
        let stamp = Date(timeIntervalSince1970: 900_000)

        let result = dashboard(
            [unstamped, stamped],
            drafts: [
                unstamped.id: draft(unstamped.id),
                stamped.id: draft(stamped.id, updatedAt: stamp),
            ]
        )

        #expect(result.drafts.oldest == stamp)
        #expect(result.drafts.pullRequest == stamped.id)
    }

    // MARK: - Nálezy podle reviewera

    @Test("Nálezy se sčítají podle reviewera přes celou frontu")
    func countsFindingsPerReviewer() {
        let first = pullRequest(1)
        let second = pullRequest(2)
        let record = makeRecord(
            runs: [
                makeStoredRun(skill: "php-review", findings: [makeReported(line: 1), makeReported(line: 2)]),
                makeStoredRun(skill: "docs", findings: []),
            ]
        )

        let result = dashboard([first, second], records: [first.id: record, second.id: record])

        #expect(result.reviewers.map(\.reviewer) == ["php-review", "docs"])
        #expect(result.reviewers.map(\.findings) == [4, 0])
    }

    /// Reviewer, který doběhl čistý, v legendě **zůstává s nulou**: „nenašel nic“ je výsledek,
    /// kdežto chybějící řádek by vypadal, že neběžel.
    @Test("Čistý reviewer zůstává v legendě s nulou")
    func keepsACleanReviewer() {
        let pr = pullRequest(1)
        let record = makeRecord(runs: [makeStoredRun(skill: "docs", findings: [])])

        let result = dashboard([pr], records: [pr.id: record])

        #expect(result.reviewers == [ReviewerShareOfFindings(reviewer: "docs", findings: 0)])
    }

    @Test("Odmítnutý nález se reviewerovi nepočítá")
    func ignoresDismissedFindings() {
        let pr = pullRequest(1)
        var record = makeRecord(runs: [makeStoredRun(skill: "php-review", findings: [makeReported()])])
        record.dismissals = makeDismissals(record.findings)

        let result = dashboard([pr], records: [pr.id: record])

        #expect(result.reviewers == [ReviewerShareOfFindings(reviewer: "php-review", findings: 0)])
    }

    /// Legenda mluví o posledních sedmi dnech, takže starší běh do ní nepatří — ani se svým
    /// jménem. Bez toho by v ní visel reviewer, který v okně vůbec neběžel.
    @Test("Běh mimo okno se nepočítá")
    func ignoresRunsBeforeTheWindow() {
        let pr = pullRequest(1)
        let old = Date(timeIntervalSince1970: 500_000)
        let record = makeRecord(
            runs: [makeStoredRun(skill: "php-review", findings: [makeReported()], finishedAt: old)]
        )

        let result = dashboard([pr], records: [pr.id: record], since: old.addingTimeInterval(3600))

        #expect(result.reviewers.isEmpty)
    }
}
