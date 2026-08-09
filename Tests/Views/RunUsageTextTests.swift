import Foundation
import Testing

@testable import PRism

/// Útrata jako text (#148, sdílená od #181).
///
/// Testuje se **jen značka `≥`**, ne formát částky: ten závisí na locale a testovat ho znamená
/// testovat `FormatStyle`. Značka je naopak tvrzení o datech — bez ní vypadá neúplný součet jako
/// úplný, a od #181 ji čtou dvě místa (stavový řádek a karta v dashboardu).
@Suite("Útrata jako text")
struct RunUsageTextTests {
    @Test("Úplný součet je bez značky")
    func leavesACompleteSumAlone() {
        let text = RunUsageText.spent(DailySpend(cost: 1.5, runs: 3, unknown: 0))

        #expect(!text.hasPrefix("≥"))
        #expect(text == RunUsageText.cost(1.5))
    }

    /// Zabitá session peníze stála taky, jen její cenu nikdo nenahlásil — součet je proto
    /// **dolní odhad**.
    @Test("Běh bez ceny udělá ze součtu dolní odhad")
    func marksAnIncompleteSum() {
        let text = RunUsageText.spent(DailySpend(cost: 1.5, runs: 3, unknown: 1))

        #expect(text == "≥ " + RunUsageText.cost(1.5))
    }
}
