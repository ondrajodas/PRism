import Foundation

/// Které segmenty panelu se kreslí a co dělat s tím vybraným, když v nich není (#333).
///
/// Rozhoduje o tom **čí je PR**: na cizím se sbírá verdikt (`Moje review`), na vlastním zadání pro
/// agenta. Volba tabu je přitom **jedna pro celé okno**, ne pro každý PR, takže přepnutí z cizího
/// PR na vlastní musí mít odpověď na otázku „a co teď mám ukázat“ — bez ní by v panelu zůstal
/// vybraný tab, který na téhle obrazovce není.
extension Policy {
    /// Segmenty panelu, v pořadí zleva.
    ///
    /// **Nikdy oba** `draft` a `agentPrompt`: verdikt na vlastním PR GitHub odmítne (422, změřeno
    /// u #62) a zakázané tlačítko svádí na něj kliknout a přečíst si chybu. Panel má jednu úlohu
    /// a ta se jmenuje v jeho segmentu.
    static func reviewPanelTabs(for ownership: PullRequestOwnership) -> [ReviewPanelTab] {
        switch ownership {
        case .mine: [.findings, .agentPrompt]
        case .theirs: [.findings, .draft]
        }
    }

    /// Tab, který se má ukázat, když je vybraný `tab`. Ten vybraný se **přeloží**, ne zahodí.
    ///
    /// Kdo si na cizím PR nechal otevřené `Moje review` a přepne na vlastní, má vidět `Zadání` —
    /// tedy tu práci, která na vlastním PR to `Moje review` zastupuje. Spadnout na `Nálezy` by
    /// znamenalo, že se panel po přepnutí PR sám přestaví na něco třetího.
    static func reviewPanelTab(
        _ tab: ReviewPanelTab,
        for ownership: PullRequestOwnership
    ) -> ReviewPanelTab {
        let tabs = reviewPanelTabs(for: ownership)
        guard !tabs.contains(tab) else { return tab }
        switch ownership {
        case .mine: return .agentPrompt
        case .theirs: return .draft
        }
    }
}
