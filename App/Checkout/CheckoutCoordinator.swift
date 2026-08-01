import Foundation

/// Hlídá, že nad jedním klíčem neběží dvě přípravy naráz.
///
/// Dvě review nad různými PR téhož repa se spustí současně a obě sáhnou na tentýž klon:
/// druhé volání by mohlo smazat složku toho, které se právě klonuje. Souběžný požadavek
/// se proto k běžící práci **připojí** místo aby začal vlastní — což je zároveň to, co
/// volající chce: výsledek je stejný.
actor CheckoutCoordinator {
    /// Ke klíči se připojila práce s jiným návratovým typem. Znamená to chybu v kódu,
    /// ne stav, do kterého se dá dostat používáním.
    struct MismatchedWork: Error {
        let key: String
        let expected: String
        let got: String
    }

    private var running: [String: Task<any Sendable, any Error>] = [:]
    /// Čekatelé podle identity, ne počtu. Kdyby se počítali, zrušený čekající by z počtu
    /// odešel až po návratu z `task.value` — jenže ten se nevrátí, dokud práce běží. Dva
    /// zrušení čekatelé by se tak navzájem viděli jako „ještě někdo čeká“ a práci by
    /// nezrušil ani jeden.
    private var waiters: [String: Set<UUID>] = [:]

    /// Slučuje se podle `key` **i** `kind`.
    ///
    /// Nad jednou cestou existují dvě různé operace — založit strom a uklidit ho — a
    /// slučovat se smějí jen stejné. Kdyby se úklid připojil k rozdělanému zakládání,
    /// dostal by cizí výsledek (`as!` by spadlo) a hlavně by neuklidil. Různé druhy tedy
    /// běží samostatně; když si na disku vlezou do cesty, ohlásí to `git` jako chybu —
    /// což je normální stav, na rozdíl od pádu na přetypování.
    func run<T: Sendable>(
        key: String,
        kind: String,
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        // Návratový typ je v klíči taky: dvě práce, které vracejí něco jiného, se pak
        // nemají jak potkat, i kdyby někdo omylem použil stejný `kind`.
        let key = "\(kind):\(T.self):\(key)"
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
            // Práce mohla doběhnout dřív, než zrušení dorazilo. Vracet výsledek
            // zrušenému volajícímu by znamenalo, že pokračuje v něčem, co má skončit.
            try Task.checkCancellation()
            guard let typed = value as? T else {
                // Nemá jak nastat — klíč nese typ. Ohlásit se to ale musí líp než pádem.
                throw MismatchedWork(key: key, expected: "\(T.self)", got: "\(type(of: value))")
            }
            return typed
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

    /// Odchod čekajícího, který se dočkal výsledku.
    ///
    /// Zrušení se tu ztratit nemůže, i když `onCancel` odbíhá do vlastního tasku:
    /// `leave` se spustí teprve po návratu z `task.value`, tedy až práce doběhla — a
    /// doběhlou práci není co rušit. `waiterLeft`, který dorazí po něm, najde prázdno
    /// a neudělá nic.
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
