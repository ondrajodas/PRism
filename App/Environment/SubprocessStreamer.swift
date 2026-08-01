import Foundation

/// Streamovací runner nad `Foundation.Process`.
struct SubprocessStreamer: ProcessStreaming {
    func stream(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        timeout: Duration
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        AsyncThrowingStream { continuation in
            let launched = LaunchedProcess(
                executable: executable,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            )
            let run = StreamedRun(launched: launched, continuation: continuation)
            let timeoutTask = Task { await Self.enforceTimeout(timeout, on: run) }

            // `onTermination` se nastavuje **před** spuštěním: kdyby proud skončil dřív,
            // než se handler doplní, zrušený konzument by po sobě nechal běžící `claude`.
            //
            // Hlídání timeoutu se ruší tady, ne po konci procesu: dokud proud neskončil,
            // je pořád co hlídat — třeba rouru, kterou drží něco, co po procesu zbylo.
            continuation.onTermination = { termination in
                timeoutTask.cancel()
                // Zrušení musí proces zabít. Bez toho by session běžela dál i poté, co
                // uživatel review zrušil nebo zavřel okno.
                if case .cancelled = termination { launched.signal(SIGKILL) }
            }

            do {
                try launched.launch()
            } catch {
                continuation.finish(throwing: error)
                return
            }

            launched.streamStandardOutput { run.receiveOutput($0) }
            launched.streamStandardError { run.receiveError($0) }
            Task { run.exited(with: await launched.exitCode()) }
        }
    }

    /// Po limitu `SIGTERM`, a kdo neodejde, dostane `SIGKILL` — stejná eskalace jako
    /// u bufferované cesty.
    private static func enforceTimeout(_ timeout: Duration, on run: StreamedRun) async {
        do {
            try await Task.sleep(for: timeout)
        } catch {
            return // Proud skončil první.
        }
        await run.timeOut()
    }
}

/// Stav jednoho streamovaného běhu: rozdělení stdout na řádky, sběr stderru a rozhodnutí,
/// kdy je proud u konce.
///
/// Proud smí skončit teprve tehdy, když dorazil konec **obou** rour i exit kód. Skončit
/// hned po exitu by uřízlo řádky, které ještě leží v rouře — a u review by tak zmizely
/// nálezy, které proces stihl vypsat.
private final class StreamedRun: @unchecked Sendable {
    private let launched: LaunchedProcess
    private let continuation: AsyncThrowingStream<ProcessEvent, any Error>.Continuation
    private let lock = NSLock()
    private var pending = Data()
    private var errorOutput = Data()
    private var outputClosed = false
    private var errorClosed = false
    private var exitCode: Int32?
    private var finished = false

    init(
        launched: LaunchedProcess,
        continuation: AsyncThrowingStream<ProcessEvent, any Error>.Continuation
    ) {
        self.launched = launched
        self.continuation = continuation
    }

    /// `nil` znamená konec proudu.
    func receiveOutput(_ data: Data?) {
        lock.withLock {
            guard let data else {
                outputClosed = true
                // Nedokončený poslední řádek se **pošle**, ne zahodí. Zabitý proces umí
                // stream useknout uprostřed řádku a `StreamParser` si s tím poradí sám —
                // spočítá ho jako rozbitý. Tiché zahození by se nedalo od ničeho odlišit.
                flushPendingLine()
                finishIfDone()
                return
            }
            pending.append(data)
            emitCompleteLines()
        }
    }

    func receiveError(_ data: Data?) {
        lock.withLock {
            guard let data else {
                errorClosed = true
                finishIfDone()
                return
            }
            errorOutput.append(data)
        }
    }

    func exited(with code: Int32) {
        lock.withLock {
            exitCode = code
            finishIfDone()
        }
    }

    /// Vypršel limit: `SIGTERM`, a kdo neodejde, dostane `SIGKILL`.
    ///
    /// Zabitý proces roury obvykle zavře sám a proud skončí normální cestou. Když je drží
    /// něco, co po něm zbylo (potomek, který přežil), čekal by proud na EOF navždy — proto
    /// má timeout poslední slovo a proud ukončí sám.
    func timeOut() async {
        launched.markTimedOut()
        launched.signal(SIGTERM)
        try? await Task.sleep(for: .seconds(2))
        launched.signal(SIGKILL)
        try? await Task.sleep(for: .seconds(2))
        lock.withLock {
            guard !finished else { return }
            finished = true
            continuation.finish(throwing: ProcessError.timedOut)
        }
    }

    private func emitCompleteLines() {
        while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = pending[pending.startIndex..<end]
            pending.removeSubrange(pending.startIndex...end)
            continuation.yield(.line(String(decoding: line, as: UTF8.self)))
        }
    }

    private func flushPendingLine() {
        guard !pending.isEmpty else { return }
        continuation.yield(.line(String(decoding: pending, as: UTF8.self)))
        pending.removeAll()
    }

    private func finishIfDone() {
        guard !finished, outputClosed, errorClosed, let exitCode else { return }
        finished = true

        // Timeout je chyba proudu, ne výsledek běhu: exit kód zabitého procesu nic
        // nevypovídá o tom, co reviewer stihl, a volající na tom staví jiný stav.
        guard !launched.didTimeOut else {
            continuation.finish(throwing: ProcessError.timedOut)
            return
        }
        continuation.yield(
            .finished(
                exitCode: exitCode,
                standardError: String(decoding: errorOutput, as: UTF8.self)
            )
        )
        continuation.finish()
    }
}
