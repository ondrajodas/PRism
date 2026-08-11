import Foundation
import Testing

@testable import PRism

/// Pruh záložek PR a odznak u `Kontrol` (#215).
///
/// Dvě věci se dají pokazit potichu: **nakreslit tab `Kontroly` u PR bez CI** (prázdný tab
/// s nadpisem tvrdí, že se něco nepovedlo) a **spočítat odznak podle většiny místo nejhoršího**
/// (dvanáct zelených a jeden červený je červený stav).
@Suite("Záložky PR a odznak kontrol")
struct PullRequestTabListTests {
    private func check(_ name: String, _ bucket: String) -> PullRequestCheck {
        PullRequestCheck(
            name: name,
            outcome: .init(bucket: bucket),
            link: nil,
            startedAt: nil,
            completedAt: nil
        )
    }

    private func badge(_ buckets: [String]) -> PullRequestTabBadge? {
        Policy.checksBadge(of: Policy.summary(of: buckets.enumerated().map { check("c\($0.0)", $0.1) }))
    }

    // MARK: - Které záložky se kreslí

    @Test("S checky je v pruhu všech šest záložek")
    func drawsEveryTabWithChecks() {
        #expect(Policy.tabs(hasChecks: true) == PullRequestTab.allCases)
    }

    /// **Nejcennější test téhle sady.** PR bez CI je běžná věc a prázdný tab s nadpisem by
    /// o něm tvrdil, že se něco nepovedlo.
    @Test("Bez checků tab Kontroly v pruhu není")
    func dropsTheChecksTabWithoutChecks() {
        let tabs = Policy.tabs(hasChecks: false)

        #expect(!tabs.contains(.checks))
        #expect(tabs.count == PullRequestTab.allCases.count - 1)
    }

    /// Odpadnout smí **jedině** `Kontroly` — ostatní záložky se kreslí vždycky, i když jsou
    /// prázdné, protože „žádný nález“ a „žádná konverzace“ jsou samy odpovědí.
    @Test("Vypadnou jen Kontroly, zbytek pruhu zůstává")
    func keepsEveryOtherTab() {
        #expect(Policy.tabs(hasChecks: false)
            == PullRequestTab.allCases.filter { $0 != .checks })
    }

    /// Pořadí se bere z `allCases`, ne z vlastního výčtu — dvě pořadí by se rozešla a dělič
    /// v pruhu se počítá z pozice v tom, co se kreslí.
    @Test("Pořadí je totéž jako ve výčtu")
    func keepsTheDeclaredOrder() {
        for hasChecks in [true, false] {
            let tabs = Policy.tabs(hasChecks: hasChecks)
            let indexes = tabs.compactMap { PullRequestTab.allCases.firstIndex(of: $0) }

            #expect(indexes == indexes.sorted())
        }
    }

    /// Výchozí tab musí v pruhu být **v obou případech**, jinak by se uložená volba zarovnávala
    /// na záložku, která se nekreslí.
    @Test("Výchozí tab je v pruhu vždycky")
    func alwaysKeepsTheStandardTab() {
        #expect(Policy.tabs(hasChecks: true).contains(PullRequestTab.standard))
        #expect(Policy.tabs(hasChecks: false).contains(PullRequestTab.standard))
    }

    // MARK: - Odznak podle nejhoršího stavu

    @Test("Spadlé dávají červený počet, ne tichou kapsli")
    func marksFailuresAsBlocking() {
        #expect(badge(["fail"]) == .blocking(1))
        #expect(badge(["fail", "fail", "pass"]) == .blocking(2))
    }

    /// Tatáž úvaha jako u chipu v hlavičce (#209): dvanáct zelených a jeden červený je červený
    /// stav, ne „skoro hotovo“.
    @Test("Nejhorší stav rozhoduje, ne většina")
    func takesTheWorstNotTheMajority() {
        let buckets = Array(repeating: "pass", count: 12) + ["fail"]

        #expect(badge(buckets) == .blocking(1))
    }

    /// Zrušený běh se počítá ke spadlým (`Policy.summary`), takže odznak je červený i nad ním —
    /// z obojího plyne, že se PR nemá čím pochlubit.
    @Test("Zrušený check je taky červený odznak")
    func marksCancelledAsBlocking() {
        #expect(badge(["cancel"]) == .blocking(1))
        #expect(badge(["cancel", "fail"]) == .blocking(2))
    }

    /// „Běží“ je **stav, ne množství**: u dvou běžících jobů by dvojka o průběhu neřekla nic.
    /// Tentýž puntík jako u `Průběhu`.
    @Test("Běžící checky dávají puntík, ne číslo")
    func marksRunningAsLive() {
        #expect(badge(["pending"]) == .live)
        #expect(badge(["pending", "pending", "pass"]) == .live)
    }

    @Test("Spadlé přebijí běžící")
    func failuresOutrankRunning() {
        #expect(badge(["pending", "fail"]) == .blocking(1))
    }

    /// **Zelené CI odznak nedostane.** Je to výchozí stav a číslo u něj by byl šum, kvůli
    /// kterému by se přestaly čít i ty ostatní dva odznaky.
    @Test("Zelené ani přeskočené checky odznak nemají")
    func staysQuietWhenNothingNeedsAttention() {
        #expect(badge(["pass"]) == nil)
        #expect(badge(Array(repeating: "pass", count: 12)) == nil)
        #expect(badge(["skipping"]) == nil)
        #expect(badge(["pass", "skipping"]) == nil)
    }

    /// Prázdná sada nemá odznak — ale hlavně se u ní tab vůbec nekreslí, takže je to druhá
    /// pojistka téhož.
    @Test("Bez checků není odznak")
    func staysQuietWithoutChecks() {
        #expect(badge([]) == nil)
    }
}
