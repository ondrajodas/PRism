import Foundation

/// Stav dotažení labelů a reviewerů jednoho PR (#392).
///
/// Stejný tvar jako `DetailState` a `ConversationState`, ze stejného důvodu: razítko `updatedAt`
/// se drží **u dat**, ne vedle nich.
///
/// Existuje kvůli jedné věci, a je to ta, kterou Copilot v tomhle repu nachází opakovaně:
/// **„labely tu nejsou“ se nesmí splést s „labely jsem nezjistil“.** Sekce, která nemá co ukázat,
/// se nekreslí — kdyby se stejně nekreslila po chybě sítě, vypadal by výpadek jako pull request
/// bez štítků, a na vlastním PR by se navíc dalo kliknout na `+ label` a přepsat tím sadu, kterou
/// aplikace nezná.
enum MetadataState: Equatable, Sendable {
    case loading
    case loaded(PullRequestMetadata, updatedAt: Date)
    case failed(String)

    /// Načtená data, nebo `nil`. Volající, kterého nezajímá, proč nejsou.
    var metadata: PullRequestMetadata? {
        if case .loaded(let metadata, _) = self { metadata } else { nil }
    }

    var failure: String? {
        if case .failed(let reason) = self { reason } else { nil }
    }
}
