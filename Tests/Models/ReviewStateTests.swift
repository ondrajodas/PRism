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
            // Chyběl ve výčtu od #113, i když se ukládá jako všechny ostatní — doplněno u #383,
            // kde se tenhle seznam kontroloval kvůli novému případu.
            .dismissed(findings: 4),
            .inconclusive(reason: .unreadCode),
            .inconclusive(reason: .noReport),
            .inconclusive(reason: .droppedFindings),
            .failed(detail: "exit 1"),
            .timedOut(findings: 2),
            .interrupted(findings: 3),
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

    /// Třetí stav (#383) se nesmí rovnat ani jednomu z těch dvou, mezi které patří — a **tři různé
    /// důvody jsou tři různé stavy**, jinak by odznak u dvou z nich tvrdil něco, co se nestalo.
    @Test("Neprůkazné není ani čisté, ani selhané")
    func inconclusiveIsNeitherCleanNorFailed() {
        let unread = ReviewState.inconclusive(reason: .unreadCode)

        #expect(unread != .clean)
        #expect(unread != .failed(detail: ""))
        #expect(unread != .inconclusive(reason: .noReport))
        #expect(unread != .inconclusive(reason: .droppedFindings))
    }
}
