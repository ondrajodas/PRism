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
        timeout: Duration
    ) async throws -> ProcessResult {
        lock.withLock {
            recorded.append(Invocation(executable: executable, arguments: arguments))
        }
        return try outcome.get()
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
