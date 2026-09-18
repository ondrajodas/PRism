import Foundation

@testable import PRism

/// Fake osmé session (#521) — obyčejná třída, která si pamatuje, co po ní kdo chtěl.
/// **Protokol + fake, ne mockovací framework.**
///
/// Na tom, co si pamatuje, stojí nejcennější tvrzení #521: **kolikrát se pustila** (nula
/// s vypnutou branou #520, nula podruhé nad týmž razítkem) a **co dostala ve vstupu** — tedy že
/// v něm není nic o disku.
final class FakeReviewBodyWriter: ReviewBodyWriting, @unchecked Sendable {
    /// Co vrátit. Když je odpovědí míň než běhů, platí ta poslední.
    var answers: [ReviewBodyAnswer]
    /// Co vyhodit místo odpovědi. `nil` = odpoví.
    var failure: (any Error)?

    private let lock = NSLock()
    private var received: [ReviewBodyRequest] = []

    init(
        answers: [ReviewBodyAnswer] = [
            ReviewBodyAnswer(
                text: "Díky, tři věci jsou k opravě a dvě si rozmyslím.",
                usage: RunUsage(cost: 0.11),
                failure: nil
            )
        ]
    ) {
        self.answers = answers
    }

    var requests: [ReviewBodyRequest] { lock.withLock { received } }

    var runs: Int { requests.count }

    func write(_ request: ReviewBodyRequest) async throws -> ReviewBodyAnswer {
        let index = lock.withLock {
            received.append(request)
            return received.count - 1
        }
        if let failure { throw failure }
        guard !answers.isEmpty else {
            return ReviewBodyAnswer(text: nil, usage: nil, failure: "prázdno")
        }
        return answers[min(index, answers.count - 1)]
    }
}
