import Foundation
import Testing

@testable import PRism

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
