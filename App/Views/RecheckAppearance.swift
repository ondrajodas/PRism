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
