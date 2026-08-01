import Foundation

@testable import PRism

/// Proud, který nic nespouští — přehraje, co si test předepsal, a pamatuje si volání.
///
/// Umí navíc běh **pozdržet**: dokud se nepustí, zůstává „běžící". Na tom se testuje limit
/// souběhu (kolik jich naráz projde) i zrušení (proud se ukončí zvenčí).
final class FakeProcessStreamer: ProcessStreaming, @unchecked Sendable {
    struct Invocation: Sendable, Equatable {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]
        let workingDirectory: URL?
    }

    /// Co proud udělá. Poslední scénář se opakuje, takže test předepisuje jen to, co ho
    /// zajímá — stejně jako `ScriptedProcessRunner`.
    enum Script: Sendable {
        /// Vypíše řádky a skončí daným kódem.
        case output(lines: [String], exitCode: Int32 = 0, standardError: String = "")
        /// Vypíše řádky a spadne na timeoutu — tak, jak to dělá `SubprocessStreamer`.
        case timeout(after: [String])
        /// Binárka se vůbec nespustila.
        case launchFailure(String)
    }

    private let scripts: [Script]
    private let holds: Bool
    private let lock = NSLock()
    private var recorded: [Invocation] = []
    private var starts = 0
    private var active = 0
    private var peak = 0
    private var cancellations = 0
    private var released = false

    init(_ scripts: [Script], holdsUntilRelease: Bool = false) {
        precondition(!scripts.isEmpty, "Proud potřebuje aspoň jeden scénář.")
        self.scripts = scripts
        holds = holdsUntilRelease
    }

    /// Zkratka pro jediný úspěšný běh.
    convenience init(lines: [String], exitCode: Int32 = 0, standardError: String = "") {
        self.init([.output(lines: lines, exitCode: exitCode, standardError: standardError)])
    }

    var invocations: [Invocation] { lock.withLock { recorded } }
    var startedCount: Int { lock.withLock { starts } }
    /// Nejvíc běhů, které se potkaly naráz. Na tom se pozná limit souběhu.
    var peakConcurrency: Int { lock.withLock { peak } }
    var cancellationCount: Int { lock.withLock { cancellations } }

    /// Pustí dál všechny pozdržené běhy i ty, které teprve přijdou.
    func releaseAll() { lock.withLock { released = true } }

    /// Počká, až se rozběhne zadaný počet běhů.
    ///
    /// Točení přes `Task.yield()` schválně: test, který se nedočká, uvízne — což je ale
    /// srozumitelnější selhání než čekání na razítko hodin, které v testech nejdou.
    func waitForStarts(_ count: Int) async {
        while startedCount < count { await Task.yield() }
    }

    func stream(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        timeout: Duration
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        let script: Script = lock.withLock {
            recorded.append(
                Invocation(
                    executable: executable,
                    arguments: arguments,
                    environment: environment,
                    workingDirectory: workingDirectory
                )
            )
            return scripts[min(recorded.count - 1, scripts.count - 1)]
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                self.markStarted()
                while self.holds, !self.isReleased, !Task.isCancelled { await Task.yield() }
                self.emit(script, into: continuation)
                self.markFinished()
            }
            continuation.onTermination = { termination in
                task.cancel()
                guard case .cancelled = termination else { return }
                self.lock.withLock { self.cancellations += 1 }
            }
        }
    }

    private func emit(
        _ script: Script,
        into continuation: AsyncThrowingStream<ProcessEvent, any Error>.Continuation
    ) {
        switch script {
        case .output(let lines, let exitCode, let standardError):
            for line in lines { continuation.yield(.line(line)) }
            continuation.yield(.finished(exitCode: exitCode, standardError: standardError))
            continuation.finish()
        case .timeout(let lines):
            for line in lines { continuation.yield(.line(line)) }
            continuation.finish(throwing: ProcessError.timedOut)
        case .launchFailure(let detail):
            continuation.finish(throwing: ProcessError.launchFailed(detail))
        }
    }

    private var isReleased: Bool { lock.withLock { released } }

    private func markStarted() {
        lock.withLock {
            starts += 1
            active += 1
            peak = max(peak, active)
        }
    }

    private func markFinished() {
        lock.withLock { active -= 1 }
    }
}
