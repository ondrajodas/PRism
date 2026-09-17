import Foundation
import Testing

@testable import PRism

/// Návrh review, který aplikace složí sama (#520) — **vyčerpávajícím výčtem**, protože je to
/// čistá funkce a jediné místo, kde se to rozhoduje.
///
/// **Nejcennější jsou tady tvrzení o tom, co se do návrhu NEdostane**: odmítnutý nález,
/// nejistý nález, nález z místa, kde se reviewery neshodnou, a cokoli nad zastaralými nálezy.
/// Ta se rozbijí potichu — výsledkem porušení není chyba, ale komentář v rozdělaném review,
/// o kterém jsem nevěděl, že tam je, a který pak odešle potvrzení.
@Suite("Policy — návrh review (#520)")
struct AutoDraftPolicyTests {
    private let head = "aaaa1111"

    private func record(
        _ findings: [ReportedFinding],
        reviewer: String = "code-review",
        isStale: Bool = false
    ) -> ReviewRecord {
        makeRecord(runs: [makeStoredRun(skill: reviewer, findings: findings)], isStale: isStale)
    }

    private func record(runs: [(reviewer: String, findings: [ReportedFinding])]) -> ReviewRecord {
        makeRecord(runs: runs.map { makeStoredRun(skill: $0.reviewer, findings: $0.findings) })
    }

    private func decide(
        _ record: ReviewRecord?,
        draft: ReviewDraft? = nil,
        ownership: PullRequestOwnership = .theirs,
        isAllowed: Bool = true,
        head: String? = "aaaa1111"
    ) -> AutoDraftDecision {
        Policy.autoDraft(
            record: record,
            draft: draft,
            ownership: ownership,
            isAllowed: isAllowed,
            head: head
        )
    }

