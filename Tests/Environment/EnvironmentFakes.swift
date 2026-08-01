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
        }
        return try outcome.get()
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

    func sleep(for duration: Duration) async throws {
        let count: Int = lock.withLock {
            sleeps.append(duration)
            current = current.addingTimeInterval(duration.seconds)
            return sleeps.count
        }
        if count >= stopAfter { throw CancellationError() }
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
