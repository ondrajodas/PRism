import Foundation

/// Runner nad `Foundation.Process`.
struct SubprocessRunner: ProcessRunning {
    func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> ProcessResult {
        let launched = LaunchedProcess(
            executable: executable,
            arguments: arguments,
            environment: environment
        )
        try launched.launch()

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: ProcessResult?.self) { group in
                group.addTask { await Self.collect(launched) }
                group.addTask {
                    await Self.enforceTimeout(timeout, on: launched)
                    return nil
                }

                while let finished = try await group.next() {
                    guard let result = finished else { continue }
                    group.cancelAll()
                    if launched.didTimeOut { throw ProcessError.timedOut }
                    return result
                }
                throw ProcessError.launchFailed("Proces skončil bez výsledku.")
            }
        } onCancel: {
            // Bez tohohle by zrušené volání čekalo, až proces doběhne sám — čtení pipy
            // skončí teprve tím, že je zavře.
            launched.requestKill()
        }
    }

    /// Oba pipy se čtou souběžně. Sériové čtení umí zablokovat: než dojde EOF na prvním,
    /// druhý naplní buffer jádra a proces se zasekne na zápisu.
    private static func collect(_ launched: LaunchedProcess) async -> ProcessResult {
        async let output = blocking { launched.readStandardOutput() }
        async let error = blocking { launched.readStandardError() }
        let (standardOutput, standardError) = await (output, error)
        let exitCode = await launched.exitCode()
        return ProcessResult(
            exitCode: exitCode,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    /// Vlákna pro blokující I/O. `readToEnd()` ani `waitUntilExit()` neumí čekat
    /// kooperativně, takže nesmí běžet na kooperativním poolu — ten má jen tolik vláken,
    /// kolik je jader, a několik paralelních review by si je vzájemně vyhladovělo.
    private static let ioQueue = DispatchQueue(
        label: "com.ondrajodas.prism.subprocess-io",
        attributes: .concurrent
    )

    /// Blokující práci odsune na `ioQueue`, ale volajícímu ji podá jako `async` —
    /// přes `async let` tak zůstává navázaná na životní cyklus `run()`.
    private static func blocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            ioQueue.async { continuation.resume(returning: work()) }
        }
    }

    /// Po limitu pošle `SIGTERM`, a kdo neodejde, dostane `SIGKILL`. Bez té eskalace by
    /// zaseknutý proces nikdy nezavřel pipy, čtení by nedoběhlo a aplikace by uvízla na
    /// startu — což je přesně to selhání, kvůli kterému timeout existuje.
    private static func enforceTimeout(_ timeout: Duration, on launched: LaunchedProcess) async {
        do {
            try await Task.sleep(for: timeout)
        } catch {
            return // Proces doběhl první a group tenhle task zrušila.
        }
        launched.markTimedOut()
        launched.signal(SIGTERM)
        try? await Task.sleep(for: .seconds(2))
        launched.signal(SIGKILL)
    }
}
