import Foundation
import Testing

@testable import PRism

/// Záložky PR (#242): jak se jmenují a kde je mezi nimi dělič.
@Suite("Záložky PR")
struct PullRequestTabTests {
    @Test("Pruh má pět záložek v pořadí, ve kterém se čtou")
    func order() {
        #expect(PullRequestTab.allCases.map(\.czechLabel)
            == ["Přehled", "Změněné soubory", "Konverzace", "Nálezy", "Průběh"])
    }

    @Test("Otevírá se Přehledem")
    func standard() {
        #expect(PullRequestTab.standard == .overview)
    }

    /// Dělič odděluje to, co je na PR (a co má i GitHub), od toho, co s ním udělaly naše reviewery.
    /// Když `Kontroly` (#215) přijdou doprostřed levé skupiny, nesmí se tím posunout.
    @Test("Výstup reviewerů je jedna souvislá skupina na konci")
    func reviewerOutputIsOneGroup() {
        let flags = PullRequestTab.allCases.map(\.isReviewerOutput)

        #expect(flags == [false, false, false, true, true])
        // Jeden přechod, tedy jeden dělič — ne dva a ne žádný.
        #expect(zip(flags, flags.dropFirst()).count { $0 != $1 } == 1)
    }

    @Test("Nálezy a Průběh jsou výstup reviewerů, zbytek ne")
    func classification() {
        #expect(PullRequestTab.findings.isReviewerOutput)
        #expect(PullRequestTab.progress.isReviewerOutput)
        #expect(!PullRequestTab.overview.isReviewerOutput)
        #expect(!PullRequestTab.filesChanged.isReviewerOutput)
        #expect(!PullRequestTab.conversation.isReviewerOutput)
    }
}
