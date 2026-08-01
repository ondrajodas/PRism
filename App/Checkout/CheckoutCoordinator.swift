import Foundation

/// Hlídá, že nad jedním klíčem neběží dvě přípravy naráz.
///
/// Dvě review nad různými PR téhož repa se spustí současně a obě sáhnou na tentýž klon:
/// druhé volání by mohlo smazat složku toho, které se právě klonuje. Souběžný požadavek
/// se proto k běžící práci **připojí** místo aby začal vlastní — což je zároveň to, co
/// volající chce: výsledek je stejný.
actor CheckoutCoordinator {
    private var running: [String: Task<any Sendable, any Error>] = [:]
    private var waiters: [String: Int] = [:]

    func run<T: Sendable>(
        key: String,
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let task = join(key, work)
        waiters[key, default: 0] += 1

        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { await self.waiterLeft(key) }
            }
            leave(key)
            // Typ drží dvojice klíč–práce: k jednomu klíči se připojují jen volání, která
            // dělají totéž. Kdyby to přestalo platit, spadne to tady a hned.
            return value as! T
        } catch {
            leave(key)
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

    private func leave(_ key: String) {
        let remaining = (waiters[key] ?? 1) - 1
        guard remaining > 0 else {
            waiters[key] = nil
            running[key] = nil
            return
        }
        waiters[key] = remaining
    }

    /// Zrušení **posledního** čekajícího zruší i samotnou práci.
    ///
    /// Bez toho by `git` běžel dál až do timeoutu, i když už výsledek nikdo nechce —
    /// a `withTaskCancellationHandler` v `SubprocessRunner`u, který má proces zabít, by
    /// se nikdy nespustil. Dokud čeká někdo další, práce pokračuje: rozdělaný klon je
    /// horší než klon navíc.
    private func waiterLeft(_ key: String) {
        guard let count = waiters[key], count <= 1 else { return }
        running[key]?.cancel()
    }
}
