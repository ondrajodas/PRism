import Foundation

/// Kde binárka leží, nebo že nikde.
enum ToolState: Sendable, Equatable {
    case found(URL, source: LocationSource)
    case missing

    var url: URL? {
        guard case .found(let url, _) = self else { return nil }
        return url
    }
}

/// Odkud se cesta vzala. Diagnostika pro gate obrazovku: na známém místě, nebo až přes
/// `PATH` login shellu.
enum LocationSource: Sendable, Equatable {
    case knownLocation
    case loginShellPath
}

/// Najde absolutní cesty k binárkám.
///
/// Nejdřív známá místa, protože pokrývají skoro všechny instalace a nic nespouštějí. Login
/// shell přijde na řadu až pro to, co v nich není, a spustí se **jednou** pro všechny zbylé
/// binárky — ne pro každou zvlášť.
struct BinaryLocator: Sendable {
    /// Místa, kde binárky na macOS bývají. Pořadí rozhoduje o tom, která instalace vyhraje:
    /// Homebrew na Apple Siliconu, Homebrew na Intelu, systém, uživatelské instalace
    /// (tam sedí `claude`).
    static let knownLocations: [URL] = [
        URL(filePath: "/opt/homebrew/bin"),
        URL(filePath: "/usr/local/bin"),
        URL(filePath: "/usr/bin"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin"),
    ]

    private let probe: ExecutableProbe
    private let shellPath: ShellPathReading

    init(probe: ExecutableProbe, shellPath: ShellPathReading) {
        self.probe = probe
        self.shellPath = shellPath
    }

    func locate() async -> [Tool: ToolState] {
        var states = knownLocationStates()

        let missing = Tool.allCases.filter { states[$0] == .missing }
        guard !missing.isEmpty else { return states }

        let directories = await shellPath.loginShellPath()
        for tool in missing {
            states[tool] = find(tool, in: directories, source: .loginShellPath)
        }
        return states
    }

    private func knownLocationStates() -> [Tool: ToolState] {
        var states: [Tool: ToolState] = [:]
        for tool in Tool.allCases {
            states[tool] = find(tool, in: Self.knownLocations, source: .knownLocation)
        }
        return states
    }

    private func find(_ tool: Tool, in directories: [URL], source: LocationSource) -> ToolState {
        for directory in directories {
            let candidate = directory.appending(path: tool.executableName)
            if probe.isExecutable(at: candidate) {
                return .found(candidate, source: source)
            }
        }
        return .missing
    }
}
