import Foundation
import Testing

@testable import PRism

/// Co po přírůstkovém review stojí v okně (#517) — souhrn na dráze a odznaky u nálezů.
///
/// Dvě věci se tady rozbijí potichu: **nález, který zmizí** (vyřešený pushem se má jen označit,
/// ne sundat — to smí jedině odmítnutí, #113) a **odznak nad kódem, který už není** (tvrdá
/// podmínka č. 5). Obě mají vlastní test.
@Suite("Policy — souhrn přírůstku")
struct IncrementalReportTests {
    private let head = "new2222"
    private let previousHead = "old1111"

    /// Nálezy z minula, jak je běh dostal — v pořadí, ve kterém se na ně ptalo.
    private var previous: [Finding] {
        [
            makeFinding(summary: "trvá", headSha: previousHead),
            makeFinding(summary: "spravené", headSha: previousHead),
            makeFinding(summary: "nejasné", headSha: previousHead),
            makeFinding(summary: "bez odpovědi", headSha: previousHead),
        ]
    }

    /// Záznam po přírůstkovém běhu — přesně tak, jak vzniká: běh se složí přes `ReviewRun`
    /// s `increment`, takže přenesené nálezy do uloženého běhu doplní `StoredReviewRun.init`.
    private func record(
        answers: [Int: RecheckStatus.Verdict] = [0: .stillApplies, 1: .resolved, 2: .unclear],
        newFindings: [ReportedFinding] = [makeReported(summary: "nový")],
        dismissals: [FindingKey: FindingDismissal] = [:],
        wholeUsage: RunUsage? = RunUsage(cost: 0.82),
        usage: RunUsage? = RunUsage(cost: 0.12),
        askedForVerdicts: Bool = true
    ) -> ReviewRecord {
        let statuses = Policy.incrementalStatuses(
            answers.mapValues { RecheckStatus(verdict: $0) },
            of: previous,
            by: "code-review"
        )
        let run = makeStoredRun(
            findings: newFindings,
            headSha: head,
            usage: usage,
            increment: IncrementalReviewOutcome(
                range: IncrementalDiffRange(seen: previousHead, head: head),
                carried: Policy.carriedFindings(of: previous, by: "code-review", to: head),
                statuses: statuses,
                wholeUsage: wholeUsage,
                askedForVerdicts: askedForVerdicts
            )
        )
        var record = makeRecord(runs: [run], headSha: head)
        record.dismissals = dismissals
        return record
    }

    // MARK: - Nálezy nemizí

    /// **Tohle je to tvrzení, kvůli kterému #517 nemůže o nález přijít.** Vyřešený pushem
    /// zůstává v záznamu; jediné, co se s ním stane, je odznak.
    @Test("Vyřešený pushem nezmizí, dostane odznak")
    func aFindingResolvedByThePushStays() {
        let record = record()

        let summaries = record.findings.map(\.reported.summary)
        #expect(summaries.contains("spravené"))
        #expect(summaries.count == 5)

        let statuses = Policy.findingStatuses(of: record, head: head)
        let resolved = record.findings.first { $0.reported.summary == "spravené" }
        #expect(statuses[Policy.key(of: resolved!)]?.verdict == .resolved)
    }

    /// Nález, ke kterému se běh nevyjádřil, je pořád platný nález — přenese se a odznak nemá.
    @Test("Nezodpovězený nález se přenese bez odznaku")
    func anUnansweredFindingIsCarriedWithoutABadge() {
        let record = record()
        let unanswered = record.findings.first { $0.reported.summary == "bez odpovědi" }

        #expect(unanswered?.headSha == head)
        #expect(unanswered?.carriedFrom == previousHead)
        #expect(Policy.findingStatuses(of: record, head: head)[Policy.key(of: unanswered!)] == nil)
    }

    /// Nový nález si nese dnešní hlavu a **žádný původ**: napsal ho tenhle běh o tomhle kódu.
    @Test("Nový nález původ nemá")
    func aNewFindingHasNoOrigin() {
        let new = record().findings.first { $0.reported.summary == "nový" }

        #expect(new?.headSha == head)
        #expect(new?.carriedFrom == nil)
    }

    // MARK: - Souhrn

    @Test("Souhrn rozlišuje staré, nové a nezodpovězené")
    func theTallySeparatesOldFromNew() throws {
        let record = record()
        let tally = try #require(Policy.incrementalTally(of: record.runs[0], in: record))

        #expect(tally.range == IncrementalDiffRange(seen: previousHead, head: head))
        #expect(tally.carried == 4)
        #expect(tally.stillApplies == 1)
        #expect(tally.resolved == 1)
        #expect(tally.unclear == 1)
        #expect(tally.unanswered == 1)
        #expect(tally.new == 1)
    }

