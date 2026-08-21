import AppKit
import SwiftUI

/// Kapsle stavu z návrhu (`.pill`) — **jedno místo pro její sazbu** (#348).
///
/// Návrh kreslí kapsli `mono 10,5 / 600, odsazení 7 a 2, poloměr 20` a nese jí **stavy a počty**:
/// `nálezy zastaraly`, `sloučení`, `hlava`, `+248`, `otevřený`. Mono v ní není ozdoba — je to
/// odlišení od `.lchip`, tedy od labelu, který je slovo z repozitáře a sází se v UI fontu
/// (zdůvodnění je v komentáři u `.lchip` v `docs/navrh.html`).
///
/// **Metrika žila v sedmi kopiích** a jedna z nich se rozešla: chip v hlavičce karty popisu byl
/// 11 bez mono, takže v okně vypadal jako jiný druh prvku, než čím je (#348, nalezená odchylka
/// zapsaná u #299). Šest kopií přitom bylo shodných do bodu — a právě to je důvod, proč metrika
/// dostala jméno: rozejít se může jedině to, co je zapsané víckrát.
///
/// Z těch čísel se **kreslí i měří**: `TextWidth.pill(_:)` bere řez a odsazení odsud, jako
/// `TextWidth.miniButton(_:emphasis:)` bere řez z `MiniButtonStyle`. Vlastní `systemFont`
/// v měření by znamenal, že se počítá jiná šířka, než jaká se nakreslí.
enum DesignPill {
    /// `font-size: 10.5px` z návrhu, jeden ku jednomu na body.
    static let fontSize: CGFloat = 10.5
    /// `padding: 2px 7px`.
    static let horizontalPadding: CGFloat = 7
    static let verticalPadding: CGFloat = 2

    /// Řez pro měření šířky — tentýž, jaký nasazuje `designPill(tint:background:)`.
    static var measuringFont: NSFont {
        .monospacedSystemFont(ofSize: fontSize, weight: .semibold)
    }
}

extension View {
    /// Kapsle stavu z návrhu: `tint` je barva textu, `background` plocha pod ním.
    ///
    /// Poloměr 20 z CSS je na kapsli vysoké 16 bodů **víc než polovina výšky**, takže `.capsule`
    /// je jeho přesný protějšek, ne zaokrouhlení.
    ///
    /// **`lineLimit` sem nepatří** — kapsle v hlavičce karty se nesmí zalomit (`otevře/ný` nejsou
    /// dva odznaky pod sebou), kdežto ta v podtitulku commitu to omezení nikdy neměla. Je to
    /// rozhodnutí volajícího o jeho místě v okně, ne vlastnost kapsle.
    func designPill(tint: Color, background: Color) -> some View {
        font(.system(size: DesignPill.fontSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, DesignPill.horizontalPadding)
            .padding(.vertical, DesignPill.verticalPadding)
            .background(background, in: .capsule)
    }
}
