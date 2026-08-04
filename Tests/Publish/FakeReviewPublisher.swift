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
    /// Co se chtělo po vláknech (#73), v pořadí. Stejný důvod jako u `asked`: na počtu stojí
    /// testy, které tvrdí, že se **nevolalo nic**.
    private var threadCalls: [ThreadCall] = []
    private var replyOutcome: Result<ThreadComment, any Error>?
    private var resolutionOutcome: Result<ThreadResolution, any Error>?
    /// Drží odeslání „rozběhnuté“, dokud se nepustí. Bez toho se nedá otestovat, co se stane
    /// **během** odesílání — a právě tam bydlí zákaz druhého odeslání. Stejný důvod, kvůli
    /// kterému `FakeReviewRunner` umí pozdržet běh.
    private var gate: (() async -> Void)?

    init(_ outcomes: [Result<SubmittedReview, any Error>]) {
        self.outcomes = outcomes
    }

    /// Co se po fake publisherovi chtělo nad vláknem.
    enum ThreadCall: Equatable {
        case reply(ThreadTarget, body: String)
        case resolution(ThreadTarget, resolved: Bool)
    }

    convenience init(reply outcome: Result<ThreadComment, any Error>) {
        self.init([])
        lock.withLock { replyOutcome = outcome }
    }

    convenience init(resolution outcome: Result<ThreadResolution, any Error>) {
        self.init([])
        lock.withLock { resolutionOutcome = outcome }
    }

    var threadActions: [ThreadCall] { lock.withLock { threadCalls } }

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

    func reply(to thread: ThreadTarget, body: String) async throws -> ThreadComment {
        lock.withLock { threadCalls.append(.reply(thread, body: body)) }
        // Brána je **za** zápisem, jako u `submit`: test musí poznat, že odesílání běží.
        if let gate = lock.withLock({ gate }) { await gate() }
        guard let outcome = lock.withLock({ replyOutcome }) else {
            throw PublishError.unknown("Fake publisher nemá co vrátit na odpověď.")
        }
        return try outcome.get()
    }

    func setResolved(_ resolved: Bool, of thread: ThreadTarget) async throws -> ThreadResolution {
        lock.withLock { threadCalls.append(.resolution(thread, resolved: resolved)) }
        if let gate = lock.withLock({ gate }) { await gate() }
        guard let outcome = lock.withLock({ resolutionOutcome }) else {
            throw PublishError.unknown("Fake publisher nemá co vrátit na vyřešení.")
        }
        return try outcome.get()
    }
}
