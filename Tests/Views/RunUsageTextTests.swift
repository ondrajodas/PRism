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

    // MARK: - Stopky běžícího review (#218)

    /// Na rozdíl od `duration(_:)` **nemění jednotku**: pruh v hlavičce se překresluje po
    /// sekundě, a kdyby se v něm `59,8 s` přehodilo na `1 m 0 s`, přeskládá se pod okem.
    @Test("Stopky drží tvar m:ss i pod minutou")
    func stopwatchKeepsItsShape() {
        #expect(RunUsageText.elapsed(.seconds(0)) == "0:00")
        #expect(RunUsageText.elapsed(.seconds(9)) == "0:09")
        #expect(RunUsageText.elapsed(.seconds(72)) == "1:12")
        #expect(RunUsageText.elapsed(.seconds(599)) == "9:59")
    }

    @Test("Nad hodinu přibude hodinové pole")
    func stopwatchAddsHours() {
        #expect(RunUsageText.elapsed(.seconds(3600)) == "1:00:00")
        #expect(RunUsageText.elapsed(.seconds(3727)) == "1:02:07")
    }

    /// Posunuté systémové hodiny umí dát začátek v budoucnosti. `-0:03` by vypadalo jako
    /// chyba aplikace, přitom je to chyba hodin.
    @Test("Záporný čas je nula, ne mínus")
    func stopwatchNeverGoesNegative() {
        #expect(RunUsageText.elapsed(.seconds(-5)) == "0:00")
    }
}
