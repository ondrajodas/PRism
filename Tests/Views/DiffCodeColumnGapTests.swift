import AppKit
import Testing
@testable import PRism

/// **Kolona kódu se neopírá o to, co stojí vpravo** (#503).
///
/// Sesterské tvrzení k `DiffColumnFitTests`, které mluví o **součtu** šířek.
///
/// **Tvrzení o hranách tu není, a je to zapsaná mezera, ne opomenutí.** Zkusil jsem ho a zahodil:
/// porovnání `zbývá vpravo` proti `okraj + proužek + mezera` vyšlo **zeleně i s mezerou nula**,
/// protože scéna, kterou sonda staví, není ten pohled, který jsem jí předal — vyšla `Pod sebou`
/// s rozloženým stromem, kde `zbývá` sedne na mez na bod. Zelený test nad měřidlem, které měří
/// jinou scénu, netvrdí nic (#478), takže tady zůstává jen to, co se ověřit dá, a hrany si
/// vezme až test, který si scénu postaví sám a doloží, že v ní doopravdy je.
@Suite("Mezera mezi kódem a pravou kolonou (#503)")
struct DiffCodeColumnGapTests {
    /// **Mezera je necelý znak, a to je podmínka**, ne estetika: kdyby byla širší než šířka znaku,
    /// ubrala by koloně celý sloupec textu — zrovna to, čemu se `charactersPerSide` snaží
    /// zabránit. Kdyby byla nulová, vrátí se stav z živého okna, kde se text lámal naplocho
    /// na dělící čáru.
    ///
    /// **Ověřeno vloženou regresí**: s `codeColumnTrailingGap = 0` tohle tvrzení spadne.
    @Test("Mezera je menší než jeden znak kódu a není nulová")
    func gapCostsNoColumnOfText() {
        let characterWidth = FontMetric.shared.characterWidth(
            of: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        )
        #expect(Policy.codeColumnTrailingGap > 0)
        #expect(Policy.codeColumnTrailingGap < characterWidth)
    }
}
