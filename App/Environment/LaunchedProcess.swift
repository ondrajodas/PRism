import Foundation

/// Běžící podproces a jeho pipy.
///
/// `Process` ani `FileHandle` nejsou `Sendable`, ale runner s nimi pracuje z několika tasků
/// naráz — každý pipe čte jeden task, další čeká na konec a další po timeoutu posílá
/// signál. Tenhle box to zúží na operace, které jsou v takovém rozložení bezpečné: jeden
/// handle nikdy nečtou dva tasky a signál jde přes POSIX `kill`, který na doběhlém procesu
/// jen vrátí chybu — na rozdíl od `Process.terminate()`, které umí vyhodit výjimku.
///
/// Staví na něm obojí: `SubprocessRunner`, který výstup bufferuje, i `SubprocessStreamer`,
/// který ho podává po řádcích.
final class LaunchedProcess: @unchecked Sendable {
    private let process = Process()
    private let output = Pipe()
    private let error = Pipe()
    private let lock = NSLock()
    /// Kam si zapsat, že proces běží — aby ho po zabité aplikaci šlo dohledat a zabít (#351).
    ///
    /// **Nepovinné, a schválně.** Dostává ho jedině streamovací cesta, tedy `claude -p`: ta běží
    /// minuty a platí se za ni tokeny, takže osiřelá stojí peníze. Bufferovaná cesta jsou `gh`
    /// a `git`, které doběhnou samy za sekundy — a hlavně se pouštějí při **každém tiku pollingu**,
    /// takže zápis do cache u nich znamená sáhnutí na disk za nic.
    private let sessions: RunningSessions?
    private var timedOut = false
    private var running = false
    private var killRequested = false
    private var terminationStatus: Int32?
    private var exitWaiters: [CheckedContinuation<Int32, Never>] = []

    init(
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        sessions: RunningSessions? = nil
    ) {
        self.sessions = sessions
        process.executableURL = executable
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        // Pracovní složku nejde `claude` předat flagem — je to `cwd` procesu (ověřeno
        // u #12). `git` si vystačí s `-C`, takže tohle nastavuje jen streamovací cesta.
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            self?.processDidExit(process.terminationStatus)
        }
    }

    func launch() throws {
        do {
            try process.run()
        } catch {
            throw ProcessError.launchFailed(error.localizedDescription)
        }

        // Značka se zapisuje **hned**, ještě před vyřizováním odloženého zrušení: proces už běží,
        // takže od téhle chvíle může aplikaci přežít. Kdyby se zápis odložil, vešlo by se do té
        // mezery ukončení aplikace — a osiřelou session by pak nikdo nedohledal.
        sessions?.remember(pid: process.processIdentifier)

        // Zabít se o proces mohl někdo říct dřív, než vznikl — zrušení dorazí kdykoli.
        // Bez tohohle by `SIGKILL` narazil na `isRunning == false`, neudělal nic a proces
        // by pak naběhl a doběhl do konce, i když už ho nikdo nechce.
        let wanted: Bool = lock.withLock {
            running = true
            return killRequested
        }
        if wanted { signal(SIGKILL) }
    }

    func readStandardOutput() -> String { Self.readToEnd(output) }

    func readStandardError() -> String { Self.readToEnd(error) }

    /// Podává stdout po kouscích, jak vznikají; `nil` znamená konec proudu. Vrácené `false`
    /// znamená „už mě to nezajímá“ a čtení se odpojí.
    ///
    /// Čte `readabilityHandler`, ne `readToEnd()`: ten by výstup vydal až po doběhnutí
    /// procesu, takže by z „průběžných nálezů“ nezbylo nic — a hlavně by na patnáctiminutové
    /// review držel blokující vlákno.
    func streamStandardOutput(_ receive: @escaping @Sendable (Data?) -> Bool) {
        Self.stream(output, into: receive)
    }

    /// Totéž pro stderr. Ten se nikam nestreamuje, jen se sbírá na vysvětlení selhání —
    /// číst ho ale musíme průběžně, jinak si proces naplní buffer jádra a zasekne se.
    func streamStandardError(_ receive: @escaping @Sendable (Data?) -> Bool) {
        Self.stream(error, into: receive)
    }

    /// Konec procesu **nedrží vlákno**. `waitUntilExit()` je blokující, takže by na každý
    /// podproces připadala tři vlákna z `ioQueue` (dvě čtení a čekání) — a jakmile jich je
    /// v běhu dost, nemá si nové čekání kde spustit a celé volání uvízne. `Process` umí dát
    /// vědět sám, tak si necháme zavolat.
    func exitCode() async -> Int32 {
        await withCheckedContinuation { continuation in
            let finished: Int32? = lock.withLock {
                if let status = terminationStatus { return status }
                exitWaiters.append(continuation)
                return nil
            }
            if let finished { continuation.resume(returning: finished) }
        }
    }

    /// Volá `terminationHandler`. Když si o výsledek ještě nikdo neřekl, jen se uloží.
    ///
    /// Čekatelů je pole, ne jeden: druhé volání `exitCode()` by jinak toho prvního
    /// přepsalo a jeho `continuation` by se nikdy neresumnula — task by visel navždy
    /// a runtime by to jen tiše ohlásil jako uniklou continuation.
    private func processDidExit(_ status: Int32) {
        // Značka jde pryč koncem procesu, ne až úklidem při dalším startu: zapsaný PID, pod kterým
        // už nic neběží, by se dal recyklovat a další start by na něj koukal jako na sirotka.
        // Identitu si `reapOrphans` ověřuje, takže by ho nezabil — ale značka, kterou nikdo
        // nemaže, je mrtvá váha, která svádí spolehnout se na ni.
        sessions?.forget(pid: process.processIdentifier)

        let waiters: [CheckedContinuation<Int32, Never>] = lock.withLock {
            terminationStatus = status
            defer { exitWaiters.removeAll() }
            return exitWaiters
        }
        for waiter in waiters { waiter.resume(returning: status) }
    }

    func signal(_ signalNumber: Int32) {
        guard process.isRunning else { return }
        kill(process.processIdentifier, signalNumber)
    }

    /// Zabít proces, ať už běží, nebo se teprve spouští.
    ///
    /// `signal(SIGKILL)` sám nestačí: zrušení může dorazit v okně mezi nastavením handleru
    /// a `process.run()`, kdy ještě není koho zabít — a proces by pak naběhl osiřelý.
    func requestKill() {
        let now: Bool = lock.withLock {
            killRequested = true
            return running
        }
        if now { signal(SIGKILL) }
    }

    func markTimedOut() { lock.withLock { timedOut = true } }

    var didTimeOut: Bool { lock.withLock { timedOut } }

    private static func readToEnd(_ pipe: Pipe) -> String {
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Prázdná dávka znamená EOF. Handler se přitom musí odpojit — jinak by se
    /// `readabilityHandler` volal pořád dokola nad zavřeným koncem.
    ///
    /// Odpojí se i tehdy, když příjemce řekne, že už nemá odběratele. Rouru může po
    /// zabitém procesu držet jeho potomek a ukecaný potomek by jinak plnil buffer, ze
    /// kterého už nikdo nečte.
    private static func stream(_ pipe: Pipe, into receive: @escaping @Sendable (Data?) -> Bool) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                _ = receive(nil)
                return
            }
            if !receive(data) { handle.readabilityHandler = nil }
        }
    }
}
