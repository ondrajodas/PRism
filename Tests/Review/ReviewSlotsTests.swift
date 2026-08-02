import Foundation
import Synchronization
import Testing

@testable import PRism

/// Limit, který se dá měnit za běhu — konfigurace se načítá znovu bez restartu.
private final class Limit: Sendable {
    private let storage: Mutex<Int>

    init(_ value: Int) { storage = Mutex(value) }

    var value: @Sendable () -> Int { { self.storage.withLock { $0 } } }

    func set(_ value: Int) { storage.withLock { $0 = value } }
}

@Suite("ReviewSlots")
struct ReviewSlotsTests {
    @Test("Naráz projde jen tolik práce, kolik je slotů")
    func concurrencyStaysUnderTheLimit() async throws {
        let slots = ReviewSlots(limit: 2)
        let work = HoldingWork()

        let running = (0..<4).map { index in
            Task { try await slots.withSlot { await work.run(index) } }
        }
        await work.waitForStarts(2)
        // Při rozbitém limitu by se rozjely všechny; pár otočení plánovače jim na to dá
        // příležitost.
        for _ in 0..<100 { await Task.yield() }
        #expect(work.startedCount == 2)

        work.releaseAll()
        for task in running { try await task.value }

        #expect(work.peak == 2)
        #expect(work.startedCount == 4)
    }

    @Test("Fronta pouští v pořadí, ve kterém se čekatelé přihlásili")
    func theLineIsFirstComeFirstServed() async throws {
        // Bez pořadí by se u větší dávky nedalo poznat, jestli se na řádek vůbec dostane.
        let slots = ReviewSlots(limit: 1)
        let work = HoldingWork()

        let first = Task { try await slots.withSlot { await work.run(0) } }
        await work.waitForStarts(1)
        let second = Task { try await slots.withSlot { await work.run(1) } }
        for _ in 0..<100 { await Task.yield() }
        let third = Task { try await slots.withSlot { await work.run(2) } }
        for _ in 0..<100 { await Task.yield() }

        work.releaseAll()
        try await first.value
        try await second.value
        try await third.value

        #expect(work.order == [0, 1, 2])
    }

    /// Limit se čte při každém pokusu o slot, ale to samo nestačí: čekatelé spí a nikdo
    /// je nevzbudí. Bez toho by zvýšení limitu za běhu vypadalo, že se neprojevilo.
    @Test("Zvýšení limitu pustí čekatele dál")
    func lettingTheLimitGrowAdmitsWaiters() async throws {
        let limit = Limit(1)
        let slots = ReviewSlots(limit: limit.value)
        let work = HoldingWork()

        let running = (0..<3).map { index in
            Task { try await slots.withSlot { await work.run(index) } }
        }
        await work.waitForStarts(1)

        limit.set(3)
        await slots.admitWaiting()
        await work.waitForStarts(3)

        work.releaseAll()
        for task in running { try await task.value }
        #expect(work.peak == 3)
    }

    /// A obráceně: po snížení limitu se běhy nad nový strop musí **vyčerpat**. Předání
    /// slotu dalšímu ve frontě bez ohledu na limit by souběh držel na starém čísle tak
    /// dlouho, dokud je fronta neprázdná.
    @Test("Snížení limitu se propíše, jakmile běhy doběhnou")
    func lettingTheLimitShrinkDrainsToIt() async throws {
        let limit = Limit(3)
        let slots = ReviewSlots(limit: limit.value)
        let first = HoldingWork()

        let running = (0..<3).map { index in
            Task { try await slots.withSlot { await first.run(index) } }
        }
        await first.waitForStarts(3)

        limit.set(1)
        let queued = HoldingWork()
        let waiting = (0..<2).map { index in
            Task { try await slots.withSlot { await queued.run(index) } }
        }
        for _ in 0..<100 { await Task.yield() }

        first.releaseAll()
        for task in running { try await task.value }
        // Tři doběhlé běhy uvolnily tři sloty, ale strop je teď jeden.
        await queued.waitForStarts(1)
        for _ in 0..<100 { await Task.yield() }
        #expect(queued.startedCount == 1)

        queued.releaseAll()
        for task in waiting { try await task.value }
        #expect(queued.peak == 1)
    }

    @Test("Zrušený čekatel frontu neucpe")
    func aCancelledWaiterFreesTheLine() async throws {
        let slots = ReviewSlots(limit: 1)
        let work = HoldingWork()

        let holder = Task { try await slots.withSlot { await work.run(0) } }
        await work.waitForStarts(1)
        let waiting = Task { try await slots.withSlot { await work.run(1) } }
        for _ in 0..<100 { await Task.yield() }
        waiting.cancel()

        await #expect(throws: CancellationError.self) { try await waiting.value }

        work.releaseAll()
        try await holder.value
        try await slots.withSlot { await work.run(2) }

        // Zrušený čekatel se nespustil a slot po sobě nenechal zabraný.
        #expect(work.order == [0, 2])
    }
}

/// Práce, která se drží, dokud ji test nepustí, a počítá, kolik jí běželo naráz.
private final class HoldingWork: @unchecked Sendable {
    private let lock = NSLock()
    private var started: [Int] = []
    private var active = 0
    private var highWaterMark = 0
    private var released = false

    var order: [Int] { lock.withLock { started } }
    var startedCount: Int { lock.withLock { started.count } }
    var peak: Int { lock.withLock { highWaterMark } }

    func releaseAll() { lock.withLock { released = true } }

    /// Točení přes `Task.yield()` schválně: test, který se nedočká, uvízne — což je
    /// srozumitelnější selhání než čekání na hodiny, které v testech nejdou.
    func waitForStarts(_ count: Int) async {
        while startedCount < count { await Task.yield() }
    }

    func run(_ index: Int) async {
        lock.withLock {
            started.append(index)
            active += 1
            highWaterMark = max(highWaterMark, active)
        }
        while !isReleased { await Task.yield() }
        lock.withLock { active -= 1 }
    }

    private var isReleased: Bool { lock.withLock { released } }
}
