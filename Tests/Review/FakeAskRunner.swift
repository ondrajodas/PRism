import Foundation

@testable import PRism

/// Rozhovor, který nic nespouští — vrátí, co si test předepsal, a pamatuje si otázky (#452).
///
/// Odpovědi se berou **po jedné z fronty**, ne jedna dokola: celé issue stojí na tom, že druhá
/// otázka navazuje na první, takže se musí dát předepsat dvě různé. Když fronta dojde, vrací se
/// poslední — test, který se ptá potřetí, tím netvrdí nic navíc.
final class FakeAskRunner: AskRunning, @unchecked Sendable {
    private let answers: [AskAnswer]
    private let failure: (any Error)?
    private let holds: Bool
    /// Na co běh spadne, když ho někdo **zruší**.
    ///
    /// `nil` = poctivá `CancellationError`. Cokoli jiného vyrábí to, co dělá skutečný zabitý
    /// podproces: `git` ani `claude` o zrušení nevědí, takže vyhodí **svou vlastní** chybu
    /// a `CancellationError` se ven vůbec nedostane.
    private let cancellationFailure: (any Error)?
    /// Co běh nahlásí jako průběh, než odpoví.
    private let reported: [AskProgress]
    private let lock = NSLock()
    private var recorded: [AskRequest] = []
    private var released = false

    init(
        answers: [AskAnswer] = [AskAnswer(text: "protože", sessionID: "s1")],
        failing failure: (any Error)? = nil,
        holdsUntilRelease: Bool = false,
        failingOnCancellation cancellationFailure: (any Error)? = nil,
        progress reported: [AskProgress] = []
    ) {
        self.answers = answers
        self.failure = failure
        holds = holdsUntilRelease
        self.cancellationFailure = cancellationFailure
        self.reported = reported
    }

    /// Otázky v pořadí, ve kterém dorazily — z nich se pozná, jestli se navazovalo.
    var requests: [AskRequest] { lock.withLock { recorded } }

    func releaseAll() { lock.withLock { released = true } }

    func ask(_ request: AskRequest, progress: @escaping AskProgressHandler) async throws -> AskAnswer {
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
        return answers.isEmpty ? AskAnswer() : answers[min(index, answers.count - 1)]
    }

    /// Zruší se to **chybou, kterou si test předepsal**, ne vždycky `CancellationError`.
    private func checkCancellation() throws {
        guard Task.isCancelled else { return }
        throw cancellationFailure ?? CancellationError()
    }
}
