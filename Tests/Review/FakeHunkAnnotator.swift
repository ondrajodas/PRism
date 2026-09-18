import Foundation

@testable import PRism

/// Anotační session, která nic nespouští — vrátí, co si test předepsal, a pamatuje si zadání (#524).
final class FakeHunkAnnotator: HunkAnnotating, @unchecked Sendable {
    private let runs: [AnnotationRun]
    private let failure: (any Error)?
    private let holds: Bool
    /// Na co běh spadne, když ho někdo **zruší**. `nil` = poctivá `CancellationError`.
    private let cancellationFailure: (any Error)?
    /// Co běh nahlásí jako průběh, než odpoví.
    private let reported: [AnnotationProgress]
    private let lock = NSLock()
    private var recorded: [AnnotationRequest] = []
    private var released = false

    init(
        runs: [AnnotationRun] = [AnnotationRun(answered: true)],
        failing failure: (any Error)? = nil,
        holdsUntilRelease: Bool = false,
        failingOnCancellation cancellationFailure: (any Error)? = nil,
        progress reported: [AnnotationProgress] = []
    ) {
        self.runs = runs
        self.failure = failure
        holds = holdsUntilRelease
        self.cancellationFailure = cancellationFailure
        self.reported = reported
    }

    /// Zadání v pořadí, ve kterém dorazila — z nich se pozná hlava, strom i limit.
    var requests: [AnnotationRequest] { lock.withLock { recorded } }

    func releaseAll() { lock.withLock { released = true } }

    func annotate(
        _ request: AnnotationRequest,
        progress: @escaping AnnotationProgressHandler
    ) async throws -> AnnotationRun {
        let index = lock.withLock {
            recorded.append(request)
            return recorded.count - 1
        }
        for event in reported { progress(event) }

        // Odmlkami, ne `Task.yield()` (#296): zrušený běh musí z čekání vypadnout sám, jinak by
        // test na zrušení visel místo aby spadl.
        while holds, !lock.withLock({ released }) {
            try checkCancellation()
            try? await Task.sleep(for: .milliseconds(10))
        }
        try checkCancellation()

        if let failure { throw failure }
        return runs.isEmpty ? AnnotationRun() : runs[min(index, runs.count - 1)]
    }

    /// Zruší se to **chybou, kterou si test předepsal**, ne vždycky `CancellationError`.
    private func checkCancellation() throws {
        guard Task.isCancelled else { return }
        throw cancellationFailure ?? CancellationError()
    }
}
