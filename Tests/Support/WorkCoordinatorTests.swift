import Foundation
import Testing

@testable import PRism

@Suite("WorkCoordinator")
struct WorkCoordinatorTests {
    /// Práce, která se dá pozdržet, aby se druhé volání stihlo přidat k prvnímu.
    private actor SlowWork {
        private var started = 0
        private var release: CheckedContinuation<Void, Never>?

        var runs: Int { started }

        func run() async -> URL {
            started += 1
            await withCheckedContinuation { release = $0 }
            return URL(filePath: "/tmp/hotovo")
        }

        func waitUntilStarted() async {
            await waitUntil("práce se rozběhne") { self.started > 0 }
        }

        func finish() { release?.resume(); release = nil }
    }

    @Test("Souběžná volání nad stejným klíčem se spojí do jedné práce")
    func concurrentCallsShareOneRun() async throws {
        // Dvě review nad různými PR téhož repa spustí přípravu naráz. Bez tohohle by
        // druhé volání smazalo složku rozběhnutého klonu prvního.
        let coordinator = WorkCoordinator()
        let work = SlowWork()

        async let first = coordinator.run(key: "keboola/vault", kind: "clone") { await work.run() }
        await work.waitUntilStarted()
        async let second = coordinator.run(key: "keboola/vault", kind: "clone") { await work.run() }
        await settle()
        await work.finish()

        let results = try await [first, second]
        #expect(results.allSatisfy { $0 == URL(filePath: "/tmp/hotovo") })
        #expect(await work.runs == 1)
    }

    @Test("Různé klíče se neblokují")
    func differentKeysRunIndependently() async throws {
        let coordinator = WorkCoordinator()

        async let first = coordinator.run(key: "a", kind: "clone") { URL(filePath: "/a") }
        async let second = coordinator.run(key: "b", kind: "clone") { URL(filePath: "/b") }

        #expect(try await [first, second] == [URL(filePath: "/a"), URL(filePath: "/b")])
    }

    @Test("Po doběhnutí se klíč uvolní pro další práci")
    func keyIsFreedAfterCompletion() async throws {
        // Jinak by se druhá příprava téhož repa navěky vracela k prvnímu výsledku
        // a nikdy by nic nedotáhla.
        let coordinator = WorkCoordinator()

        _ = try await coordinator.run(key: "a", kind: "clone") { URL(filePath: "/první") }
        let second = try await coordinator.run(key: "a", kind: "clone") { URL(filePath: "/druhý") }

        #expect(second == URL(filePath: "/druhý"))
    }

    /// Práce, která běží, dokud ji někdo nezruší — a poví, že si zrušení všimla.
    private actor CancellableWork {
        private var started = false
        private(set) var sawCancellation = false

        func run() async -> URL {
            started = true
            // Držení, ne čekání na jev: práce běží, dokud ji někdo nezruší.
            while !Task.isCancelled { await TestWait.pause() }
            sawCancellation = true
            return URL(filePath: "/zruseno")
        }

        func waitUntilStarted() async {
            await waitUntil("práce se rozběhne") { self.started }
        }
    }

    @Test("Zrušení posledního čekajícího zruší i sdílenou práci")
    func cancellingTheLastWaiterCancelsTheWork() async throws {
        // Bez toho by `git` běžel dál do timeoutu, i když už výsledek nikdo nechce —
        // a `withTaskCancellationHandler` v `SubprocessRunner`u by se nikdy nespustil.
        let coordinator = WorkCoordinator()
        let work = CancellableWork()

        let waiter = Task { try await coordinator.run(key: "a", kind: "clone") { await work.run() } }
        await work.waitUntilStarted()
        waiter.cancel()
        _ = try? await waiter.value

        #expect(await work.sawCancellation)
    }

    @Test("Dokud čeká někdo další, práce pokračuje")
    func workSurvivesWhileAnotherCallerWaits() async throws {
        // Rozdělaný klon je horší než klon navíc, takže odchod jednoho zájemce nestačí.
        let coordinator = WorkCoordinator()
        let work = CancellableWork()

        let first = Task { try await coordinator.run(key: "a", kind: "clone") { await work.run() } }
        await work.waitUntilStarted()
        let second = Task { try await coordinator.run(key: "a", kind: "clone") { await work.run() } }
        await settle()
        first.cancel()

        // Druhý čekající drží práci naživu, takže se nezruší ani po zrušení prvního.
        await settle()
        #expect(await work.sawCancellation == false)

        second.cancel()
        _ = try? await second.value
        #expect(await work.sawCancellation)
    }

    @Test("Jiný druh práce se k běžící nepřipojí")
    func differentKindDoesNotJoin() async throws {
        // Založení stromu a jeho úklid sdílejí cestu, ale vracejí jiný typ. Připojit se
        // k cizí práci by znamenalo dostat cizí výsledek — a hlavně by úklid neuklidil.
        let coordinator = WorkCoordinator()
        let work = SlowWork()
        let cleaned = Cleaned()

        async let creating: URL = coordinator.run(key: "strom", kind: "add") { await work.run() }
        await work.waitUntilStarted()
        try await coordinator.run(key: "strom", kind: "remove") { await cleaned.mark() }

        #expect(await cleaned.done)
        await work.finish()
        _ = try await creating
        #expect(await work.runs == 1)
    }

    private actor Cleaned {
        private(set) var done = false
        func mark() { done = true }
    }

    @Test("Chyba se předá všem, kdo na práci čekali")
    func failurePropagatesToEveryCaller() async {
        let coordinator = WorkCoordinator()

        await #expect(throws: CheckoutError.timedOut) {
            try await coordinator.run(key: "a", kind: "clone") { throw CheckoutError.timedOut }
        }
    }
}
