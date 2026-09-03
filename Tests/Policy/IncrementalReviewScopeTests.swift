import Foundation
import Testing

@testable import PRism

/// Kdy se jde nad přírůstkem a kdy nad celým diffem (#517).
///
/// **Výčet, ne příklady**: každá odpověď `whole(...)` znamená jinou větu v okně a `increment`
/// znamená, že reviewer **nepřečte** kód mimo rozsah. Nejcennější tvrzení jsou tady ta negativní
/// — že se přírůstek **nepustí** tam, kde by přeskočil kód, o kterém nikdo nic neřekl.
@Suite("Policy — přírůstek nebo celý diff")
struct IncrementalReviewScopeTests {
    private func record(
        headSha: String = "old1111",
        runs: [StoredReviewRun]? = nil,
        findings: [ReportedFinding] = [makeReported(summary: "starý nález")]
    ) -> ReviewRecord {
        makeRecord(
            runs: runs ?? [makeStoredRun(findings: findings, headSha: headSha)],
            isStale: true,
            headSha: headSha
        )
    }

    private func scope(
        record: ReviewRecord?,
        head: String = "new2222",
        skill: String = "code-review",
        ancestry: BranchAncestry = .ancestor,
        enabled: Bool = true
    ) -> ReviewScope {
        Policy.reviewScope(
            record: record,
            head: head,
            skill: skill,
            ancestry: ancestry,
            enabled: enabled
        )
    }

    // MARK: - Kdy přírůstek

    @Test("Po pushi nad doběhlým během jde přírůstek")
    func aFinishedPreviousRunGetsTheIncrement() {
        let scope = scope(record: record())

        #expect(scope == .increment(IncrementalDiffRange(seen: "old1111", head: "new2222")))
        #expect(scope.increment?.seen == "old1111")
    }

    // MARK: - Kdy celý diff

    /// Vypnuté nastavení je odpověď, ne absence odpovědi — a musí být poznat od těch ostatních,
    /// protože jediné, co ji odblokuje, je přepínač v nastavení.
    @Test("Vypnuté nastavení znamená celý diff")
    func theSettingOffMeansTheWholeDiff() {
        #expect(scope(record: record(), enabled: false) == .whole(.disabled))
    }

    @Test("Bez uloženého záznamu není od čeho odpočítávat")
    func theFirstReviewIsWhole() {
        #expect(scope(record: nil) == .whole(.firstReview))
    }

    /// Ruční `Pustit review` nad hlavou, na které záznam už je: přírůstek by byl prázdný.
    @Test("Tatáž hlava znamená celý diff")
    func theSameHeadIsWhole() {
        #expect(scope(record: record(headSha: "new2222")) == .whole(.sameHead))
    }

    /// **Tohle je to tvrzení, které se rozbije potichu.** Reviewer, který nad předchozí hlavou
    /// nedoběhl, tam kód nepřečetl — a přírůstek by ten nepřečtený zbytek přeskočil, aniž by to
    /// kdokoli poznal.
    @Test("Reviewer, který minule nedoběhl, jde nad celým diffem")
    func aReviewerThatDidNotFinishGetsTheWholeDiff() {
        for outcome in [
            ReviewRunOutcome.timedOut,
            .interrupted,
            .failed(detail: "kód 1"),
        ] {
            let previous = record(
                runs: [makeStoredRun(outcome: outcome, headSha: "old1111")]
            )

            #expect(scope(record: previous) == .whole(.noFinishedRun))
        }
    }

    /// Reviewer, který v předchozím kole vůbec nebyl (přibyl do sady), nemá od čeho odpočítávat —
    /// a je to jiný důvod než „nedoběhl“ jedině zvenčí; v okně stačí jeden.
    @Test("Reviewer, který minule neběžel, jde nad celým diffem")
    func aReviewerWithoutAPreviousRunGetsTheWholeDiff() {
        let previous = record(runs: [makeStoredRun(skill: "security", headSha: "old1111")])

        #expect(scope(record: previous, skill: "code-review") == .whole(.noFinishedRun))
    }

    /// **Force push bez společné historie** — ten případ, který se od #466 bude dít, protože
    /// aplikace umí přetlačit vlastní větev. Musí to být vlastní důvod: „co přibylo“ vyjde po
    /// přepsané historii na **víc** než celý diff PR (změřeno u #284).
    @Test("Přepsaná historie znamená celý diff, a řekne se to")
    func aRewrittenHistoryIsWholeAndSaysSo() {
        #expect(scope(record: record(), ancestry: .rewritten) == .whole(.rewroteHistory))
    }

