import Foundation

/// Runner nad `Foundation.Process`.
struct SubprocessRunner: ProcessRunning {
    func run(_ executable: URL, arguments: [String], timeout: Duration) async throws -> ProcessResult {
        let launched = LaunchedProcess(executable: executable, arguments: arguments)
        try launched.launch()

        return try await withThrowingTaskGroup(of: ProcessResult?.self) { group in
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
    }

    /// Oba pipy se čtou souběžně. Sériové čtení umí zablokovat: než dojde EOF na prvním,
    /// druhý naplní buffer jádra a proces se zasekne na zápisu.
    private static func collect(_ launched: LaunchedProcess) async -> ProcessResult {
        async let output = Task.detached { launched.readStandardOutput() }.value
        async let error = Task.detached { launched.readStandardError() }.value
        let (standardOutput, standardError) = await (output, error)
        let exitCode = await Task.detached { launched.waitUntilExit() }.value
        return ProcessResult(
            exitCode: exitCode,
            standardOutput: standardOutput,
            standardError: standardError
        )
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

/// Běžící podproces a jeho pipy.
///
/// `Process` ani `FileHandle` nejsou `Sendable`, ale runner s nimi pracuje z několika tasků
/// naráz — každý pipe čte jeden task, další čeká na konec a další po timeoutu posílá
/// signál. Tenhle box to zúží na operace, které jsou v takovém rozložení bezpečné: jeden
/// handle nikdy nečtou dva tasky a signál jde přes POSIX `kill`, který na doběhlém procesu
/// jen vrátí chybu — na rozdíl od `Process.terminate()`, které umí vyhodit výjimku.
private final class LaunchedProcess: @unchecked Sendable {
    private let process = Process()
    private let output = Pipe()
    private let error = Pipe()
    private let lock = NSLock()
    private var timedOut = false

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
    }

    func launch() throws {
        do {
            try process.run()
        } catch {
            throw ProcessError.launchFailed(error.localizedDescription)
        }
    }

    func readStandardOutput() -> String { Self.readToEnd(output) }

    func readStandardError() -> String { Self.readToEnd(error) }

    func waitUntilExit() -> Int32 {
        process.waitUntilExit()
        return process.terminationStatus
    }

    func signal(_ signalNumber: Int32) {
        guard process.isRunning else { return }
        kill(process.processIdentifier, signalNumber)
    }

    func markTimedOut() { lock.withLock { timedOut = true } }

    var didTimeOut: Bool { lock.withLock { timedOut } }

    private static func readToEnd(_ pipe: Pipe) -> String {
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
