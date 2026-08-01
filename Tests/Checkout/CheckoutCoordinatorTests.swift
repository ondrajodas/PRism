import Foundation
import Testing

@testable import PRism

@Suite("CheckoutCoordinator")
struct CheckoutCoordinatorTests {
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
            while started == 0 { await Task.yield() }
        }

        func finish() { release?.resume(); release = nil }
    }

    @Test("Souběžná volání nad stejným klíčem se spojí do jedné práce")
    func concurrentCallsShareOneRun() async throws {
        // Dvě review nad různými PR téhož repa spustí přípravu naráz. Bez tohohle by
        // druhé volání smazalo složku rozběhnutého klonu prvního.
        let coordinator = CheckoutCoordinator()
        let work = SlowWork()

        async let first = coordinator.run(key: "keboola/vault") { await work.run() }
        await work.waitUntilStarted()
        async let second = coordinator.run(key: "keboola/vault") { await work.run() }
        await Task.yield()
        await work.finish()

        let results = try await [first, second]
        #expect(results.allSatisfy { $0 == URL(filePath: "/tmp/hotovo") })
        #expect(await work.runs == 1)
    }

    @Test("Různé klíče se neblokují")
    func differentKeysRunIndependently() async throws {
        let coordinator = CheckoutCoordinator()

        async let first = coordinator.run(key: "a") { URL(filePath: "/a") }
        async let second = coordinator.run(key: "b") { URL(filePath: "/b") }

        #expect(try await [first, second] == [URL(filePath: "/a"), URL(filePath: "/b")])
    }

    @Test("Po doběhnutí se klíč uvolní pro další práci")
    func keyIsFreedAfterCompletion() async throws {
        // Jinak by se druhá příprava téhož repa navěky vracela k prvnímu výsledku
        // a nikdy by nic nedotáhla.
        let coordinator = CheckoutCoordinator()

        _ = try await coordinator.run(key: "a") { URL(filePath: "/první") }
        let second = try await coordinator.run(key: "a") { URL(filePath: "/druhý") }

        #expect(second == URL(filePath: "/druhý"))
    }

    @Test("Chyba se předá všem, kdo na práci čekali")
    func failurePropagatesToEveryCaller() async {
        let coordinator = CheckoutCoordinator()

        await #expect(throws: CheckoutError.timedOut) {
            try await coordinator.run(key: "a") { throw CheckoutError.timedOut }
        }
    }
}
