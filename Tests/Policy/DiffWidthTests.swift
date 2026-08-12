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
    /// Gutter se předává **vždycky**: výchozí hodnota tu byla a byla vymyšlená, takže ukazatel
    /// tvrdil víc znaků, než se vejde (nález Copilota na #188). Tady je 64 jen kulaté číslo
    /// do výpočtu, skutečné bere lišta z `DiffLineView`.
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
            Policy.charactersPerSide(
                contentWidth: 1000,
                characterWidth: 0,
                layout: .unified,
                gutter: 64
            ) == 0
        )
    }

    /// Slib je z `CLAUDE.md`, ne odhad — a je to tatáž hodnota, se kterou lišta porovnává.
    @Test("Slibuje se 120 znaků")
    func promisesOneHundredAndTwenty() {
        #expect(Policy.promisedCharactersPerSide == 120)
    }

    // MARK: - Šířka sheetu s kódem (#292)

    /// Na téhle obrazovce (1512 bodů) má sheet **1 360 bodů** místo dřívějších 820 — a je to
    /// změřené: ubude tím třetina řádků sazby, protože sheet zalamuje.
    @Test("Na běžné obrazovce je sheet o třetinu širší než dřív")
    func widensTheSheetOnAnOrdinaryScreen() {
        #expect(Policy.codeSheetWidth(screenWidth: 1_512) == 1_360)
        #expect(Policy.codeSheetWidth(screenWidth: 1_512) > Policy.previousCodeSheetWidth)
    }

    /// **Nikdy užší než dřív.** Zúžení by byla regrese, ne kompromis.
    @Test("Sheet se nezúží pod dřívější šířku", arguments: [1_000.0, 972.0, 900.0] as [CGFloat])
    func neverNarrowerThanBefore(screen: CGFloat) {
        #expect(Policy.codeSheetWidth(screenWidth: screen) >= Policy.previousCodeSheetWidth)
    }

    /// Na malém displeji rozhoduje **obrazovka, ne konstanta z většího** — sheet, který se
    /// nevejde, je horší než užší sheet.
    @Test("Na malou obrazovku se sheet vejde")
    func fitsSmallScreens() {
        #expect(Policy.codeSheetWidth(screenWidth: 800) <= 800 - Policy.codeSheetEdge)
        #expect(Policy.codeSheetWidth(screenWidth: 600) <= 600 - Policy.codeSheetEdge)
        #expect(Policy.codeSheetWidth(screenWidth: 600) > 0)
    }

    /// Strop drží širokoúhlé monitory: nad ním už to pro log nic nepřidá (celá obrazovka proti
    /// 1 360 bodům přidala 4 %) a sheet kreslí i hunky kódu, kde je řádek ~120 znaků.
    @Test("Na širokoúhlém monitoru se sheet zastropuje")
    func capsOnUltrawideScreens() {
        #expect(Policy.codeSheetWidth(screenWidth: 3_440) == Policy.codeSheetWidthCap)
        #expect(Policy.codeSheetWidth(screenWidth: 5_120) == Policy.codeSheetWidthCap)
    }

    /// Bez známé obrazovky (náhledy, testy) se vrací dřívější šířka — **žádná nula**, jinak by
    /// sheet neměl co kreslit.
    @Test("Bez známé obrazovky zůstane dřívější šířka")
    func fallsBackWithoutAScreen() {
        #expect(Policy.codeSheetWidth(screenWidth: nil) == Policy.previousCodeSheetWidth)
        #expect(Policy.codeSheetWidth(screenWidth: 0) == Policy.previousCodeSheetWidth)
    }

    /// Šířka **roste s obrazovkou** až do stropu; kdyby někde klesla, byla by v tom aritmetická
    /// chyba, kterou jednotlivé případy výš minou.
    @Test("Šířka s obrazovkou neklesá")
    func widthIsMonotonic() {
        var previous: CGFloat = 0
        for screen in stride(from: 600.0, through: 3_400.0, by: 50.0) {
            let current = Policy.codeSheetWidth(screenWidth: screen)
            #expect(current >= previous, "u obrazovky \(screen) šířka klesla")
            #expect(current <= max(screen - Policy.codeSheetEdge, Policy.codeSheetWidthCap))
            previous = current
        }
    }
}
