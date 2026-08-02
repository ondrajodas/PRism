import Foundation

/// Kolik review smí běžet naráz.
///
/// Session je drahá na stroj i na účet, takže dávka deseti PR nesmí spustit deset `claude`
/// procesů. Běhy nad limit čekají ve frontě v pořadí, ve kterém přišly — kdo si řekl dřív,
/// jde dřív; jinak by se u větší dávky nedalo poznat, jestli se na řádek vůbec dostane.
actor ReviewSlots {
    /// Limit se čte **při každém pokusu o slot**, ne jednou při vzniku — jinak by se
    /// změna konfigurace projevila až po restartu.
    private let limit: @Sendable () -> Int
    private var taken = 0
    private var waiting: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []
    /// Zrušení, která dorazila dřív, než se čekatel stihl zapsat.
    ///
    /// `onCancel` odbíhá do vlastního tasku, takže může předběhnout zápis do fronty. Bez
    /// tohohle záznamu by se zrušený čekatel zapsal až po něm a čekal na slot navždy.
    private var cancelledBeforeWaiting: Set<UUID> = []
    /// Volání `acquire`, která právě probíhají.
    ///
    /// Rozhoduje, jestli má smysl si zrušení pamatovat: `onCancel` může dorazit i poté, co
    /// čekatel slot dostal a z fronty odešel. Bez téhle podmínky by se takové zrušení
    /// uložilo do `cancelledBeforeWaiting`, kde už ho nikdo nikdy nepřečte — a set by
    /// v dlouho běžící aplikaci rostl bez omezení.
    private var pendingAcquires: Set<UUID> = []

    init(limit: @escaping @Sendable () -> Int) {
        self.limit = limit
    }

    init(limit: Int) {
        self.init(limit: { limit })
    }

    /// Nula z konfigurace by znamenala, že se nespustí nic a nikdo nepozná proč. Překlep
    /// v souboru nemá aplikaci umlčet.
    private var currentLimit: Int { max(1, limit()) }

    /// Spustí práci, jakmile je volný slot, a slot po ní vrátí — i když skončila chybou.
    ///
    /// `nonisolated` schválně: kdyby práce běžela na aktoru, serializoval by ji tenhle typ
    /// úplně a limit by byl vždycky jedna.
    nonisolated func withSlot<T: Sendable>(_ work: () async throws -> T) async throws -> T {
        try await acquire()
        do {
            let value = try await work()
            await release()
            return value
        } catch {
            await release()
            throw error
        }
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        guard taken >= currentLimit else {
            taken += 1
            return
        }

        let id = UUID()
        pendingAcquires.insert(id)
        // Doběhne na aktoru bez suspendování, takže se `abandon` nemá kam vklínit.
        defer {
            pendingAcquires.remove(id)
            cancelledBeforeWaiting.remove(id)
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if cancelledBeforeWaiting.remove(id) != nil {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiting.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.abandon(id) }
        }
    }

    /// Slot se **předává** dalšímu ve frontě, ne vrací a znovu bere. Mezikrok, ve kterém je
    /// volný, by pustil dovnitř běh, který si o slot řekl později.
    private func release() {
        guard !waiting.isEmpty else {
            taken -= 1
            return
        }
        waiting.removeFirst().continuation.resume()
    }

    private func abandon(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else {
            // Zrušení, které dorazilo po tom, co čekatel z fronty odešel, si pamatovat
            // nemá kdo přečíst.
            if pendingAcquires.contains(id) { cancelledBeforeWaiting.insert(id) }
            return
        }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
