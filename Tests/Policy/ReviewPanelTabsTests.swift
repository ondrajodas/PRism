import Testing

@testable import PRism

/// Které segmenty panelu se kreslí (#333) — čistá funkce, výčet obou stran.
///
/// Nejcennější tvrzení je to negativní: **na vlastním PR se `Moje review` nekreslí vůbec.**
/// Zašedlé by svádělo na něj kliknout a přečíst si 422 od GitHubu, a schované jen v jednom ze
/// dvou míst by znamenalo tab bez segmentu.
@Suite("Policy — segmenty panelu")
struct ReviewPanelTabsTests {
    @Test("Na vlastním PR je vedle nálezů zadání, ne review")
    func offersTheAgentPromptOnMyOwn() {
        #expect(Policy.reviewPanelTabs(for: .mine) == [.findings, .agentPrompt])
    }

    @Test("Na cizím PR je vedle nálezů review, ne zadání")
    func offersTheDraftOnSomebodyElses() {
        #expect(Policy.reviewPanelTabs(for: .theirs) == [.findings, .draft])
    }

    /// Volba tabu je jedna pro celé okno, takže po přepnutí PR musí být z čeho ukázat obsah —
    /// a `Nálezy` by znamenaly, že se panel sám přestaví na něco třetího.
    @Test("Vybraný tab, který na PR není, se přeloží na ten druhý")
    func translatesAMissingTab() {
        #expect(Policy.reviewPanelTab(.draft, for: .mine) == .agentPrompt)
        #expect(Policy.reviewPanelTab(.agentPrompt, for: .theirs) == .draft)
    }

    @Test("Vybraný tab, který na PR je, zůstává")
    func keepsATabThatExists() {
        #expect(Policy.reviewPanelTab(.findings, for: .mine) == .findings)
        #expect(Policy.reviewPanelTab(.findings, for: .theirs) == .findings)
        #expect(Policy.reviewPanelTab(.agentPrompt, for: .mine) == .agentPrompt)
        #expect(Policy.reviewPanelTab(.draft, for: .theirs) == .draft)
    }

    /// Každý tab z výčtu se dá na obou stranách přeložit na tab, který se doopravdy kreslí —
    /// jinak by v panelu zbyl prázdný obsah.
    @Test("Přeložený tab se vždycky kreslí")
    func alwaysTranslatesIntoADrawnTab() {
        for ownership in [PullRequestOwnership.mine, .theirs] {
            let drawn = Policy.reviewPanelTabs(for: ownership)
            for tab in ReviewPanelTab.allCases {
                #expect(drawn.contains(Policy.reviewPanelTab(tab, for: ownership)))
            }
        }
    }
}