    private func draft() -> ReviewDraft {
        ReviewDraft(
            pullRequest: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42),
            headSha: "aaaa1111",
            body: "moje věta"
        )
    }

    // MARK: - Jeden nález: pět odpovědí, každá z jiného důvodu

    @Test("CONFIRMED bez rozporu se převezme")
    func adoptsConfirmed() {
        let finding = makeFinding(file: "Cart.php", line: 10, verdict: .confirmed)
        #expect(Policy.autoDraftPick(of: finding, dismissal: nil, doubt: nil) == .adopt)
    }

    @Test("PLAUSIBLE zůstává sporný a důvod je vidět")
    func leavesPlausible() {
        let finding = makeFinding(file: "Cart.php", line: 10, verdict: .plausible)
        #expect(Policy.autoDraftPick(of: finding, dismissal: nil, doubt: nil) == .contested(.plausible))
    }

    /// „Neřekl jsem“ není „jsem si jistý“ — a je to vlastní důvod, ne `PLAUSIBLE`.
    @Test("Nález bez verdiktu zůstává sporný jako „bez verdiktu“")
    func leavesFindingWithoutVerdict() {
        let finding = makeFinding(file: "Cart.php", line: 10, verdict: nil)
        #expect(Policy.autoDraftPick(of: finding, dismissal: nil, doubt: nil) == .contested(.noVerdict))
    }

    /// **Nejcennější tvrzení téhle sady.** Odmítnutý nález se nesmí ani převzít, ani nabídnout
    /// jako sporný — o něm rozhodl člověk (#113) a návrh ho zpochybňovat nemá čím.
    @Test("Odmítnutý nález se nepřevezme ani se nenabídne jako sporný")
    func skipsDismissed() {
        let finding = makeFinding(file: "Cart.php", line: 10, verdict: .confirmed)
        let dismissal = FindingDismissal(reason: .invalid, dismissedAt: Date(timeIntervalSince1970: 1))
        #expect(Policy.autoDraftPick(of: finding, dismissal: dismissal, doubt: nil) == .skip(.dismissed))
    }

    /// Rozpor přebíjí verdikt: dva `CONFIRMED` proti sobě jsou pořád spor.
    @Test("Rozpor na místě přebije i CONFIRMED")
    func disagreementBeatsVerdict() {
        let finding = makeFinding(file: "Cart.php", line: 10, verdict: .confirmed)
        let doubt = AutoDraftDoubt.disagreement(reviewers: ["php-review", "security-review"])
        #expect(Policy.autoDraftPick(of: finding, dismissal: nil, doubt: doubt) == .contested(doubt))
    }

    // MARK: - Rozpor na místě

    @Test("Dva reviewery se shodným verdiktem rozpor nedělají")
    func noDisagreementWhenVerdictsMatch() {
        let group = FindingGroup(
            file: "Cart.php",
            line: 10,
            findings: [
                makeFinding(file: "Cart.php", line: 10, verdict: .confirmed, reviewer: "php-review"),
                makeFinding(file: "Cart.php", line: 10, verdict: .confirmed, reviewer: "security-review"),
            ]
        )
        #expect(Policy.disagreement(in: group) == nil)
    }

    @Test("Dva reviewery s jiným verdiktem dají rozpor se jmény v abecedě")
    func disagreementNamesReviewers() {
        let group = FindingGroup(
            file: "Cart.php",
            line: 10,
            findings: [
                makeFinding(file: "Cart.php", line: 10, verdict: .plausible, reviewer: "security-review"),
                makeFinding(file: "Cart.php", line: 10, verdict: .confirmed, reviewer: "php-review"),
            ]
        )
        #expect(
            Policy.disagreement(in: group)
                == .disagreement(reviewers: ["php-review", "security-review"])
        )
    }

    /// Shoda dvou reviewerů, ze kterých jednomu nevěřím, není shoda — a spor taky ne.
    @Test("Odmítnutý nález do rozporu nemluví")
    func dismissedFindingIsNotPartOfDisagreement() {
        let mine = makeFinding(file: "Cart.php", line: 10, verdict: .confirmed, reviewer: "php-review")
        let other = makeFinding(file: "Cart.php", line: 10, verdict: .plausible, reviewer: "security-review")
        var group = FindingGroup(file: "Cart.php", line: 10, findings: [mine, other])
        group.dismissals = makeDismissals([other])
        #expect(Policy.disagreement(in: group) == nil)
    }

    @Test("Jeden reviewer si neodporuje ani dvěma nálezy na jednom řádku")
    func oneReviewerNeverDisagreesWithHimself() {
        let group = FindingGroup(
            file: "Cart.php",
            line: 10,
            findings: [
                makeFinding(file: "Cart.php", line: 10, verdict: .confirmed, summary: "a"),
                makeFinding(file: "Cart.php", line: 10, verdict: .plausible, summary: "b"),
            ]
        )
        #expect(Policy.disagreement(in: group) == nil)
    }

    // MARK: - Plán nad celým záznamem

    @Test("Ze tří jistých a dvou nejistých vyjdou tři převzaté a dva sporné")
    func splitsPlan() {
        let record = record([
            makeReported(file: "Cart.php", line: 10, verdict: .confirmed, summary: "a"),
            makeReported(file: "Cart.php", line: 20, verdict: .confirmed, summary: "b"),
            makeReported(file: "Order.php", line: 5, verdict: .confirmed, summary: "c"),
            makeReported(file: "Order.php", line: 9, verdict: .plausible, summary: "d"),
            makeReported(file: nil, line: nil, verdict: nil, summary: "e"),
        ])
        let plan = Policy.autoDraftPlan(of: record)
        #expect(plan.adopt.map(\.summary) == ["a", "b", "c"])
        #expect(plan.contested.count == 2)
    }

    @Test("Nález bez místa se převezme jako kterýkoli jiný")
    func adoptsFindingWithoutLocation() {
        let record = record([makeReported(file: nil, line: nil, verdict: .confirmed, summary: "chybí testy")])
        #expect(Policy.autoDraftPlan(of: record).adopt.map(\.summary) == ["chybí testy"])
    }

    @Test("Dva reviewery, kteří se na místě neshodnou, nechají oba nálezy sporné")
    func contestsBothSidesOfDisagreement() {
        let record = record(runs: [
            ("php-review", [makeReported(file: "Cart.php", line: 10, verdict: .confirmed, summary: "a")]),
            ("security-review", [makeReported(file: "Cart.php", line: 10, verdict: .plausible, summary: "b")]),
        ])
        let plan = Policy.autoDraftPlan(of: record)
        #expect(plan.adopt.isEmpty)
        #expect(plan.contested.count == 2)
        #expect(plan.contested.values.allSatisfy {
            $0 == .disagreement(reviewers: ["php-review", "security-review"])
        })
    }

    @Test("Shodní reviewery na jednom řádku se převezmou oba")
    func adoptsBothWhenReviewersAgree() {
        let record = record(runs: [
            ("php-review", [makeReported(file: "Cart.php", line: 10, verdict: .confirmed, summary: "a")]),
            ("security-review", [makeReported(file: "Cart.php", line: 10, verdict: .confirmed, summary: "b")]),
        ])
        let plan = Policy.autoDraftPlan(of: record)
        #expect(plan.adopt.count == 2)
        #expect(plan.contested.isEmpty)
    }

    // MARK: - Kdy se návrh vůbec skládá

    @Test("Cizí otevřený PR se zapnutou branou návrh složí")
    func composesOnForeignPullRequest() {
        let record = record([makeReported(file: "Cart.php", line: 10, verdict: .confirmed)])
        guard case .compose(let plan) = decide(record) else {
            Issue.record("čekal se návrh")
            return
        }
        #expect(plan.adopt.count == 1)
    }

    /// **Výchozí stav.** Bez tohohle by se panel začal plnit sám u každého, kdo aplikaci
    /// aktualizuje — tedy změna chování, o kterou nikdo nepožádal.
    @Test("S vypnutou branou se nesloží nic")
    func gateClosedByDefault() {
        let record = record([makeReported(file: "Cart.php", line: 10, verdict: .confirmed)])
        #expect(decide(record, isAllowed: false) == .skip(.gateClosed))
    }

    @Test("Na vlastním PR se návrh neskládá — review na něj stejně neodejde")
    func skipsOwnPullRequest() {
        let record = record([makeReported(file: "Cart.php", line: 10, verdict: .confirmed)])
        #expect(decide(record, ownership: .mine) == .skip(.ownPullRequest))
    }

    /// Tvrdá podmínka č. 5 ze strany návrhu: **jak se hlava pohne, převzetí zhasne.**
    @Test("Nad posunutou hlavou se návrh neskládá")
    func skipsWhenHeadMoved() {
        let record = record([makeReported(file: "Cart.php", line: 10, verdict: .confirmed)])
        #expect(decide(record, head: "bbbb2222") == .skip(.staleFindings))
    }

    @Test("Zastaralý záznam návrh nesloží")
    func skipsStaleRecord() {
        let record = record([makeReported(file: "Cart.php", line: 10, verdict: .confirmed)], isStale: true)
        #expect(decide(record) == .skip(.staleFindings))
    }

    /// Neznámá hlava je **zákaz, ne povolení** — dokud nevíme, na čem PR stojí, nedá se tvrdit,
    /// že návrh platí pro kód, který v něm je.
    @Test("Bez známé hlavy se návrh neskládá")
    func skipsWhenHeadUnknown() {
        let record = record([makeReported(file: "Cart.php", line: 10, verdict: .confirmed)])
        #expect(decide(record, head: nil) == .skip(.staleFindings))
    }

    @Test("Bez záznamu není z čeho skládat")
    func skipsWithoutRecord() {
        #expect(decide(nil) == .skip(.staleFindings))
    }

    /// **Druhé nejcennější tvrzení téhle sady.** Co jsem začal psát já, si aplikace nepřepíše.
    @Test("Ručně rozepsaný draft automat nepřepíše")
    func neverOverwritesExistingDraft() {
        let record = record([makeReported(file: "Cart.php", line: 10, verdict: .confirmed)])
        #expect(decide(record, draft: draft()) == .skip(.draftExists))
    }

    @Test("Čisté review žádný návrh nesloží")
    func skipsCleanReview() {
        #expect(decide(record([])) == .skip(.nothingToPropose))
    }

    @Test("Ze samých odmítnutých nálezů se návrh nesloží")
    func skipsWhenEverythingIsDismissed() {
        var record = record([makeReported(file: "Cart.php", line: 10, verdict: .confirmed)])
        record.dismissals = makeDismissals(record.findings)
        #expect(decide(record) == .skip(.nothingToPropose))
    }

    /// Návrh, ve kterém zbyly samé sporné nálezy, se **skládá** — pruh v panelu je to jediné,
    /// co nad prázdným panelem vysvětlí, proč v něm nic není.
    @Test("Samé sporné nálezy návrh složí, i když se nepřevezme nic")
    func composesEvenWithoutAdoptions() {
        let record = record([makeReported(file: "Cart.php", line: 10, verdict: .plausible)])
        guard case .compose(let plan) = decide(record) else {
            Issue.record("čekal se návrh")
            return
        }
        #expect(plan.adopt.isEmpty)
        #expect(plan.contested.count == 1)
    }

    // MARK: - Co je z návrhu vidět

    @Test("Bez razítka se u nálezů nekreslí žádná značka")
    func noDoubtsWithoutStamp() {
        #expect(Policy.autoDraftDoubts(of: record([makeReported(verdict: .plausible)])).isEmpty)
    }

    @Test("Razítko vydá značky, které si do něj návrh zapsal")
    func doubtsComeFromStamp() {
        var record = record([makeReported(file: "Cart.php", line: 10, verdict: .plausible)])
        let key = Policy.key(of: record.findings[0])
        record.autoDraft = StoredAutoDraft(
            at: Date(timeIntervalSince1970: 1),
            adopted: 0,
            contested: [key: .plausible]
        )
        #expect(Policy.autoDraftDoubts(of: record) == [key: .plausible])
    }

    @Test("Věta pruhu nese obě čísla i ve správných tvarech")
    func tallyText() {
        #expect(Policy.autoDraftTally(adopted: 3, contested: 2) == "z 5 nálezů 3 převzaty, 2 sporné")
        #expect(Policy.autoDraftTally(adopted: 1, contested: 0) == "z 1 nálezu 1 převzat, 0 sporných")
        #expect(Policy.autoDraftTally(adopted: 0, contested: 3) == "z 3 nálezů 0 převzato, 3 sporné")
    }

    @Test("Pruh v panelu nese hodiny i počty")
    func noteText() {
        #expect(
            Policy.autoDraftNote(at: "21:52", adopted: 3, contested: 2)
                == "Návrh připravený automatem · 21:52 · z 5 nálezů 3 převzaty, 2 sporné"
        )
    }

    // MARK: - Pilulka v řádku fronty

    private func stamp(adopted: Int, contested: Int) -> StoredAutoDraft {
        StoredAutoDraft(
            at: Date(timeIntervalSince1970: 1),
            adopted: adopted,
            contested: Dictionary(
                uniqueKeysWithValues: (0..<contested).map { (FindingKey("k\($0)"), AutoDraftDoubt.plausible) }
            )
        )
    }

    /// **Razítko mluví i po vypnutí volby.** V panelu leží komentáře, které tam někdo nenapsal —
    /// schovat o nich zprávu jen proto, že se volba mezitím vypnula, by z nich udělalo práci bez
    /// vysvětlení. Brána brání tomu, aby **vznikl další** návrh, ne tomu o něm mluvit.
    @Test("Razítko mluví i s vypnutou branou, živý návrh verdiktu ne")
    func stampSpeaksEvenWithTheGateClosed() {
        #expect(
            Policy.autoDraftPill(stamp: stamp(adopted: 3, contested: 2), suggestion: .approve, isAllowed: false)
                == .composed(adopted: 3, contested: 2)
        )
        #expect(Policy.autoDraftPill(stamp: nil, suggestion: .approve, isAllowed: false) == nil)
    }

    @Test("Razítko dá pilulku s oběma čísly")
    func pillFromStamp() {
        let pill = Policy.autoDraftPill(
            stamp: stamp(adopted: 3, contested: 2),
            suggestion: .requestChanges,
            isAllowed: true
        )
        #expect(pill == .composed(adopted: 3, contested: 2))
        #expect(pill?.text == "návrh review · 3 + 2 sporné")
    }

    @Test("Bez sporných se druhá půlka pilulky nepíše")
    func pillWithoutContested() {
        let pill = Policy.autoDraftPill(stamp: stamp(adopted: 2, contested: 0), suggestion: nil, isAllowed: true)
        #expect(pill?.text == "návrh review · 2")
    }

    @Test("U čistého review zbude návrh verdiktu")
    func pillFromVerdict() {
        let pill = Policy.autoDraftPill(stamp: nil, suggestion: .approve, isAllowed: true)
        #expect(pill == .verdict(.approve))
        #expect(pill?.text == "návrh: schválit")
    }

    /// `REQUEST_CHANGES` bez jediného převzatého nálezu znamená, že se všechno nechalo na
    /// kliknutí — slíbit u toho hotový verdikt by tvrdilo, že je co odeslat.
    @Test("Nad vyžádáním změn bez návrhu se pilulka nekreslí")
    func noPillForRequestChanges() {
        #expect(Policy.autoDraftPill(stamp: nil, suggestion: .requestChanges, isAllowed: true) == nil)
    }

    @Test("Bez razítka i bez verdiktu řádek mlčí")
    func noPillWithoutAnything() {
        #expect(Policy.autoDraftPill(stamp: nil, suggestion: nil, isAllowed: true) == nil)
    }
}
