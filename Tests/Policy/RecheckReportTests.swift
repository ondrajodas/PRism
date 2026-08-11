import Foundation
import Testing

@testable import PRism

/// Párování odpovědí kontroly na nálezy a to, kdy se smí ukázat (#150).
///
/// Dvě věci, které se tady rozbijí potichu: **klíč** (odpověď spadne mimo a odznak nesvítí)
/// a **platnost** (odznak svítí nad commitem, který kontrola nikdy neviděla — tvrdá podmínka
/// č. 5). Obě mají vlastní test.
@Suite("Policy — kontrola nálezů")
struct RecheckReportTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    private func record(
        findings: [ReportedFinding],
        recheck: StoredRecheck? = nil,
        dismissals: [FindingKey: FindingDismissal] = [:],
        headSha: String = "old1111"
    ) -> ReviewRecord {
        ReviewRecord(
            pullRequest: pr,
            headSha: headSha,
            runs: [makeStoredRun(findings: findings, headSha: headSha)],
            isStale: true,
            dismissals: dismissals,
            recheck: recheck
        )
    }

    private func stored(
        _ statuses: [FindingKey: RecheckStatus],
        against headSha: String = "new2222",
        outcome: ReviewRunOutcome = .finished
    ) -> StoredRecheck {
        StoredRecheck(
            againstHeadSha: headSha,
            outcome: outcome,
            sessionID: "session",
            statuses: statuses,
            finishedAt: Date(timeIntervalSince1970: 2_000_000)
        )
    }

    // MARK: - Párování

    /// Klíč se skládá **produkční funkcí**. Kdyby si ho tenhle test skládal sám, testoval by
    /// svoji kopii pravidla — a `Policy.key(of:)` je změřený proti přeformulovanému
    /// `short_summary` i proti překladu, o čemž by kopie nevěděla.
    @Test("Odpovědi se spárují klíčem nálezu")
    func theAnswersArePairedByFindingKey() {
        let findings = [makeFinding(summary: "první"), makeFinding(summary: "druhý")]

        let statuses = Policy.recheckStatuses(
            [0: RecheckStatus(verdict: .resolved), 1: RecheckStatus(verdict: .unclear)],
            of: findings
        )

        #expect(statuses[Policy.key(of: findings[0])]?.verdict == .resolved)
        #expect(statuses[Policy.key(of: findings[1])]?.verdict == .unclear)
    }

    /// Překlad se ukládá druhým zápisem po běhu a při dalším běhu vyjde jinak — klíč z něj by se
    /// rozešel sám se sebou. Odpověď na nález, který se mezitím přeložil, proto sedět musí.
    @Test("Překlad nálezu párování nerozbije")
    func aTranslationDoesNotBreakThePairing() {
        let original = makeFinding(file: "Cart.php", line: 4, summary: "missing check")
        let translated = makeFinding(
            file: "Cart.php",
            line: 4,
            summary: "missing check",
            translation: FindingTranslation(
                summary: "chybí kontrola",
                shortSummary: nil,
                failureScenario: nil
            )
        )

        let statuses = Policy.recheckStatuses([0: RecheckStatus(verdict: .resolved)], of: [original])

        #expect(statuses[Policy.key(of: translated)]?.verdict == .resolved)
    }

    @Test("Index mimo seznam se zahodí")
    func anIndexOutOfRangeIsDropped() {
        #expect(Policy.recheckStatuses([7: RecheckStatus(verdict: .resolved)], of: [makeFinding()]).isEmpty)
    }

    // MARK: - Report

    @Test("Bez záznamu a bez kontroly není co ukazovat")
    func withoutARecheckThereIsNothing() {
        #expect(Policy.recheck(of: nil, head: "new2222") == .none)
        #expect(Policy.recheck(of: record(findings: [makeReported()]), head: "new2222") == .none)
    }

    /// Jak se hlava posune, kontrola přestane platit: odznaky zhasnou a zbyde věta o tom, že se
    /// dá pustit znovu. Kdyby zůstaly, tvrdily by „vyřešeno“ nad commity, které kontrola nikdy
    /// neviděla.
    @Test("Kontrola proti jiné hlavě odznaky nerozsvítí")
    func aRecheckAgainstAnotherHeadIsOutdated() {
        let finding = makeFinding(summary: "první")
        let record = record(
            findings: [finding.reported],
            recheck: stored([Policy.key(of: finding): RecheckStatus(verdict: .resolved)])
        )

        let report = Policy.recheck(of: record, head: "third3333")

        #expect(report == .outdated(againstHeadSha: "new2222"))
        #expect(report.statuses.isEmpty)
    }

    /// Nenačtený detail znamená, že hlavu neznáme — a platnost, kterou nemáme čím potvrdit, se
    /// u odznaků nepředpokládá.
    @Test("Bez známé hlavy se odznaky nekreslí")
    func withoutAKnownHeadThereAreNoBadges() {
        let finding = makeFinding(summary: "první")
        let record = record(
            findings: [finding.reported],
            recheck: stored([Policy.key(of: finding): RecheckStatus(verdict: .resolved)])
        )

        #expect(Policy.recheck(of: record, head: nil).statuses.isEmpty)
    }

    @Test("Platná kontrola sečte, co řekla")
    func aCurrentRecheckIsTallied() {
        let findings = [
            makeFinding(file: "a.swift", line: 1, summary: "první"),
            makeFinding(file: "b.swift", line: 2, summary: "druhý"),
            makeFinding(file: "c.swift", line: 3, summary: "třetí"),
            makeFinding(file: "d.swift", line: 4, summary: "čtvrtý"),
        ]
        let record = record(
            findings: findings.map(\.reported),
            recheck: stored([
                Policy.key(of: findings[0]): RecheckStatus(verdict: .resolved),
                Policy.key(of: findings[1]): RecheckStatus(verdict: .stillApplies),
                Policy.key(of: findings[2]): RecheckStatus(verdict: .unclear),
            ])
        )

        guard case .current(let tally) = Policy.recheck(of: record, head: "new2222") else {
            Issue.record("čekal se platný report")
            return
        }

        #expect(tally.resolved == 1)
        #expect(tally.stillApplies == 1)
        #expect(tally.unclear == 1)
        // Čtvrtý nález odpověď nemá — bez tohohle čísla by „1 vyřešený“ nad čtyřmi nálezy
        // vypadalo, že o zbytku kontrola něco řekla.
        #expect(tally.unanswered == 1)
        #expect(tally.answered == 3)
    }

    /// Odmítnutý nález z okna zmizí, takže se nesmí počítat ani sem — jinak by věta v hlavičce
    /// mluvila o nálezech, které nikde nejsou.
    @Test("Odmítnutý nález se do počtů nepočítá")
    func aDismissedFindingIsNotCounted() {
        let findings = [makeFinding(summary: "první"), makeFinding(summary: "druhý")]
        let record = record(
            findings: findings.map(\.reported),
            recheck: stored([
                Policy.key(of: findings[0]): RecheckStatus(verdict: .resolved),
                Policy.key(of: findings[1]): RecheckStatus(verdict: .resolved),
            ]),
            dismissals: makeDismissals([findings[1]])
        )

        guard case .current(let tally) = Policy.recheck(of: record, head: "new2222") else {
            Issue.record("čekal se platný report")
            return
        }

        #expect(tally.resolved == 1)
        #expect(tally.unanswered == 0)
        #expect(tally.statuses.count == 1)
        #expect(tally.statuses[Policy.key(of: findings[1])] == nil)
    }

    /// Kontrola, kterou zabil timeout, mluví jen za odpovědi, které stihla poslat. Slít ji
    /// s doběhlou by znamenalo tvrdit, že se probraly všechny nálezy.
    @Test("Report nese, jak běh skončil")
    func theReportCarriesTheOutcome() {
        let finding = makeFinding(summary: "první")
        let record = record(
            findings: [finding.reported],
            recheck: stored(
                [Policy.key(of: finding): RecheckStatus(verdict: .resolved)],
                outcome: .timedOut
            )
        )

        guard case .current(let tally) = Policy.recheck(of: record, head: "new2222") else {
            Issue.record("čekal se platný report")
            return
        }

        #expect(tally.outcome == .timedOut)
    }
}
