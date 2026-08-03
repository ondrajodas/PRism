import Foundation

@testable import PRism

/// Publisher, který nic neodesílá — jen si pamatuje, co po něm kdo chtěl.
///
/// Že **nic neodešlo**, je u tohohle protokolu to hlavní, co má fake zaručit: testy okolo
/// odesílání se nesmí spoléhat na síť ani na sandbox.
final class FakeReviewPublisher: ReviewPublishing, @unchecked Sendable {
    private let outcomes: [Result<SubmittedReview, any Error>]
    private let lock = NSLock()
    private var asked: [ReviewDraft] = []

    init(_ outcomes: [Result<SubmittedReview, any Error>]) {
        self.outcomes = outcomes
    }

    convenience init(always outcome: Result<SubmittedReview, any Error>) {
        self.init([outcome])
    }

    /// Co se po něm chtělo, v pořadí. Na počtu stojí testy, které tvrdí, že se **nevolalo nic**.
    var submitted: [ReviewDraft] { lock.withLock { asked } }

    func submit(_ draft: ReviewDraft) async throws -> SubmittedReview {
        let index: Int = lock.withLock {
            asked.append(draft)
            return asked.count - 1
        }
        guard !outcomes.isEmpty else {
            throw PublishError.unknown("Fake publisher nemá co vrátit.")
        }
        return try outcomes[min(index, outcomes.count - 1)].get()
    }
}
