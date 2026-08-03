import Foundation

/// Stav konverzace jednoho PR. Co v mapě store není, se ještě nenačítalo.
///
/// Stejný tvar jako `DiffState` a ze stejného důvodu: razítko `updatedAt` se drží **u dat**,
/// ne vedle nich. Dvě mapy s různými klíči si dokázaly odporovat už u checkoutu.
enum ConversationState: Equatable, Sendable {
    case loading
    case loaded(Conversation, updatedAt: Date)
    case failed(String)
}
