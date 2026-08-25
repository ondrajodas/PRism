import Foundation
import Testing

@testable import PRism

/// Reviewer, který nepřečetl kód, se nesmí nakreslit jako čisté review (#383).
///
/// Sada drží **obojí** a je to celý smysl toho rozdělení do jednoho souboru: nahoře falešné
/// čisto (běh bez čtení projde jako průkazný), dole falešný poplach (běh, který kód přečetl,
/// nebo o kterém záznam nic neříká, se označí za nepřečtený). Kdyby platila jen jedna polovina,
/// stav by se přestal čítat — jen by se to podle toho, která to je, poznalo dřív nebo později.
@Suite("Nepřečtený kód se nekreslí jako čisto")
struct UnreadCodeStateTests {
    private let worktree = URL(fileURLWithPath: "/cache/worktrees/cli/cli/42-aaaa1111")

    private func timeline(_ attempts: [ToolAttempt]) -> StoredTimeline {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let entries = attempts.enumerated().map { index, attempt in
            ReviewerTimeline.Entry(
                id: index,
                at: start.addingTimeInterval(Double(index)),
                kind: .tool(attempt)
            )
        }
        return StoredTimeline(worktree: worktree, entries: entries, dropped: 0)
    }

    /// Běh, který si přečetl jen zadání a prohnal `git diff` — tvar opsaný ze skutečného
    /// uloženého běhu `security-review` z 18. 8. (0,139 $, 13 kol, jedenáct pokusů, ani jeden
    /// otevřený soubor z kódu).
    private func unreadRun(
        skill: String = "security-review",
        findings: [ReportedFinding] = [],
        calledReportFindings: Bool = true,
        droppedFindings: Int = 0
    ) -> StoredReviewRun {
        makeStoredRun(
            skill: skill,
            findings: findings,
            calledReportFindings: calledReportFindings,
            droppedFindings: droppedFindings,
            timeline: timeline([
                ToolAttempt(name: "Skill", detail: skill),
                ToolAttempt(name: "Read", detail: worktree.path() + ".md"),
                ToolAttempt(name: "Bash", detail: "cd \"\(worktree.path())\" && git diff bbbb2222...HEAD --stat"),
                ToolAttempt(name: "ReportFindings", detail: nil),
            ])
        )
    }

    /// Běh, který kód doopravdy otevřel. Jinak úplně stejný — rozdíl je **jediný pokus**.
    private func readingRun(
        skill: String = "code-review",
        findings: [ReportedFinding] = []
    ) -> StoredReviewRun {
        makeStoredRun(
            skill: skill,
            findings: findings,
            timeline: timeline([
                ToolAttempt(name: "Skill", detail: skill),
                ToolAttempt(name: "Read", detail: worktree.path() + "/src/Job/Runner.php"),
                ToolAttempt(name: "ReportFindings", detail: nil),
            ])
        )
    }

    // MARK: - Falešné čisto

    @Test("Běh, který kód neotevřel, není čisté review")
    func anUnreadRunIsNotClean() {
        let state = Policy.reviewState(for: makeRecord(runs: [unreadRun()]))

        #expect(state != .clean)
        #expect(state == .inconclusive(reason: .unreadCode))
    }

    @Test("Návrh verdiktu z takového běhu nevznikne")
    func noVerdictIsSuggestedFromAnUnreadRun() {
        // Schválit PR proto, že se reviewer nepodíval do kódu, je tatáž chyba jako schválit ho
        // proto, že reviewer spadl.
        #expect(Policy.suggestedVerdict(for: makeRecord(runs: [unreadRun()])) == nil)
        #expect(Policy.isConclusive(unreadRun()) == false)
    }

    @Test("Chip revieweera řekne, co chybí")
    func theChipSaysWhatIsMissing() {
        let chips = Policy.chips(
            for: makeRecord(runs: [unreadRun()]),
            skills: ["security-review"],
            running: []
        )

        guard case .inconclusive(let text) = chips.first?.state else {
            Issue.record("Očekáván nejistý chip, přišlo \(String(describing: chips.first?.state))")
            return
        }
        #expect(text.contains("neotevřel"))
    }

