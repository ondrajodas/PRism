import AppKit

/// Šířka popisku ve skutečném písmu (#284).
///
/// **Existuje proto, že `ViewThatFits` na tohle nestačí.** `Text` je vodorovně pružný, takže se
/// ve zúžené řadě radši zkrátí, než by nahlásil, že se nevejde — a `ViewThatFits` pak vybere
/// nejširší variantu a nechá z popisku `Jen t…`. Změřeno u #284 na liště rozsahového diffu v tabu
/// 648 bodů s rozloženým panelem; `lineLimit(1)` ani `fixedSize` s tím nehnuly.
///
/// Popisky v okně jsou přitom **konstanty**, takže se jejich šířka dá změřit a o podobě řady
/// rozhodnout z jednoho čísla — tedy tak, jak to má #220: v zanořeném stromu se rozměr nenechává
/// vyjednávat, když se dá spočítat.
///
/// **Měří se skutečným písmem, ne odhadem znaků**: česká věta má jinou šířku než anglická
/// a `count × 7` by se rozešlo hned u prvního delšího popisku.
enum TextWidth {
    /// Šířka jednoho řádku, zaokrouhlená nahoru — půl bodu dolů znamená o znak víc, než se vejde.
    static func of(_ value: String, font: NSFont) -> CGFloat {
        NSAttributedString(string: value, attributes: [.font: font]).size().width.rounded(.up)
    }

    /// Šířka popisku malého tlačítka i s jeho odsazením a obtažením.
    ///
    /// **Řez se bere ze stylu** (`MiniButtonStyle.labelFont`), ne z vlastního `systemFont`: plné
    /// tlačítko se kreslí mediumem, takže měřit ho regularem znamená spočítat menší šířku, než
    /// jaká se nakreslí — a přesně to je chyba, kterou má měření chytat.
    static func miniButton(_ label: String, emphasis: MiniButtonStyle.Emphasis) -> CGFloat {
        of(label, font: MiniButtonStyle.labelFont(of: emphasis))
            + 2 * MiniButtonStyle.Metrics.insetHorizontal
    }
}
