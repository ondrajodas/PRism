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
    var tint: Color {
        switch self {
        case .approve: .green
        case .requestChanges: .red
        case .comment: .accentColor
        }
    }
}