    @Test("Díl proužku u řádku není zelený")
    func theSpectrumSegmentIsNotGreen() {
        let row = Policy.queueRow(for: makeRecord(runs: [unreadRun()]))

        #expect(row.spectrum.map(\.outcome) == [.inconclusive])
    }

    @Test("Prázdný tab nálezů to řekne větou, ne prázdnem")
    func theEmptyFindingsTabExplainsIt() {
        let reason = Policy.findingsEmptyReason(
            visible: [],
            record: makeRecord(runs: [unreadRun()]),
            isRunning: false
        )

        #expect(reason == .inconclusive(.unreadCode))
        // Věta musí mluvit o souboru, ne o poruše — a nesmí být tatáž jako u čistoty.
        #expect(Policy.inconclusiveDetail(.unreadCode).contains("neotevřel"))
        #expect(Policy.inconclusiveDetail(.unreadCode) != Policy.inconclusiveDetail(.noReport))
    }

    @Test("Odznak se neslije s čistým, selhaným ani zastaralým")
    func theBadgeStandsApart() {
        let labels = InconclusiveReason.allCases.map {
            ReviewStateAppearance.label(of: .inconclusive(reason: $0))
        }
        let others: [String] = [ReviewState.clean, .failed(detail: "boom"), .stale]
            .map { ReviewStateAppearance.label(of: $0) }

        #expect(Set(labels).count == InconclusiveReason.allCases.count)
        #expect(Set(labels).isDisjoint(with: Set(others)))
        #expect(ReviewStateAppearance.label(of: .inconclusive(reason: .unreadCode)) == "kód nepřečten")
        // Ne zelená a ne červená: session doběhla, takže „selhalo“ by lhalo, a „čisté“ taky.
        //
        // **Porovnává se s barvou těch dvou stavů, ne se systémovou `.green`/`.red`** (#432): od
        // převodu škály na tokeny by tvrzení o systémových barvách procházelo samo sebou, protože
        // je nekreslí ani jeden stav.
        let unread = ReviewStateAppearance.color(of: .inconclusive(reason: .unreadCode))
        #expect(unread != ReviewStateAppearance.color(of: .clean))
        #expect(unread != ReviewStateAppearance.color(of: .failed(detail: "boom")))
    }

    // MARK: - Falešný poplach

    @Test("Běh, který kód přečetl a nic nenašel, je čistý")
    func aReadingRunWithoutFindingsIsClean() {
        // Bez tohohle testu by stačilo pravidlo „nula nálezů = podezřelé“ a poplach by přišel
        // u každého čistého PR.
        #expect(Policy.reviewState(for: makeRecord(runs: [readingRun()])) == .clean)
        #expect(Policy.suggestedVerdict(for: makeRecord(runs: [readingRun()])) == .approve)
    }

    @Test("Krátký a levný běh nad malým diffem se neoznačí")
    func aCheapShortRunIsNotFlagged() {
        // Cena se do rozhodnutí nebere vůbec — a je to změřené: na uložených datech otevřel běh
        // za 0,12 $ tři soubory. Rozhoduje **jediný pokus** v ose, ne částka.
        let cheap = makeStoredRun(
            timeline: timeline([ToolAttempt(name: "Read", detail: worktree.path() + "/README.md")])
        )

        #expect(Policy.reviewState(for: makeRecord(runs: [cheap])) == .clean)
    }

    @Test("Starší záznam bez osy zůstává čistý")
    func anOlderRecordWithoutATimelineStaysClean() {
        // Osa se ukládá od #203. Kdyby chybějící záznam znamenal obvinění, rozkřičelo by se okno
        // nad každým starším review naráz — a ta hláška by se přestala čítat.
        #expect(Policy.reviewState(for: makeRecord(runs: [makeStoredRun(timeline: nil)])) == .clean)
    }

    @Test("Běh, který nálezy má, se na čtení kódu neptá")
    func aRunWithFindingsIsNotAskedAboutReading() {
        // Nálezy mluví samy za sebe: v řádku je jejich počet, ne obvinění z nečtení.
        let record = makeRecord(runs: [unreadRun(findings: [makeReported(category: "style")])])

        #expect(Policy.reviewState(for: record) == .completed(findings: 1))
        #expect(Policy.suggestedVerdict(for: record) == .approve)
    }

