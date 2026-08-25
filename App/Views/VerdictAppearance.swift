import SwiftUI

/// Jak verdikt vypadá. Jedno místo pro obě obrazovky, které ho kreslí — výběr v panelu
/// (`DraftPanel`) a potvrzení odeslání (`ReviewSubmissionSheet`).
///
/// Tatáž úvaha jako u `czechLabel` na modelu: dvě sady barev a ikon pro tutéž hodnotu se
/// rozejdou, a rozejít se v tomhle znamená, že `Schválit` vypadá v jednom okně jinak než
/// v druhém. Není to na modelu, protože `Color` je SwiftUI a doménové typy ho neznají.
extension ReviewDraft.Verdict {
    var symbolName: String {
        switch self {
        case .approve: "checkmark.seal"
        case .requestChanges: "exclamationmark.triangle"
        case .comment: "text.bubble"
        }
    }

    /// `Vyžádat změny` je **červené**, ne oranžové.
    ///
    /// Červená se v tomhle okně drží pro blokující věci a GitHub barví „changes requested“
    /// stejně. Odhad aplikace se od rozhodnutí, které odejde na GitHub, odlišuje popiskem
    /// `návrh z nálezů` v panelu (#114) — do #218 na to byl v hlavičce vlastní oranžový odznak
    /// (`VerdictView`), který se s předvyplněným verdiktem překrýval.
    ///
    /// **`Komentář` bere akcent z palety** (#309), ne `Color.accentColor`. Verdikt je **volba**,
    /// tedy akce: tři tlačítka, ze kterých se jedno zmáčkne, takže mint (konstatování) by tu měl
    /// obrácený význam. Systémová modrá tu byla jediná barva, kterou si okno neurčuje samo —
    /// `.tint(Palette.accent)` z kořene na `Color.accentColor` nezabírá.
    ///
    /// **Zelená a červená jsou od #432 taky z palety** (`Palette.ok`, `Palette.crit`) — do té doby
    /// tady stálo, že zůstávají systémové, „protože převod celé sémantické škály je jiná otázka,
    /// kterou #218 a #277 zodpověděly měřením jen pro kapsli stavu a pro diff“. #432 tu otázku
    /// zodpovědělo pro zbytek `App/` a odpověď je stejná: systémová škála je výplň tlačítka
    /// s bílým textem, takže jako barva textu vychází ve světlém režimu pod 3. Zdůvodnění
    /// s čísly je v `ReviewStateAppearance`.
    var tint: Color {
        switch self {
        case .approve: Palette.ok
        case .requestChanges: Palette.crit
        case .comment: Palette.accent
        }
    }
}
