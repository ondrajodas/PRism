import Foundation
import Testing

@testable import PRism

/// Kolik znaků se vejde na stranu diffu (#188).
///
/// Co se dá pokazit potichu: **zapomenout, že se vedle sebe dělí šířka na dvě strany**. Číslo by
/// pak tvrdilo, že se slib drží, zrovna v režimu, ve kterém se nedrží — a řádky by se lámaly bez
/// vysvětlení.
@Suite("Šířka diffu ve znacích")
struct DiffWidthTests {
    private func characters(_ width: Double, layout: DiffLayout, gutter: Double = 64) -> Int {
        Policy.charactersPerSide(
            contentWidth: width,
            characterWidth: 7.2,
            layout: layout,
            gutter: gutter
        )
    }

    @Test("Pod sebou se počítá celá šířka bez okraje s čísly")
    func measuresTheWholeWidthWhenUnified() {
        // (1000 − 64) / 7,2 = 130
        #expect(characters(1000, layout: .unified) == 130)
    }

    /// **Nejcennější test téhle sady.** Vedle sebe má každá strana vlastní sloupec s čísly, takže
    /// se neodečítá jednou, ale z každé poloviny.
    @Test("Vedle sebe se šířka dělí na dvě strany")
    func halvesTheWidthWhenSplit() {
        // (1000 / 2 − 64) / 7,2 = 60
        #expect(characters(1000, layout: .split) == 60)
    }

    @Test("Užší okno než okraj s čísly nedá záporný počet")
    func clampsToZero() {
        #expect(characters(40, layout: .unified) == 0)
    }

    /// Než se okno změří, je šířka nula — a nula znaků je pravda o tom, co se změřilo, ne tvrzení
    /// o okně. Rozhodnutí „ukázat, nebo ne“ patří tomu, kdo ví, jestli už měření proběhlo.
    @Test("Nezměřené okno dá nulu")
    func handlesAnUnmeasuredWindow() {
        #expect(characters(0, layout: .unified) == 0)
    }

    /// Bez znalosti šířky znaku by dělení spadlo — a písmo bez šířky znamená, že se ještě
    /// nekreslilo.
    @Test("Nulová šířka znaku nespadne")
    func handlesAZeroCharacterWidth() {
        #expect(
            Policy.charactersPerSide(contentWidth: 1000, characterWidth: 0, layout: .unified) == 0
        )
    }

    /// Slib je z `CLAUDE.md`, ne odhad — a je to tatáž hodnota, se kterou lišta porovnává.
    @Test("Slibuje se 120 znaků")
    func promisesOneHundredAndTwenty() {
        #expect(Policy.promisedCharactersPerSide == 120)
    }
}
