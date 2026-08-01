import Foundation

/// Hlídá, že nad jedním klíčem neběží dvě přípravy naráz.
///
/// Dvě review nad různými PR téhož repa se spustí současně a obě sáhnou na tentýž klon:
/// druhé volání by mohlo smazat složku toho, které se právě klonuje. Souběžný požadavek
/// se proto k běžící práci **připojí** místo aby začal vlastní — což je zároveň to, co
/// volající chce: výsledek je stejný.
actor CheckoutCoordinator {
    private var running: [String: Task<any Sendable, any Error>] = [:]
    /// Čekatelé podle identity, ne počtu. Kdyby se počítali, zrušený čekající by z počtu
    /// odešel až po návratu z `task.value` — jenže ten se nevrátí, dokud práce běží. Dva
    /// zrušení čekatelé by se tak navzájem viděli jako „ještě někdo čeká“ a práci by
    /// nezrušil ani jeden.
    private var waiters: [String: Set<UUID>] = [:]

    func run<T: Sendable>(
        key: String,
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let token = UUID()
        let task = join(key, work)
        waiters[key, default: []].insert(token)

        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { await self.waiterLeft(key, token) }
            }
            leave(key, token)
            // Typ drží dvojice klíč–práce: k jednomu klíči se připojují jen volání, která
            // dělají totéž. Kdyby to přestalo platit, spadne to tady a hned.
            return value as! T
        } catch {
            leave(key, token)
            throw error
        }
    }

    private func join(
        _ key: String,
        _ work: @escaping @Sendable () async throws -> some Sendable
    ) -> Task<any Sendable, any Error> {
        if let existing = running[key] { return existing }
        let task = Task { try await work() as any Sendable }
        running[key] = task
        return task
    }

    private func leave(_ key: String, _ token: UUID) {
        waiters[key]?.remove(token)
        guard waiters[key]?.isEmpty != false else { return }
        waiters[key] = nil
        running[key] = nil
    }

    /// Zrušení **posledního** čekajícího zruší i samotnou práci.
    ///
    /// Bez toho by `git` běžel dál až do timeoutu, i když už výsledek nikdo nechce —
    /// a `withTaskCancellationHandler` v `SubprocessRunner`u, který má proces zabít, by
    /// se nikdy nespustil. Dokud čeká někdo další, práce pokračuje: rozdělaný klon je
    /// horší než klon navíc.
    private func waiterLeft(_ key: String, _ token: UUID) {
        waiters[key]?.remove(token)
        guard waiters[key]?.isEmpty != false else { return }
        running[key]?.cancel()
    }
}
