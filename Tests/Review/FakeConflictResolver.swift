import Foundation

@testable import PRism

/// Fake session, která slévá konflikty (#467) — obyčejná třída, která si pamatuje, co po ní kdo
/// chtěl. **Protokol + fake, ne mockovací framework.**
///
/// **Odpovědi se berou po kolech**, ne jedna dokola: kolo za kolem je zrovna to, co má u slévání
/// smysl testovat (rebase se zastaví u každého kolizního commitu), a jedna hodnota by ten směr
/// nedovolila napsat vůbec. Když jich je připraveno málo, platí ta poslední.
final class FakeConflictResolver: ConflictResolving, @unchecked Sendable {
    /// Co vrátit v jednotlivých kolech.
    var answers: [ConflictAnswer]
    /// Co vyhodit místo odpovědi. `nil` = odpoví.
    var failure: (any Error)?
    /// Co se má stát **před** odpovědí — sem si test dá zrušení tasku nebo zápis do stromu.
    var beforeAnswer: (@Sendable (ConflictRequest) -> Void)?

    private let lock = NSLock()
    private var received: [ConflictRequest] = []

    init(answers: [ConflictAnswer] = [ConflictAnswer()]) {
        self.answers = answers
    }

    /// Requesty, které přišly. **Na tom stojí tvrzení o rozsahu zápisu** (strom v requestu je
    /// zároveň to, na co se omezí `Write` a `Edit`) **i o tom, co je v promptu** — kolidující soubory
    /// jdou session textem, ne vlastním polem.
    var requests: [ConflictRequest] { lock.withLock { received } }

    var rounds: Int { requests.count }

    func resolve(
        _ request: ConflictRequest,
        progress: @escaping ConflictProgressHandler
    ) async throws -> ConflictAnswer {
        let index = lock.withLock {
            received.append(request)
            return received.count - 1
        }
        beforeAnswer?(request)
        if let failure { throw failure }
        guard !answers.isEmpty else { return ConflictAnswer() }
        return answers[min(index, answers.count - 1)]
    }
}
