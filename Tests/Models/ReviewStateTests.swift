import Foundation
import Testing

@testable import PRism

@Suite("ReviewState")
struct ReviewStateTests {
    @Test(
        "Každý stav přežije round-trip přes Codable",
        arguments: [
            ReviewState.notStarted,
            .queued,
            .cloning,
            .checkoutFailed(detail: "fatal: repository not found"),
            .running(finished: 1, total: 3),
            .clean,
            .completed(findings: 9),
            .failed(detail: "exit 1"),
            .timedOut(findings: 2),
            .stale,
        ]
    )
    func survivesCodableRoundTrip(state: ReviewState) throws {
        #expect(try roundTrip(state) == state)
    }

    @Test("Doběhlé review bez nálezů je čisté")
    func finishedWithoutFindingsIsClean() {
        #expect(ReviewState.finished(findingCount: 0) == .clean)
    }

    @Test("Doběhlé review s nálezy nese jejich počet")
    func finishedWithFindingsCarriesCount() {
        #expect(ReviewState.finished(findingCount: 9) == .completed(findings: 9))
    }

    @Test("Čisté není totéž co selhané")
    func cleanIsNotFailed() {
        #expect(ReviewState.finished(findingCount: 0) != .failed(detail: ""))
    }

    @Test("Selhání checkoutu se neplete se selháním session")
    func checkoutFailureIsDistinctFromSessionFailure() {
        #expect(ReviewState.checkoutFailed(detail: "boom") != .failed(detail: "boom"))
    }
}
