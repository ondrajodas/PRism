import SwiftUI

/// Jak se kreslí odznak kontroly nálezů (#150).
///
/// **Na jednom místě**, i když ho sázejí tři: bublina u kódu, karta v panelu a rozbalený řádek
/// tabulky. Dvě různé barvy pro totéž „vyřešeno“ by z jednoho stavu udělaly dva — je to tatáž
/// úvaha jako u `VerdictAppearance` a `ReviewStateAppearance`.
extension RecheckStatus.Verdict {
    /// `vyřešeno` zeleně, protože je to jediná dobrá zpráva. `pořád platí` **tlumeně, ne
    /// červeně** — závažnost už nese proužek a obrys bubliny, takže druhá červená vedle nich by
    /// z bubliny udělala výstrahu o výstraze.
    var tint: Color {
        switch self {
        case .resolved: Palette.ok
        case .stillApplies: Palette.ink2
        case .unclear: Palette.ink3
        }
    }
}

extension RecheckStatus {
    /// Nápověda k odznaku. Věta od kontroly se přidává za vysvětlení, protože ve sbalené značce
    /// je to jediné místo, kde se dá přečíst.
    var help: String {
        guard let note else { return verdict.explanation }
        return "\(verdict.explanation) \(note)"
    }
}

extension FindingSeverityBadge {
    /// Slovo do **odznaku závažnosti** u nálezu, který kontrola má za opravený (#150).
    ///
    /// Bez `kontrola:`, na rozdíl od odznaku kontroly — a je to daň za místo, ne opomenutí:
    /// sloupec závažnosti má 92 bodů a hlavička karty 300, takže se plný popisek zkrátí na
    /// `kontrola…`, tedy na nic. Odkud tvrzení je, proto v odznaku závažnosti nese **barva
    /// a nápověda** (`RecheckStatus.help`), a plný odznak `kontrola: vyřešeno` zůstává tam, kde
    /// pro něj místo je — na kartě pod textem a v obsahu bubliny.
    static let resolvedLabel = "vyřešeno"

    /// Tatáž zelená jako u odznaku kontroly, a **z něj**, ne druhou konstantou: dvě zelené pro
    /// jedno „vyřešeno“ by z jednoho stavu udělaly dva.
    static var resolvedTint: Color { RecheckStatus.Verdict.resolved.tint }
}
