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
    /// Návrh verdiktu z nálezů (`VerdictView`) oranžový zůstává schválně: to je odhad
    /// aplikace, kdežto tohle je rozhodnutí, které odejde na GitHub. Červená se v tomhle
    /// okně drží pro blokující věci a GitHub barví „changes requested“ stejně.
    var tint: Color {
        switch self {
        case .approve: .green
        case .requestChanges: .red
        case .comment: .accentColor
        }
    }
}
