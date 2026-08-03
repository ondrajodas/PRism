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
    /// Drží odeslání „rozběhnuté“, dokud se nepustí. Bez toho se nedá otestovat, co se stane
    /// **během** odesílání — a právě tam bydlí zákaz druhého odeslání. Stejný důvod, kvůli
    /// kterému `FakeReviewRunner` umí pozdržet běh.
    private var gate: (() async -> Void)?

    init(_ outcomes: [Result<SubmittedReview, any Error>]) {
        self.outcomes = outcomes
    }

    /// Odeslání se zastaví, dokud `release` nedovolí pokračovat.
    func hold(until gate: @escaping () async -> Void) {
        lock.withLock { self.gate = gate }
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
        // Zápis do `asked` je **před** bránou schválně: test se potřebuje dozvědět, že
        // odeslání běží, aby mohl zkusit to druhé.
        if let gate = lock.withLock({ gate }) { await gate() }
        guard !outcomes.isEmpty else {
            throw PublishError.unknown("Fake publisher nemá co vrátit.")
        }
        return try outcomes[min(index, outcomes.count - 1)].get()
    }
}
