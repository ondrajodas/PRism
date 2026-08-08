import Foundation
import Testing

@testable import PRism

@Suite("VisitLedger")
struct VisitLedgerTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 43)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Nikdy neviděný PR nemá návštěvu")
    func anUnvisitedPullRequestHasNoMark() {
        // `nil` je jiný stav než „dávno": nad prvním zobrazením se nemá co ukazovat, jinak by
        // „od tvé poslední návštěvy" znamenalo „od začátku věků".
        let ledger = VisitLedger(preferences: InMemoryPreferences())

        #expect(ledger.lastVisit(to: pr) == nil)
    }

    @Test("Zapsaná návštěva se přečte zpátky")
    func aRecordedVisitSurvives() {
        let preferences = InMemoryPreferences()
        VisitLedger(preferences: preferences).record(pr, at: now)

        // Nová instance nad týmiž předvolbami — tohle je to, co se děje při dalším spuštění.
        #expect(VisitLedger(preferences: preferences).lastVisit(to: pr) == now)
    }

    @Test("Návštěvy různých PR se nepletou")
    func visitsOfDifferentPullRequestsStayApart() {
        let preferences = InMemoryPreferences()
        let ledger = VisitLedger(preferences: preferences)

        ledger.record(pr, at: now)
        ledger.record(other, at: now.addingTimeInterval(60))

        #expect(ledger.lastVisit(to: pr) == now)
        #expect(ledger.lastVisit(to: other) == now.addingTimeInterval(60))
    }

    @Test("Zápis zahodí, co se přežilo")
    func writingCleansUpExpiredVisits() {
        // Zavřený PR se do seznamu nevrátí, takže by jeho záznam ležel v předvolbách napořád.
        let preferences = InMemoryPreferences()
        let ledger = VisitLedger(preferences: preferences)
        ledger.record(other, at: now)

        ledger.record(pr, at: now.addingTimeInterval(VisitLedger.retention + 1))

        #expect(ledger.lastVisit(to: other) == nil)
        #expect(ledger.lastVisit(to: pr) != nil)
    }

    @Test("Záznam těsně pod hranicí zůstává")
    func aVisitJustUnderTheLimitStays() {
        let preferences = InMemoryPreferences()
        let ledger = VisitLedger(preferences: preferences)
        ledger.record(other, at: now)

        ledger.record(pr, at: now.addingTimeInterval(VisitLedger.retention - 1))

        #expect(ledger.lastVisit(to: other) == now)
    }

    @Test("Rozbitá hodnota se čte jako prázdno, ne jako pád")
    func brokenDataReadsAsEmpty() {
        // Bezpečný směr: prázdno vyjde jako „nikdy jsem tu nebyl", takže se banner neukáže.
        // Opačná volba by ukazovala změny proti času, který jsme si vymysleli.
        let preferences = InMemoryPreferences()
        preferences.setPreference("{tohle není JSON", forKey: "pullRequests.lastVisits")
        let ledger = VisitLedger(preferences: preferences)

        #expect(ledger.lastVisit(to: pr) == nil)

        // A zápis přes rozbitou hodnotu funguje dál — jinak by se stav nedal opravit.
        ledger.record(pr, at: now)
        #expect(ledger.lastVisit(to: pr) == now)
    }
}
