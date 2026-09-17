import Foundation

@testable import PRism

/// Fake šesté session (#516) — obyčejná třída, která si pamatuje, co po ní kdo chtěl.
/// **Protokol + fake, ne mockovací framework.**
///
/// Na tom, co si pamatuje, stojí nejcennější tvrzení #516: **kolikrát se pustila** (nula
/// s vypnutou branou, nula při tiku v režimu `Na požádání`, nula nad nenačtenou frontou)
/// a **co dostala ve vstupu** — tedy že v něm není nic o kódu.
final class FakeBriefWriter: BriefWriting, @unchecked Sendable {
    /// Co vrátit. Když je odpovědí míň než běhů, platí ta poslední.
    var answers: [BriefAnswer]
    /// Co vyhodit místo odpovědi. `nil` = odpoví.
    var failure: (any Error)?

    private let lock = NSLock()
    private var received: [BriefRequest] = []

    init(
        answers: [BriefAnswer] = [
            BriefAnswer(
                text: "Přes den přišly dva PR do fronty. Sandbox #4 blokuje. Nic dalšího nehoří.",
                usage: RunUsage(cost: 0.03),
                failure: nil
            )
        ]
    ) {
        self.answers = answers
    }

    var requests: [BriefRequest] { lock.withLock { received } }

    var runs: Int { requests.count }

    func write(_ request: BriefRequest) async throws -> BriefAnswer {
        let index = lock.withLock {
            received.append(request)
            return received.count - 1
        }
        if let failure { throw failure }
        guard !answers.isEmpty else { return BriefAnswer(text: nil, usage: nil, failure: "prázdno") }
        return answers[min(index, answers.count - 1)]
    }
}