    @Test("Jeden průkazný běh stačí, i když druhý kód neotevřel")
    func oneConclusiveRunIsEnough() {
        // `code-review` kód přečetl a nic nenašel — to je doklad čistoty a `security-review`,
        // který se nepodíval, ho nezneplatní. Poznat se to musí na **jeho chipu**, ne na řádku.
        let record = makeRecord(runs: [readingRun(), unreadRun()])
        let chips = Policy.chips(
            for: record,
            skills: ["code-review", "security-review"],
            running: []
        )

        #expect(Policy.reviewState(for: record) == .clean)
        #expect(chips.first?.state == .clean)
        if case .inconclusive = chips.last?.state {} else {
            Issue.record("Druhý chip měl být nejistý, je \(String(describing: chips.last?.state))")
        }
    }

    // MARK: - Sejde-li se víc důvodů

    @Test("Ztracený nález přebíjí nepřečtený kód")
    func droppedFindingsWinOverUnreadCode() {
        // O ztraceném nálezu se dá říct něco adresnějšího: víme, že něco bylo, a nemáme to.
        let record = makeRecord(runs: [unreadRun(droppedFindings: 1)])

        #expect(Policy.reviewState(for: record) == .inconclusive(reason: .droppedFindings))
    }

    @Test("Chybějící hlášení přebíjí nepřečtený kód")
    func aMissingReportWinsOverUnreadCode() {
        let record = makeRecord(runs: [unreadRun(calledReportFindings: false)])

        #expect(Policy.reviewState(for: record) == .inconclusive(reason: .noReport))
    }

    @Test("Bez důvodu zbývá nejslabší tvrzení")
    func withoutAReasonTheWeakestClaimWins() {
        // `inconclusiveReason(for:)` se volá jedině nad záznamem, který průkazný není — takový
        // záznam má vždycky aspoň jeden důvod. Tvrdí se to i pro ten stav, do kterého se okno
        // nedostane: kdyby se tam přesto někdo dostal, ať je z toho **nejslabší** ze tří
        // tvrzení, a ne obvinění z nečtení kódu.
        #expect(Policy.inconclusiveReason(for: makeRecord(runs: [readingRun()])) == .noReport)
    }

    @Test("Přednosti jsou vyjmenované všechny")
    func everyReasonHasAPrecedence() {
        // Kdyby přibyl čtvrtý důvod a zapomněl se do `byPrecedence`, spadl by tichý fallback
        // na `noReport` — tedy nejslabší tvrzení nad nejsilnějším signálem.
        #expect(Set(InconclusiveReason.byPrecedence) == Set(InconclusiveReason.allCases))
        #expect(InconclusiveReason.byPrecedence.count == InconclusiveReason.allCases.count)
    }

    @Test("Nedoběhlý běh zůstává timeoutem, ne nepřečteným kódem")
    func anUnfinishedRunKeepsItsOwnState() {
        // Zabitý běh kód taky neotevřel, ale hlavní zpráva je, že neskončil — a dělá se s tím
        // něco jiného (zvednout limit, ne pustit znovu).
        let record = makeRecord(runs: [
            makeStoredRun(outcome: .timedOut, timeline: timeline([ToolAttempt(name: "Bash", detail: "git diff")])),
        ])

        #expect(Policy.reviewState(for: record) == .timedOut(findings: 0))
    }

    @Test("Odmítnutý nástroj z toho stav nedělá")
    func aDeniedToolDoesNotMakeTheState() {
        // Odmítnutí je běžný stav read-only režimu (`Bash(gh:*)` se odmítnout **má**) a session
        // po něm skončí `success`. Rozhoduje čtení souboru, ne to, že se něco odmítlo.
        let record = makeRecord(runs: [
            makeStoredRun(timeline: timeline([
                ToolAttempt(name: "Bash", detail: "gh pr view", outcome: .init(kind: .denied)),
                ToolAttempt(name: "Read", detail: worktree.path() + "/src/Job/Runner.php"),
            ])),
        ])

        #expect(Policy.reviewState(for: record) == .clean)
    }
}
