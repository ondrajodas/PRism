import Foundation
import Testing

@testable import PRism

/// Záložky PR (#242): jak se jmenují a kde je mezi nimi dělič.
@Suite("Záložky PR")
struct PullRequestTabTests {
    /// `Kontroly` (#215) sedí **mezi `Konverzací` a `Nálezy`**, tedy nalevo od děliče: je to
    /// něco, co je na PR, ne výstup našich reviewerů.
    @Test("Pruh má šest záložek v pořadí, ve kterém se čtou")
    func order() {
        #expect(PullRequestTab.allCases.map(\.czechLabel)
            == ["Přehled", "Změněné soubory", "Konverzace", "Kontroly", "Nálezy", "Průběh"])
    }

    @Test("Otevírá se Přehledem")
    func standard() {
        #expect(PullRequestTab.standard == .overview)
    }

    /// Dělič odděluje to, co je na PR (a co má i GitHub), od toho, co s ním udělaly naše reviewery.
    /// `Kontroly` (#215) přišly doprostřed levé skupiny a nesmí se tím posunout.
    @Test("Výstup reviewerů je jedna souvislá skupina na konci")
    func reviewerOutputIsOneGroup() {
        let flags = PullRequestTab.allCases.map(\.isReviewerOutput)

        #expect(flags == [false, false, false, false, true, true])
        // Jeden přechod, tedy jeden dělič — ne dva a ne žádný.
        #expect(zip(flags, flags.dropFirst()).count { $0 != $1 } == 1)
    }

    /// **Počet záložek není funkcí dat** (#306). `PullRequestTabBar` kreslí `allCases` a nemá
    /// parametr, kterým by se dal pruh zúžit — do #306 ho měl a pruh se tím při **každém** otevření
    /// PR přeskládal z pěti záložek na šest. Test hlídá druhou polovinu toho tvrzení: že se výčet,
    /// ze kterého pruh kreslí, nezmenšil. Sám o sobě by prošel i po smazání jednoho prvku z testu
    /// pořadí výš, proto počet i jmenovitě `Kontroly`.
    @Test("Kontroly jsou ve výčtu, ze kterého pruh kreslí, vždycky")
    func stripAlwaysHasTheChecksTab() {
        #expect(PullRequestTab.allCases.count == 6)
        #expect(PullRequestTab.allCases.contains(.checks))
    }

    // MARK: - Panel s mým review (#294)

    /// Vyčerpávající výčet, ne tři reprezentanti: je to šest případů a jediné, co tuhle vlastnost
    /// drží, je právě ten výčet — přidaný sedmý tab by jinak mlčky dostal panel podle toho, kam ho
    /// někdo napsal.
    @Test("Panel je jen v Přehledu, Změněných souborech a Konverzaci")
    func panelTabs() {
        let withPanel = PullRequestTab.allCases.filter(\.showsReviewPanel)

        #expect(withPanel == [.overview, .filesChanged, .conversation])
        #expect(!PullRequestTab.checks.showsReviewPanel)
        #expect(!PullRequestTab.findings.showsReviewPanel)
        #expect(!PullRequestTab.progress.showsReviewPanel)
    }

    /// **Tohle je ten test, který tvrdí, že se něco NEstalo**: že se `showsReviewPanel` neohnul na
    /// `isReviewerOutput`. Ty dvě vlastnosti se rozcházejí právě v `Kontrolách` — jsou fakt o PR,
    /// takže **nalevo od děliče**, a panel přesto mít nemají. Kdyby se sloučily, dělič v pruhu
    /// záložek by se posunul a `Kontroly` by skočily do pravé skupiny.
    @Test("Panel se neřídí příznakem výstupu reviewerů")
    func panelIsNotReviewerOutput() {
        #expect(PullRequestTab.checks.isReviewerOutput == false)
        #expect(PullRequestTab.checks.showsReviewPanel == false)

        let sameEverywhere = PullRequestTab.allCases.allSatisfy { $0.showsReviewPanel == !$0.isReviewerOutput }
        #expect(!sameEverywhere, "vlastnosti splynuly — jedna z nich pak mluví o něčem jiném, než co dělá")
    }

    /// Tři a tři: kdyby panel zmizel odevšad nebo zůstal všude, obojí by prošlo výčtem výš jen
    /// s jeho přepsáním — tohle je pojistka na to, že se výčet nepřepíše „aby test prošel“.
    @Test("Panel je ve třech tabech, ne ve všech a ne v žádném")
    func panelIsPartial() {
        let count = PullRequestTab.allCases.count(where: \.showsReviewPanel)

        #expect(count == 3)
        #expect(count < PullRequestTab.allCases.count)
        #expect(count > 0)
    }

    @Test("Nálezy a Průběh jsou výstup reviewerů, zbytek ne")
    func classification() {
        #expect(PullRequestTab.findings.isReviewerOutput)
        #expect(PullRequestTab.progress.isReviewerOutput)
        #expect(!PullRequestTab.overview.isReviewerOutput)
        #expect(!PullRequestTab.filesChanged.isReviewerOutput)
        #expect(!PullRequestTab.conversation.isReviewerOutput)
        // Kontroly jsou fakt o PR, ne výstup reviewerů — proto nalevo od děliče.
        #expect(!PullRequestTab.checks.isReviewerOutput)
    }
}
