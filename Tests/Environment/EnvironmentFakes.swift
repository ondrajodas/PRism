import Foundation

@testable import PRism

/// Filesystém, ve kterém je spustitelné jen to, co si test vyjmenuje.
struct FakeExecutableProbe: ExecutableProbe {
    private let executables: Set<String>

    init(_ paths: [String]) {
        executables = Set(paths)
    }

    func isExecutable(at url: URL) -> Bool {
        executables.contains(url.path(percentEncoded: false))
    }
}

/// Shell, který vrátí předepsaný `PATH` a spočítá, kolikrát se ho někdo zeptal. Ten počet
/// je součást kontraktu: locator ho má spustit nejvýš jednou, a jen když je co dohledávat.
final class FakeShellPathReader: ShellPathReading, @unchecked Sendable {
    private let directories: [URL]
    private let lock = NSLock()
    private var calls = 0

    init(path directories: [String] = []) {
        self.directories = directories.map { URL(filePath: $0) }
    }

    var callCount: Int { lock.withLock { calls } }

    func loginShellPath() async -> [URL] {
        lock.withLock { calls += 1 }
        return directories
    }
}

/// Runner, který nic nespouští — vrátí, co si test předepsal, a pamatuje si volání.
final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]

        /// Vlastní init, aby `environment` mohlo mít default a zůstat `let` — u `var`
        /// s výchozí hodnotou jde zaznamenanou invokaci omylem přepsat.
        init(executable: URL, arguments: [String], environment: [String: String] = [:]) {
            self.executable = executable
            self.arguments = arguments
            self.environment = environment
        }
    }

    private let outcome: Result<ProcessResult, ProcessError>
    private let lock = NSLock()
    private var recorded: [Invocation] = []
    private var recordedTimeouts: [Duration] = []

    init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
        outcome = .success(
            ProcessResult(
                exitCode: exitCode,
                standardOutput: standardOutput,
                standardError: standardError
            )
        )
    }

    init(failing error: ProcessError) {
        outcome = .failure(error)
    }

    var invocations: [Invocation] { lock.withLock { recorded } }

    /// S jakým limitem se volalo, v pořadí. **Zvlášť od `invocations`**, aby se do porovnávané
    /// invokace nedostalo pole, které dnešní testy neuvádějí — a přitom šlo tvrdit, že výpis rep
    /// organizace (#532) neběží pod společným třicetisekundovým limitem, do kterého se změřených
    /// 46,8 s nevejde.
    var timeouts: [Duration] { lock.withLock { recordedTimeouts } }

    func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> ProcessResult {
        lock.withLock {
            recorded.append(
                Invocation(executable: executable, arguments: arguments, environment: environment)
            )
            recordedTimeouts.append(timeout)
        }
        return try outcome.get()
    }
}

/// Runner, který odpovídá jinak na každé volání — na tocích, kde jde několik příkazů po
/// sobě a záleží na jejich výsledcích. Poslední odpověď se opakuje, takže test předepisuje
/// jen to, co ho zajímá.
final class ScriptedProcessRunner: ProcessRunning, @unchecked Sendable {
    private let outcomes: [Result<ProcessResult, ProcessError>]
    private let lock = NSLock()
    private var recorded: [FakeProcessRunner.Invocation] = []

    init(_ outcomes: [Result<ProcessResult, ProcessError>]) {
        precondition(!outcomes.isEmpty, "Runner potřebuje aspoň jednu odpověď.")
        self.outcomes = outcomes
    }

    /// Zkratka: posloupnost exit kódů, nic na výstupu.
    convenience init(exitCodes: [Int32]) {
        self.init(exitCodes.map { .success(ProcessResult(exitCode: $0, standardOutput: "", standardError: "")) })
    }

    var invocations: [FakeProcessRunner.Invocation] { lock.withLock { recorded } }

    /// Argumenty jednotlivých volání — na nich se ověřuje pořadí příkazů.
    var commands: [[String]] { invocations.map(\.arguments) }

    func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> ProcessResult {
        let index: Int = lock.withLock {
            recorded.append(
                .init(executable: executable, arguments: arguments, environment: environment)
            )
            return recorded.count - 1
        }
        return try outcomes[min(index, outcomes.count - 1)].get()
    }
}

/// Terminál, který nic neotevírá — zapamatuje si řádku a odpoví, jak si test řekl (#453).
///
/// Skutečné okno by se v testu nedalo ani vyrobit, ani vzít zpátky, a `osascript` by si vyžádal
/// povolení automatizace pro testovacího hostitele.
final class FakeTerminal: TerminalOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var failure: TerminalError?
    private var opened: [String] = []

    init(failing failure: TerminalError? = nil) {
        self.failure = failure
    }

    /// Co se doopravdy poslalo do terminálu.
    var openedLines: [String] { lock.withLock { opened } }

    /// Co odpoví **příště**. Test „hláška po nepovedeném pokusu zmizí, až se to povede“ potřebuje
    /// jednu instanci se dvěma odpověďmi — dvě instance by o zahození hlášky netvrdily nic.
    func willSucceed() {
        lock.withLock { failure = nil }
    }

    func open(_ commandLine: String) async throws {
        let outcome: TerminalError? = lock.withLock {
            opened.append(commandLine)
            return failure
        }
        if let outcome { throw outcome }
    }
}