    /// Počty se berou z **platných** nálezů, ne z uložených čísel: odmítnutý nález z okna zmizí,
    /// takže by věta tvrdila „4 staré“ nad třemi. Tatáž úvaha jako u `RecheckTally`.
    @Test("Odmítnutý nález se do počtů nepočítá")
    func aDismissedFindingIsNotCounted() throws {
        let dismissed = Policy.carriedFindings(of: previous, by: "code-review", to: head)[0]
        let record = record(dismissals: makeDismissals([dismissed]))

        let tally = try #require(Policy.incrementalTally(of: record.runs[0], in: record))

        #expect(tally.carried == 3)
        #expect(tally.stillApplies == 0)
        #expect(tally.unanswered == 1)
    }

    /// Běh nad celým diffem souhrn **nemá** — a `nil` je tu odpověď, ne prázdný souhrn: nuly by
    /// na dráze vypadaly jako přírůstek, ve kterém se nic nestalo.
    @Test("Celý běh souhrn nemá")
    func aWholeRunHasNoTally() {
        let record = makeRecord(runs: [makeStoredRun(headSha: head)], headSha: head)

        #expect(Policy.incrementalTally(of: record.runs[0], in: record) == nil)
    }

    /// **„Nezeptali jsme se“ je jiná odpověď než „neodpověděl“**: materiál se nepodařilo uložit,
    /// takže verdikty nechyběly modelu, ale otázce. Spočítat se to z `statuses` nedá — prázdná
    /// mapa vznikne i tak, že běh odpověděl nečitelně.
    @Test("Nezeptali jsme se je jiný stav než neodpověděl")
    func notAskingIsNotTheSameAsNoAnswer() throws {
        let asked = record(answers: [:])
        let notAsked = record(answers: [:], askedForVerdicts: false)

        let askedTally = try #require(Policy.incrementalTally(of: asked.runs[0], in: asked))
        let notAskedTally = try #require(
            Policy.incrementalTally(of: notAsked.runs[0], in: notAsked)
        )

        #expect(askedTally.unanswered == 4)
        #expect(askedTally.askedForVerdicts)
        #expect(notAskedTally.unanswered == 4)
        #expect(!notAskedTally.askedForVerdicts)
        // A v okně to nejsou tytéž věty.
        #expect(ReviewerLaneText.increment(askedTally) != ReviewerLaneText.increment(notAskedTally))
        #expect(ReviewerLaneText.increment(notAskedTally)?.contains("materiál") == true)
    }

    @Test("Cena celého běhu z prvního kola se drží u přírůstku")
    func theWholeRunCostTravelsWithTheIncrement() throws {
        let record = record()
        let tally = try #require(Policy.incrementalTally(of: record.runs[0], in: record))

        #expect(tally.wholeUsage?.cost == 0.82)
    }

    // MARK: - Platnost odznaků (tvrdá podmínka č. 5)

    /// **Jak se hlava posune, odznaky zhasnou.** Nechat je svítit by znamenalo tvrdit
    /// „vyřešeno“ nad commity, které ten běh nikdy neviděl.
    @Test("Po dalším pushi odznaky zmizí")
    func theBadgesGoOutWhenTheHeadMoves() {
        let record = record()

        #expect(Policy.findingStatuses(of: record, head: "third3333").isEmpty)
    }

    /// Nenačtený detail (`head == nil`) je totéž: platnost, kterou nemáme čím potvrdit, se
    /// nepředpokládá.
    @Test("Bez známé hlavy odznaky nejsou")
    func noBadgesWithoutAKnownHead() {
        #expect(Policy.findingStatuses(of: record(), head: nil).isEmpty)
    }

    /// Kontrola nálezů (#150) a přírůstek (#517) jdou do okna **jednou mapou**: dvě čtení by
    /// znamenala, že u nálezu stojí jeden odznak a v hlavičce druhý.
    @Test("Odznaky z kontroly a z přírůstku jdou jednou mapou")
    func bothSourcesEndUpInOneMap() {
        // Nález, který v záznamu **je** — počty i odznaky kontroly se skládají proti platným
        // nálezům záznamu (`Policy.recheck`), takže verdikt o cizí větě se zahodí. Tady je proto
        // ten nový nález z přírůstkového běhu.
        let finding = makeFinding(summary: "nový", headSha: head)
        var record = record()
        record.recheck = StoredRecheck(
            againstHeadSha: head,
            outcome: .finished,
            sessionID: nil,
            statuses: [Policy.key(of: finding): RecheckStatus(verdict: .unclear)],
            finishedAt: Date(timeIntervalSince1970: 2_000_000)
        )

        let statuses = Policy.findingStatuses(of: record, head: head)

        #expect(statuses[Policy.key(of: finding)]?.verdict == .unclear)
        let stillApplies = record.findings.first { $0.reported.summary == "trvá" }
        #expect(statuses[Policy.key(of: stillApplies!)]?.verdict == .stillApplies)
    }

    @Test("Bez záznamu nejsou odznaky žádné")
    func noRecordMeansNoBadges() {
        #expect(Policy.findingStatuses(of: nil, head: head).isEmpty)
    }
}
