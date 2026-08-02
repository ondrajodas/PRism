import Foundation
import Testing

@testable import PRism

/// Stav jednoho revieweera v horní liště detailu.
///
/// Platí tu totéž, co u návrhu verdiktu: **„nic jsem nenašel“ a „nemám co říct“ se nesmí
/// slít.** Chip, který u nereportujícího běhu ukáže „čisté“, je schválený PR s neohlášenou
/// chybou.
@Suite("Policy — chipy reviewerů")
struct ReviewerChipTests {
    private func run(
        _ skill: String,
        outcome: ReviewRunOutcome = .finished,
        findings: Int = 0,
        dropped: Int = 0,
        reported: Bool = true
    ) -> StoredReviewRun {
        var summary = StreamSummary()
        summary.calledReportFindings = reported
        summary.droppedFindings = dropped
        summary.findings = (0..<findings).map {
            ReportedFinding(
                file: "App/Main.swift",
                line: $0 + 1,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: nil,
                summary: "nález \($0)",
                failureScenario: nil
            )
        }
        let review = ReviewRun(
            key: ReviewRunKey(pullRequest: PRIdentifier("cli/cli#1")!, headSha: "abc", skillID: skill),
            summary: summary,
            outcome: outcome
        )
        return StoredReviewRun(review, finishedAt: Date(timeIntervalSince1970: 0))
    }

    private func record(_ runs: [StoredReviewRun], stale: Bool = false) -> ReviewRecord {
        var record = ReviewRecord(
            pullRequest: PRIdentifier("cli/cli#1")!,
            headSha: "abc",
            runs: runs
        )
        record.isStale = stale
        return record
    }

    private func state(_ chips: [ReviewerChip], of skill: String) -> ReviewerChip.State? {
        chips.first { $0.skill == skill }?.state
    }

    @Test("Doběhlý běh s nálezy hlásí jejich počet")
    func reportsTheNumberOfFindings() {
        let chips = Policy.chips(for: record([run("code-review", findings: 3)]), skills: ["code-review"], running: [])

        #expect(state(chips, of: "code-review") == .findings(3))
    }

    @Test("Doběhlý běh, který nic nenašel, je čistý")
    func marksACleanRun() {
        let chips = Policy.chips(for: record([run("code-review")]), skills: ["code-review"], running: [])

        #expect(state(chips, of: "code-review") == .clean)
    }

    /// Nezavolaný `ReportFindings` znamená, že se nálezy nemají kde vzít — ne že jich je nula.
    @Test("Běh, který nereportoval, čistý není")
    func neverCallsASilentRunClean() {
        let chips = Policy.chips(
            for: record([run("code-review", reported: false)]),
            skills: ["code-review"],
            running: []
        )

        guard case .inconclusive = state(chips, of: "code-review") else {
            Issue.record("Čekal jsem nejistý výsledek, přišlo \(String(describing: state(chips, of: "code-review")))")
            return
        }
    }

    @Test("Běh, kterému se ztratil nález, čistý není")
    func neverCallsARunWithDroppedFindingsClean() {
        let chips = Policy.chips(
            for: record([run("code-review", dropped: 1)]),
            skills: ["code-review"],
            running: []
        )

        guard case .inconclusive = state(chips, of: "code-review") else {
            Issue.record("Zahozený nález se nesmí tvářit jako čisto")
            return
        }
    }

    /// Nálezy dorazily, ale ne všechny. Chip musí říct obojí: kolik jich je **a** že
    /// výsledek není úplný — jinak je ztráta neviditelná.
    @Test("Běh s nálezy i ztrátou hlásí počet a varuje")
    func warnsWhenSomeFindingsWereLost() throws {
        let chips = Policy.chips(
            for: record([run("code-review", findings: 3, dropped: 1)]),
            skills: ["code-review"],
            running: []
        )

        let chip = try #require(chips.first)
        #expect(chip.state == .findings(3))
        #expect(chip.warning?.contains("nepodařilo přečíst") == true)
    }

    @Test("Čistý běh nemá co varovat")
    func hasNoWarningWhenNothingWasLost() {
        let chips = Policy.chips(for: record([run("code-review")]), skills: ["code-review"], running: [])

        #expect(chips.first?.warning == nil)
    }

    @Test("Spadlý běh nese text chyby")
    func carriesTheFailureDetail() {
        let chips = Policy.chips(
            for: record([run("code-review", outcome: .failed(detail: "claude spadl"))]),
            skills: ["code-review"],
            running: []
        )

        #expect(state(chips, of: "code-review") == .failed("claude spadl"))
    }

    /// Vytimeoutovaný běh si nálezy nechává — jsou to jediné, co stihl.
    @Test("Timeout si nechá, co stihl")
    func keepsWhatATimedOutRunManaged() {
        let chips = Policy.chips(
            for: record([run("code-review", outcome: .timedOut, findings: 2)]),
            skills: ["code-review"],
            running: []
        )

        #expect(state(chips, of: "code-review") == .timedOut(findings: 2))
    }

    @Test("Běžící reviewer přebije starší výsledek")
    func aRunningReviewerOverridesAnOlderResult() {
        let chips = Policy.chips(
            for: record([run("code-review", findings: 3)]),
            skills: ["code-review"],
            running: ["code-review"]
        )

        #expect(state(chips, of: "code-review") == .running)
    }

    @Test("Skill bez běhu je nespuštěný")
    func marksASkillWithoutARun() {
        #expect(Policy.chips(for: nil, skills: ["code-review"], running: []) == [
            ReviewerChip(skill: "code-review", state: .notStarted),
        ])
    }

    @Test("Pořadí chipů kopíruje nastavenou sadu skillů")
    func keepsTheConfiguredOrder() {
        let chips = Policy.chips(
            for: record([run("security"), run("code-review")]),
            skills: ["code-review", "security"],
            running: []
        )

        #expect(chips.map(\.skill) == ["code-review", "security"])
    }

    /// Sada skillů se dá změnit, ale výsledky starého běhu tím nezmizí — a bez chipu by
    /// se nedalo poznat, odkud se v tabulce vzaly.
    @Test("Reviewer mimo nastavenou sadu se přidá na konec")
    func keepsResultsOfAReviewerOutsideTheSet() {
        let chips = Policy.chips(
            for: record([run("code-review"), run("security", findings: 1)]),
            skills: ["code-review"],
            running: []
        )

        #expect(chips.map(\.skill) == ["code-review", "security"])
        #expect(state(chips, of: "security") == .findings(1))
    }
}
