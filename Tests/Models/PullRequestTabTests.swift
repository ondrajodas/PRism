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

    /// Platí to i po vypadnutí `Kontrol` u PR bez CI: dělič se počítá z kreslených záložek,
    /// takže z něj nesmí být ani dva, ani žádný.
    @Test("Bez Kontrol zbývá dělič pořád jeden")
    func reviewerOutputIsOneGroupWithoutChecks() {
        let flags = Policy.tabs(hasChecks: false).map(\.isReviewerOutput)

        #expect(flags == [false, false, false, true, true])
        #expect(zip(flags, flags.dropFirst()).count { $0 != $1 } == 1)
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
