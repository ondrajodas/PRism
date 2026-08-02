import Foundation

/// Stav diffu jednoho PR. Co v mapě store není, se ještě nenačítalo.
enum DiffState: Equatable, Sendable {
    case loading
    /// Načtený diff a `updatedAt`, ke kterému patří. Razítko se drží u dat, ne vedle nich:
    /// dvě mapy s různými klíči si dokázaly odporovat už u checkoutu.
    case loaded(Diff, updatedAt: Date)
    case failed(String)
}
