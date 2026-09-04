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
        // Od #432 **z palety**, ne systémové `.orange`/`.red`: kapsle je text na tlumeném washi
        // a systémová škála je navržená jako výplň s bílým textem — ve světlém režimu z ní vyšlo
        // 1,85 a 2,70. Čísla i prahy jsou v `PillTypesettingTests`.
        #expect(ReviewStateAppearance.color(of: state) == Palette.find)
        #expect(ReviewStateAppearance.color(of: state, blocking: 1) == Palette.crit)
        #expect(ReviewStateAppearance.color(of: state) != .orange)
        #expect(ReviewStateAppearance.color(of: state, blocking: 1) != .red)
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
        #expect(ReviewStateAppearance.color(of: .clean) == Palette.ok)
        #expect(ReviewStateAppearance.color(of: .failed(detail: "boom")) == Palette.crit)
        // A ani jedna z nich není ta systémová, ze které se to u #432 převádělo.
        #expect(ReviewStateAppearance.color(of: .clean) != .green)
        #expect(ReviewStateAppearance.color(of: .failed(detail: "boom")) != .red)
    }

    @Test("Odmítnuté není čisté")
    func dismissedIsNotClean() {
        // #113: „nic jsem nenašel" a „našel a já to zamítl" jsou dvě tvrzení.
        #expect(ReviewStateAppearance.label(of: .dismissed(findings: 3)) == "odmítnuto · 3")
        // Od #309 tyrkysová **z palety**, ne systémová `.mint`: v okně má být jedna tyrkysová,
        // ne dvě skoro stejné. Že to je opravdu jiná barva a že je čitelnější, měří `MintTokenTests`.
        #expect(ReviewStateAppearance.color(of: .dismissed(findings: 3)) == Palette.mint)
        #expect(ReviewStateAppearance.color(of: .dismissed(findings: 3)) != .mint)
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
        #expect(ReviewStateAppearance.color(of: .timedOut(findings: 0)) == Palette.crit)
        #expect(ReviewStateAppearance.color(of: .timedOut(findings: 2)) == Palette.crit)
        #expect(ReviewStateAppearance.color(of: .interrupted(findings: 0)) == Palette.crit)
        #expect(ReviewStateAppearance.color(of: .interrupted(findings: 2)) == Palette.crit)
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
        // Od #309 akcent **z palety**, ne systémový: `.tint(Palette.accent)` z kořene okna na
        // `Color.accentColor` nezabírá, takže se odznak kreslil systémovou modrou. Že běžící stav
        // zůstává akcentem (a nedostal mint, i když je to stav), zdůvodňuje `ReviewStateAppearance`.
        #expect(ReviewStateAppearance.color(of: .running(finished: 2, total: 3), blocking: 1) == Palette.accent)
        #expect(ReviewStateAppearance.color(of: .running(finished: 2, total: 3), blocking: 1) != .accentColor)
    }

    @Test("Zastaralé zůstává okrové")
    func staleStaysOchre() {
        // Nálezy patří commitu, který v PR není — to přebíjí i blokující.
        #expect(ReviewStateAppearance.label(of: .stale, blocking: 2) == "zastaralé")
        // Od #383 **z palety**, ne systémová `.yellow`: návrh má `.pill.stale { color: var(--stale) }`
        // a systémová `#FFCC00` měla na vlastní kapsli ve světlém režimu kontrast 1,41. Tatáž
        // výměna jako u `dismissed` v #309 a ze stejného důvodu.
        #expect(ReviewStateAppearance.color(of: .stale, blocking: 2) == Palette.stale)
        #expect(ReviewStateAppearance.color(of: .stale, blocking: 2) != .yellow)
    }

    /// Řádek a chip revieweera mluví o tomtéž běhu, takže se **nesmí lišit ani odstínem** (#383).
    /// Do #383 tady byla systémová žlutá a chip kreslil `Palette.stale` — a komentář u toho tvrdil,
    /// že je to jedna barva. Nález Copilota na #403; tvrzení místo komentáře.
    @Test("Neprůkazné má v řádku i v chipu jednu barvu")
    func inconclusiveSharesOneColourWithTheChip() {
        for reason in InconclusiveReason.allCases {
            let row = ReviewStateAppearance.color(of: .inconclusive(reason: reason))
            #expect(row == Palette.stale)
            #expect(row == ReviewerChipsView.color(.inconclusive("cokoli")))
            #expect(row != .yellow)
            // A od `zastaralé` se to pozná **textem**, ne barvou — tu mají schválně stejnou.
            #expect(
                ReviewStateAppearance.label(of: .inconclusive(reason: reason))
                    != ReviewStateAppearance.label(of: .stale)
            )
        }
    }

    // **Proužek reviewerů odešel s #502** — v řádku fronty je na jeho místě mapa PR, takže
    // `ReviewStateAppearance.color(of: ReviewerShare.Outcome)` už nikdo nekreslí a spolu s ním
    // odsud odešla dvě tvrzení: barvy jednotlivých dílů a to, že díl nebere nic ze systémové
    // škály (#432). **Není to ztráta pokrytí:** obojí se nad `ReviewState` tvrdí v testech výš
    // (u každého stavu je vedle barvy z palety i nerovnost proti té systémové) a rozhodnutí
    // „čisto versus nemám co říct“, na kterém proužek stál, drží `Policy.chips`
    // (`UnreadCodeStateTests.theChipSaysWhatIsMissing`).
}
