import SwiftUI
import Testing

@testable import PRism

@Suite("ReviewStateAppearance")
struct ReviewStateAppearanceTests {
    @Test("Blokující nález změní text i barvu")
    func aBlockingFindingChangesTextAndColour() {
        // Kvůli tomuhle #172 vzniklo: „3 nálezy" nešlo odlišit od „3 nálezy, z nichž jeden
        // zastavuje merge" ani textem, ani barvou.
        let state = ReviewState.completed(findings: 3)

        #expect(ReviewStateAppearance.label(of: state) == "3 nálezy")
        #expect(ReviewStateAppearance.label(of: state, blocking: 1) == "3 nálezy · 1 blokuje")
        #expect(ReviewStateAppearance.color(of: state) == .orange)
        #expect(ReviewStateAppearance.color(of: state, blocking: 1) == .red)
    }

    @Test("Bez blokujících odznak nenaroste o nulu")
    func withoutBlockingTheBadgeStaysShort() {
        #expect(ReviewStateAppearance.label(of: .completed(findings: 1), blocking: 0) == "1 nález")
    }

    @Test("Čisté a selhané se neslijí")
    func cleanAndFailedNeverMerge() {
        // Říkají opak jedno o druhém, takže se nesmí potkat ani v textu, ani v barvě.
        #expect(ReviewStateAppearance.label(of: .clean) == "čisté")
        #expect(ReviewStateAppearance.label(of: .failed(detail: "boom")) == "selhalo")
        #expect(ReviewStateAppearance.color(of: .clean) == .green)
        #expect(ReviewStateAppearance.color(of: .failed(detail: "boom")) == .red)
    }

    @Test("Odmítnuté není čisté")
    func dismissedIsNotClean() {
        // #113: „nic jsem nenašel" a „našel a já to zamítl" jsou dvě tvrzení.
        #expect(ReviewStateAppearance.label(of: .dismissed(findings: 3)) == "odmítnuto · 3")
        #expect(ReviewStateAppearance.color(of: .dismissed(findings: 3)) == .mint)
    }

    @Test("Přerušené není timeout")
    func interruptedIsNotTimedOut() {
        // #97: vedou jinam — u timeoutu se zvedá limit, u přerušení se pouští znovu.
        #expect(ReviewStateAppearance.label(of: .timedOut(findings: 2)) == "timeout · 2")
        #expect(ReviewStateAppearance.label(of: .interrupted(findings: 2)) == "přerušeno · 2")
    }

    @Test("Nedoběhlý běh nese důvod, počet i blokující")
    func anUnfinishedRunKeepsAllThree() {
        // Blokující nález platí i z poloviny běhu, ale důvod zůstává první — částečný výsledek
        // se nesmí tvářit jako hotový.
        #expect(
            ReviewStateAppearance.label(of: .timedOut(findings: 2), blocking: 1)
                == "timeout · 2 · 1 blokuje"
        )
        // Bez nálezů zůstane jen důvod — „timeout · 0" by tvrdilo, že se něco našlo.
        #expect(ReviewStateAppearance.label(of: .timedOut(findings: 0)) == "timeout")
    }

    @Test("Nedoběhlý běh zůstává červený i bez nálezů")
    func anUnfinishedRunStaysRed() {
        // Oranžová znamená „něco se našlo". U timeoutu a přerušení je ale hlavní zpráva ta,
        // že běh neskončil — `timeout · 0` oranžově by vypadalo jako výsledek, a je to selhání.
        #expect(ReviewStateAppearance.color(of: .timedOut(findings: 0)) == .red)
        #expect(ReviewStateAppearance.color(of: .timedOut(findings: 2)) == .red)
        #expect(ReviewStateAppearance.color(of: .interrupted(findings: 0)) == .red)
        #expect(ReviewStateAppearance.color(of: .interrupted(findings: 2)) == .red)
        // A stejnou barvu jako ostatní selhání — vedou jinam, ale obojí je „tohle neskončilo".
        #expect(
            ReviewStateAppearance.color(of: .timedOut(findings: 2))
                == ReviewStateAppearance.color(of: .failed(detail: "boom"))
        )
    }

    @Test("Běžící stav blokující ignoruje")
    func aRunningStateIgnoresBlocking() {
        // Během běhu se počty přepisují, takže se z nich nic netvrdí.
        #expect(ReviewStateAppearance.label(of: .running(finished: 2, total: 3), blocking: 1) == "běží 2/3")
        #expect(ReviewStateAppearance.color(of: .running(finished: 2, total: 3), blocking: 1) == .accentColor)
    }

    @Test("Zastaralé zůstává žluté")
    func staleStaysYellow() {
        // Nálezy patří commitu, který v PR není — to přebíjí i blokující.
        #expect(ReviewStateAppearance.color(of: .stale, blocking: 2) == .yellow)
        #expect(ReviewStateAppearance.label(of: .stale, blocking: 2) == "zastaralé")
    }

    @Test("Díl proužku má barvu podle výsledku")
    func everyShareHasItsColour() {
        #expect(ReviewStateAppearance.color(of: ReviewerShare.Outcome.blocking) == .red)
        #expect(ReviewStateAppearance.color(of: ReviewerShare.Outcome.findings) == .orange)
        #expect(ReviewStateAppearance.color(of: ReviewerShare.Outcome.clean) == .green)
        // Odmítnuté má stejnou barvu jako `ReviewState.dismissed` — řádek a odznak nesmí
        // o tomtéž říkat každý něco jiného.
        #expect(ReviewStateAppearance.color(of: ReviewerShare.Outcome.dismissed) == .mint)
        #expect(ReviewStateAppearance.color(of: ReviewerShare.Outcome.dismissed)
            == ReviewStateAppearance.color(of: .dismissed(findings: 1)))
        #expect(ReviewStateAppearance.color(of: ReviewerShare.Outcome.inconclusive) == .secondary)
    }
}