/// Čas, který se nikam neposouvá sám.
///
/// Místo čekání si jen zapíše, jak dlouho se mělo čekat — na tom se testuje backoff — a
/// posune `now` o tutéž dobu, aby razítka ve stavu odpovídala. Po `stopAfter` uspáních
/// vyhodí `CancellationError`, čímž ukončí pollovací smyčku; test tak doběhne za nulový
/// reálný čas a bez závodů.
final class FakeTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private let stopAfter: Int
    private var current: Date
    private var sleeps: [Duration] = []

    init(start: Date = Date(timeIntervalSince1970: 1_000_000), stopAfter: Int = .max) {
        current = start
        self.stopAfter = stopAfter
    }

    var now: Date { lock.withLock { current } }

    var requestedSleeps: [Duration] { lock.withLock { sleeps } }

    /// Posune hodiny bez čekání.
    ///
    /// Ne všechno, co v aplikaci závisí na čase, jde přes `sleep` pollingu — návštěva PR (#173)
    /// se stane, když si na ni někdo klikne. Bez tohohle by se „mezitím uběhla hodina“ dalo
    /// v testu vyjádřit jedině druhou instancí, a tím by se ztratilo, že jde o **tytéž** hodiny.
    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }

    func sleep(for duration: Duration) async throws {
        let count: Int = lock.withLock {
            sleeps.append(duration)
            current = current.addingTimeInterval(duration.seconds)
            return sleeps.count
        }
        if count >= stopAfter { throw CancellationError() }
    }
}

/// Předvolby v paměti. Skutečné `UserDefaults` sem nepatří ani jako vlastní suite: ta po
/// sobě nechává soubor v `~/Library/Preferences` (změřeno u #127 — `removePersistentDomain`
/// ani `synchronize()` to nespraví).
final class InMemoryPreferences: PreferenceStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func preference(forKey key: String) -> String? { lock.withLock { values[key] } }

    func setPreference(_ value: String, forKey key: String) {
        lock.withLock { values[key] = value }
    }
}

/// Tabulka procesů, ve které běží jen to, co si test vyjmenuje — a která si **pamatuje, komu se
/// signál vůbec adresoval**.
///
/// Ten seznam je celý smysl fake: nejcennější tvrzení #351 je, že se **nezabije cizí** session,
/// a to se dá ověřit jedině tím, že je seznam prázdný. Skutečnými procesy se navíc nenasimuluje
/// stav, o který tam jde nejvíc — PID, které mezitím dostal někdo jiný.
///
/// **Pokusy se evidují zvlášť od úspěchů, a je to podmínka, ne pohodlí.** `SystemProcessInspector`
/// si identitu ověřuje ještě sám (kvůli okně mezi rozhodnutím a signálem), takže kdyby ji fake
/// ověřoval a mlčel, kryl by rozhodnutí, které cizí proces vůbec zabít **chtělo** — a test
/// „cizí session se nezabije“ by prošel i nad `Policy`, která identitu neporovnává. Změřeno
/// vloženou regresí: přesně tak to proběhlo, dokud fake evidoval jen úspěchy.
final class FakeProcessInspector: ProcessInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var table: [pid_t: ProcessIdentity]
    private var requests: [ProcessIdentity] = []
    private var killed: [ProcessIdentity] = []

    /// Kdo běží. Klíčem je PID, hodnotou identita — takže „PID recyklované cizím procesem“ se
    /// zapíše jako tentýž PID s jiným `startedAt`.
    init(running: [ProcessIdentity] = []) {
        table = Dictionary(uniqueKeysWithValues: running.map { ($0.pid, $0) })
    }

    /// Komu se signál **adresoval**, ať už odešel, nebo ne. Tohle je to, co se v negativních
    /// testech musí rovnat prázdnu.
    var killRequests: [ProcessIdentity] { lock.withLock { requests } }

    /// Komu signál doopravdy odešel.
    var killedProcesses: [ProcessIdentity] { lock.withLock { killed } }

    func identity(of pid: pid_t) -> ProcessIdentity? {
        guard pid > 0 else { return nil }
        return lock.withLock { table[pid] }
    }

    @discardableResult
    func kill(_ identity: ProcessIdentity) -> Bool {
        lock.withLock {
            requests.append(identity)
            guard table[identity.pid] == identity else { return false }
            killed.append(identity)
            table[identity.pid] = nil
            return true
        }
    }
}

/// Cesty, na kterých nástroje leží podle `BinaryLocator.knownLocations`.
enum KnownPath {
    static let gh = "/opt/homebrew/bin/gh"
    static let git = "/opt/homebrew/bin/git"
    static let claude = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".local/bin/claude")
        .path(percentEncoded: false)

    static let all = [gh, git, claude]
}

extension ToolState {
    var path: String? { url?.path(percentEncoded: false) }

    var source: LocationSource? {
        guard case .found(_, let source) = self else { return nil }
        return source
    }
}

/// Editor, který nic neotevírá — zapamatuje si adresy a odpoví, jak si test řekl (#530).
///
/// **Prázdný seznam adres je to nejcennější, co tenhle fake umí.** Nejdůležitější tvrzení #530 je,
/// že se cesta mimo cache do editoru **nedostane**, a to se dá ověřit jedině tím, že se
/// `NSWorkspace` nikdy nic nepředalo. Skutečné otevření by navíc spustilo cizí aplikaci a nedalo
/// se vzít zpátky.
final class FakeEditorOpener: EditorOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var accepts: Bool
    private var urls: [URL] = []

    init(accepting accepts: Bool = true) {
        self.accepts = accepts
    }

    /// Co se doopravdy předalo systému.
    var openedURLs: [URL] { lock.withLock { urls } }

    func open(_ url: URL) async -> Bool {
        lock.withLock {
            urls.append(url)
            return accepts
        }
    }
}