    /// Nezjištěná příbuznost vede na tentýž běh, ale **jinou větu**: tvrdit přepsanou historii
    /// tam, kde se `git` k odpovědi nedostal, znamená tvrdit víc, než data unesou.
    @Test("Nezjištěná příbuznost je vlastní důvod")
    func anUnknownAncestryIsItsOwnReason() {
        #expect(scope(record: record(), ancestry: .unknown) == .whole(.unknownAncestry))
    }

    /// Záznam s prázdnou hlavou by dal rozsah, ve kterém jedna sha chybí — a `git diff ...HEAD`
    /// znamená něco jiného než `git diff <sha>...HEAD`.
    @Test("Prázdná hlava záznamu se bere jako první review")
    func anEmptyStoredHeadIsTheFirstReview() {
        #expect(scope(record: record(headSha: "")) == .whole(.firstReview))
    }

    // MARK: - Co se z rozhodnutí dostane do okna

    /// **Rozhodnutí, které nikdo nečte, je mrtvá váha** — proto se `whole(...)` u těch tří důvodů,
    /// kde by člověk přírůstek čekal, dostane do osy a v `Průběhu` je z něj věta. U prvního kola,
    /// vypnutého nastavení a téže hlavy se **nehlásí nic**: „celý diff, protože je to první kolo“
    /// je stav, ve kterém aplikace běžela do #517, a řádek o něm by přidal šum do každé osy.
    @Test("Do osy jde přírůstek a tři vysvětlované důvody, nic jiného")
    func onlyExplainedDecisionsGoIntoTheTimeline() {
        #expect(scope(record: record()).belongsInTimeline)
        #expect(scope(record: record(), ancestry: .rewritten).belongsInTimeline)
        #expect(scope(record: record(), ancestry: .unknown).belongsInTimeline)
        #expect(scope(record: record(runs: [makeStoredRun(outcome: .timedOut, headSha: "old1111")]))
            .belongsInTimeline)

