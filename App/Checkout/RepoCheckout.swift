import Foundation

/// Vlastní pracovní kopie aplikace.
///
/// Za protokolem, aby šla v testech nahradit fake implementací — a aby bylo z jednoho
/// místa vidět, že aplikace pracuje jen ve své cache.
protocol RepoCheckout: Sendable {
    /// Zajistí, že v cache je bare klon repa s aktuálními refy, a vrátí cestu k němu.
    ///
    /// Idempotentní: první volání klonuje, každé další jen dotahuje.
    func prepare(_ repo: RepoID) async throws -> URL
}
