import Foundation
import Testing

@testable import PRism

/// Záložky PR (#242): jak se jmenují a kde je mezi nimi dělič.
@Suite("Záložky PR")
struct PullRequestTabTests {
    /// `Kontroly` (#215) sedí **mezi `Konverzací` a `Nálezy`**, tedy nalevo od děliče: je to
    /// něco, co je na PR, ne výstup našich reviewerů. `Commity` (#316) přišly ještě dál doleva —
    /// vedle `Změněných souborů`, protože obojí odpovídá na „co se v kódu změnilo“, jen jednou
    /// naráz a jednou po krocích.
    @Test("Pruh má sedm záložek v pořadí, ve kterém se čtou")
    func order() {
        #expect(PullRequestTab.allCases.map(\.czechLabel)
            == ["Přehled", "Změněné soubory", "Commity", "Konverzace", "Kontroly", "Nálezy", "Průběh"])
    }

    @Test("Otevírá se Přehledem")
    func standard() {
        #expect(PullRequestTab.standard == .overview)
    }

    /// Dělič odděluje to, co je na PR (a co má i GitHub), od toho, co s ním udělaly naše reviewery.
    /// `Kontroly` (#215) přišly doprostřed levé skupiny a `Commity` (#316) taky — a **ani jedno ho
    /// nesmí posunout**, protože se počítá z vlastnosti tabu, ne z indexu.
    @Test("Výstup reviewerů je jedna souvislá skupina na konci")
    func reviewerOutputIsOneGroup() {
        let flags = PullRequestTab.allCases.map(\.isReviewerOutput)

        #expect(flags == [false, false, false, false, false, true, true])
        // Jeden přechod, tedy jeden dělič — ne dva a ne žádný.
        #expect(zip(flags, flags.dropFirst()).count { $0 != $1 } == 1)
    }

    /// **Tvrdí, že se něco NEstalo** (#316): sedmá záložka vložená doprostřed dělič neposunula.
    /// Kdyby se `needsSeparator` počítalo z indexu — jak by to od #306 při konstantním pruhu šlo —,
    /// stál by dělič po vložení `Commitů` o jedno místo vlevo, tedy před `Kontrolami`.
    @Test("Dělič stojí před Nálezy, ne na indexu, kde stával")
    func separatorSitsBeforeTheFindingsTab() {
        let tabs = PullRequestTab.allCases
        let boundaries = tabs.indices.dropFirst().filter {
            tabs[$0].isReviewerOutput && !tabs[$0 - 1].isReviewerOutput
        }

        #expect(boundaries.count == 1)
        #expect(boundaries.first.map { tabs[$0] } == .findings)
        // Index, na kterém dělič stál do #316. Kdyby byl zadrátovaný, seděl by teď před `Kontrolami`.
        #expect(tabs[4] == .checks)
    }

    /// **Počet záložek není funkcí dat** (#306, platí i pro #316). `PullRequestTabBar` kreslí
    /// `allCases` a nemá parametr, kterým by se dal pruh zúžit — do #306 ho měl a pruh se tím při
    /// **každém** otevření PR přeskládal z pěti záložek na šest. Test hlídá druhou polovinu toho
    /// tvrzení: že se výčet, ze kterého pruh kreslí, nezmenšil. Sám o sobě by prošel i po smazání
    /// jednoho prvku z testu pořadí výš, proto počet i jmenovitě obě záložky, které přišly
    /// doprostřed.
    @Test("Kontroly i Commity jsou ve výčtu, ze kterého pruh kreslí, vždycky")
    func stripAlwaysHasTheDataDrivenTabs() {
        #expect(PullRequestTab.allCases.count == 7)
        #expect(PullRequestTab.allCases.contains(.checks))
        #expect(PullRequestTab.allCases.contains(.commits))
    }

    // MARK: - Panel s mým review (#294)

    /// Vyčerpávající výčet, ne tři reprezentanti: je to sedm případů a jediné, co tuhle vlastnost
    /// drží, je právě ten výčet — přidaný osmý tab by jinak mlčky dostal panel podle toho, kam ho
    /// někdo napsal.
    ///
    /// **`Commity` přibyly u #392** a pořadí ve výčtu je pořadí z `allCases`, tedy třetí.
    @Test("Panel je v Přehledu, Změněných souborech, Commitech a Konverzaci")
    func panelTabs() {
        let withPanel = PullRequestTab.allCases.filter(\.showsReviewPanel)

        #expect(withPanel == [.overview, .filesChanged, .commits, .conversation])
        #expect(PullRequestTab.commits.showsReviewPanel)
        #expect(!PullRequestTab.checks.showsReviewPanel)
        #expect(!PullRequestTab.findings.showsReviewPanel)
        #expect(!PullRequestTab.progress.showsReviewPanel)
    }

    /// **Tohle je ten test, který tvrdí, že se něco NEstalo**: že se `showsReviewPanel` neohnul na
    /// `isReviewerOutput`. Od #392 to drží **`Kontroly` samotné**: jsou fakt o PR, takže stojí **nalevo od
    /// děliče** (`isReviewerOutput == false`), a panel přesto mít nemají — vedle detailu spadlého
    /// checku se čte konec logu, který šířku potřebuje. Kdyby se ty dvě vlastnosti sloučily, dělič
    /// v pruhu záložek by se posunul a `Kontroly` by skočily do pravé skupiny.
    ///
    /// **Přepsáno u #392, ne doplněno.** Do té doby tu byly ve výčtu i `Commity` s odůvodněním,
    /// že nálezy jsou klíčované `headSha`, takže by panel u staršího commitu ukazoval nálezy
    /// k jinému kódu. Panel v `Commitech` od #392 **je** (rozhodly o tom labely a reviewery, které
    /// platí pro celý PR), a ta podmínka se neobešla — stala se z ní věta v UI
    /// (`Policy.findingsHeadNotice`). Z původního odůvodnění proto nesmí zbýt nic: `Commity`
    /// jsou dneska tab **s** panelem.
    @Test("Panel se neřídí příznakem výstupu reviewerů")
    func panelIsNotReviewerOutput() {
        #expect(PullRequestTab.checks.isReviewerOutput == false)
        #expect(PullRequestTab.checks.showsReviewPanel == false)

        let sameEverywhere = PullRequestTab.allCases.allSatisfy { $0.showsReviewPanel == !$0.isReviewerOutput }
        #expect(!sameEverywhere, "vlastnosti splynuly — jedna z nich pak mluví o něčem jiném, než co dělá")
    }

    /// Čtyři ze sedmi (do #392 tři): kdyby panel zmizel odevšad nebo zůstal všude, obojí by prošlo
    /// výčtem výš jen s jeho přepsáním — tohle je pojistka na to, že se výčet nepřepíše „aby test
    /// prošel“.
    @Test("Panel je ve čtyřech tabech, ne ve všech a ne v žádném")
    func panelIsPartial() {
        let count = PullRequestTab.allCases.count(where: \.showsReviewPanel)

        #expect(count == 4)
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
        // Kontroly a Commity jsou fakt o PR, ne výstup reviewerů — proto nalevo od děliče.
        #expect(!PullRequestTab.checks.isReviewerOutput)
        #expect(!PullRequestTab.commits.isReviewerOutput)
    }
}