        #expect(!scope(record: nil).belongsInTimeline)
        #expect(!scope(record: record(), enabled: false).belongsInTimeline)
        #expect(!scope(record: record(headSha: "new2222")).belongsInTimeline)
    }

    /// Věty o důvodech se **nesmí slít**: „nedoběhlo minule“ a „přepsala se historie“ vedou na
    /// tentýž běh, ale znamenají něco jiného.
    @Test("Každý důvod má vlastní věta")
    func everyReasonHasItsOwnSentence() {
        let sentences = ReviewScope.WholeReason.allCases.map(ReviewerLaneText.wholeReason)

        #expect(Set(sentences).count == sentences.count)
        #expect(sentences.allSatisfy { !$0.isEmpty })
    }

    /// Rozsah se z rozhodnutí čte **jedním** getterem, a u celého diffu vyjde `nil` — jinak by se
    /// dal vzít u běhu, který jede nad celým diffem.
    @Test("Z celého diffu se rozsah přečíst nedá")
    func aWholeScopeHasNoRange() {
        #expect(scope(record: nil).increment == nil)
        #expect(scope(record: nil).wholeReason == .firstReview)
        #expect(scope(record: record()).wholeReason == nil)
    }

    // MARK: - Co se posílá a co se přenáší

    /// Materiál nese nálezy **všech** reviewerů: běh, který nevidí, co už na PR stojí, ohlásí
    /// cizí nález jako svůj nový.
    @Test("Materiál nese nálezy všech reviewerů")
    func theMaterialCarriesEveryReviewersFindings() {
        let previous = record(runs: [
            makeStoredRun(skill: "code-review", findings: [makeReported(summary: "můj")], headSha: "old1111"),
            makeStoredRun(skill: "security", findings: [makeReported(summary: "cizí")], headSha: "old1111"),
        ])

        let findings = Policy.previousFindings(of: previous)

        #expect(findings.map(\.reported.summary) == ["můj", "cizí"])
    }

    /// Odmítnutý nález (#113) se **neposílá ani nepřenáší**: odmítnutí je jediné, co nález
    /// sundává, a poslat ho zpátky do dalšího kola by ho vzkřísilo.
    @Test("Odmítnutý nález se do dalšího kola nedostane")
    func aDismissedFindingIsNotCarried() {
        var previous = record(findings: [
            makeReported(summary: "platný"),
            makeReported(summary: "odmítnutý"),
        ])
        previous.dismissals = makeDismissals([makeFinding(summary: "odmítnutý", headSha: "old1111")])

        let findings = Policy.previousFindings(of: previous)

        #expect(findings.map(\.reported.summary) == ["platný"])
    }

    /// Běh si odnese **jen své** nálezy: `ReviewRecord.findings` je sjednocení běhů, takže dvě
    /// kopie jedné věty by v okně byly dva nálezy.
    @Test("Přenášejí se jen nálezy toho revieweera")
    func onlyTheOwnFindingsAreCarried() {
        let previous = [
            makeFinding(summary: "můj", reviewer: "code-review", headSha: "old1111"),
            makeFinding(summary: "cizí", reviewer: "security", headSha: "old1111"),
        ]

        let carried = Policy.carriedFindings(of: previous, by: "code-review", to: "new2222")

        #expect(carried.map(\.reported.summary) == ["můj"])
        #expect(carried.first?.headSha == "new2222")
        #expect(carried.first?.carriedFrom == "old1111")
    }

    /// **Původ se po druhém pushi nepřepisuje**: věta má ukazovat na commit, na kterém ji
    /// reviewer napsal, ne na předchozí přírůstek.
    @Test("Původ přeneseného nálezu se drží prvního commitu")
    func theOriginSurvivesASecondPush() {
        let once = Policy.carriedFindings(
            of: [makeFinding(headSha: "old1111")],
            by: "code-review",
            to: "mid2222"
        )

        let twice = Policy.carriedFindings(of: once, by: "code-review", to: "new3333")

        #expect(twice.first?.headSha == "new3333")
        #expect(twice.first?.carriedFrom == "old1111")
    }

    /// Přenesení nález **nerozdvojí**: klíč nese `Policy.key(of:)` a `carriedFrom` v něm není,
    /// takže odmítnutí i verdikty se dál párují.
    @Test("Přenesení nemění klíč nálezu")
    func carryingDoesNotChangeTheKey() {
        let original = makeFinding(summary: "nález", headSha: "old1111")

        let carried = original.carried(to: "new2222")

        #expect(Policy.key(of: carried) == Policy.key(of: original))
    }

    // MARK: - Párování verdiktů

    /// **Přes index, ne přes text** — jako u #150. Regrese: reviewer si větu přeformuluje a
    /// párování to nesmí rozbít, protože `id` nese aplikace na obou stranách.
    @Test("Verdikty se párují indexem, ne textem")
    func theVerdictsArePairedByIndex() {
        let previous = [
            makeFinding(summary: "první", headSha: "old1111"),
            makeFinding(summary: "druhý", headSha: "old1111"),
        ]

        let statuses = Policy.incrementalStatuses(
            [0: RecheckStatus(verdict: .stillApplies), 1: RecheckStatus(verdict: .resolved)],
            of: previous,
            by: "code-review"
        )

        #expect(statuses[Policy.key(of: previous[0])]?.verdict == .stillApplies)
        #expect(statuses[Policy.key(of: previous[1])]?.verdict == .resolved)
    }

    /// Verdikt, který běh dal **cizímu** nálezu, se zahodí: u nálezu, o kterém tenhle běh nic
    /// nevěděl, by se objevil odznak od někoho, kdo ho neposuzoval.
    @Test("Verdikt cizímu nálezu se zahodí")
    func aVerdictOnAnotherReviewersFindingIsDropped() {
        let previous = [
            makeFinding(summary: "můj", reviewer: "code-review", headSha: "old1111"),
            makeFinding(summary: "cizí", reviewer: "security", headSha: "old1111"),
        ]

        let statuses = Policy.incrementalStatuses(
            [0: RecheckStatus(verdict: .stillApplies), 1: RecheckStatus(verdict: .resolved)],
            of: previous,
            by: "code-review"
        )

        #expect(statuses.count == 1)
        #expect(statuses[Policy.key(of: previous[1])] == nil)
    }

    /// `id` mimo rozsah se **nedomýšlí**: přiřadit verdikt podle vymyšleného indexu by ho dalo
    /// cizímu nálezu.
    @Test("Index mimo rozsah se zahodí")
    func anIndexOutOfRangeIsDropped() {
        let previous = [makeFinding(headSha: "old1111")]

        let statuses = Policy.incrementalStatuses(
            [7: RecheckStatus(verdict: .resolved), -1: RecheckStatus(verdict: .resolved)],
            of: previous,
            by: "code-review"
        )

        #expect(statuses.isEmpty)
    }
}
