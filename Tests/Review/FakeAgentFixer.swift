import Foundation

@testable import PRism

/// Fake session, která opravuje vlastní PR (#510) — obyčejná třída, která si pamatuje, co po ní
/// kdo chtěl. **Protokol + fake, ne mockovací framework.**
///
/// Na tom, co si pamatuje, stojí ta nejcennější tvrzení #510: **kolikrát se pustila** (nula
/// u cizího PR, u vypnuté brány a u vlastního komentáře) a **co dostala v requestu** (strom v cache
/// je zároveň rozsah, na který se omezí `Write` a `Edit`).
final class FakeAgentFixer: AgentFixing, @unchecked Sendable {
    /// Co vrátit. Když je odpovědí míň než běhů, platí ta poslední.
    var answers: [AgentFixAnswer]
    /// Co vyhodit místo odpovědi. `nil` = odpoví.
    var failure: (any Error)?
    /// Co se má stát **před** odpovědí — sem si test dá zrušení tasku.
    var beforeAnswer: (@Sendable (AgentFixRequest) -> Void)?
    /// Kroky, které se ohlásí do průběhu, než přijde odpověď (#511). Prázdné = neohlásí se nic.
    ///
    /// **Pokusy o nástroj, ne text**: živý ocas v panelu se skládá z nich, protože prózu modelu
    /// aplikace ze streamu nečte.
    var steps: [ToolAttempt] = []

    private let lock = NSLock()
    private var received: [AgentFixRequest] = []

    init(answers: [AgentFixAnswer] = [AgentFixAnswer(files: ["App/A.swift"], summary: "opraveno")]) {
        self.answers = answers
    }

    var requests: [AgentFixRequest] { lock.withLock { received } }

    var runs: Int { requests.count }

    func fix(
        _ request: AgentFixRequest,
        progress: @escaping AgentFixProgressHandler
    ) async throws -> AgentFixAnswer {
        let index = lock.withLock {
            received.append(request)
            return received.count - 1
        }
        if !steps.isEmpty { progress(.started) }
        for step in steps { progress(.attemptedTool(step)) }
        beforeAnswer?(request)
        if let failure { throw failure }
        guard !answers.isEmpty else { return AgentFixAnswer() }
        return answers[min(index, answers.count - 1)]
    }
}
