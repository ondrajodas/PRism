import Foundation

/// Přečtení `PATH` z login shellu. Fallback pro binárky, které neleží na známém místě.
protocol ShellPathReading: Sendable {
    /// Složky z `PATH` login shellu. Prázdné, když se ho nepodařilo přečíst.
    func loginShellPath() async -> [URL]
}

/// Spustí login shell a nechá si vypsat `PATH`.
///
/// Login shell, protože právě v `.zprofile` a `.zshrc` leží `eval $(brew shellenv)` a
/// podobné doplňky `PATH`, které aplikace spuštěná z Finderu nikdy nevidí.
///
/// Když shell selže nebo se zasekne na vlastní konfiguraci, výsledkem je prázdný seznam.
/// Binárka pak vyjde jako nenalezená a gate obrazovka to řekne — což je lepší než aby
/// aplikace uvízla na startu kvůli cizímu `.zshrc`.
struct LoginShellPathReader: ShellPathReading {
    private let runner: ProcessRunning
    private let timeout: Duration

    init(runner: ProcessRunning, timeout: Duration = .seconds(5)) {
        self.runner = runner
        self.timeout = timeout
    }

    func loginShellPath() async -> [URL] {
        guard
            let result = try? await runner.run(
                Self.shell,
                arguments: ["-lc", "echo $PATH"],
                timeout: timeout
            ),
            result.exitCode == 0
        else { return [] }

        return Self.directories(in: result.standardOutput)
    }

    /// Shell z prostředí, jinak `/bin/zsh` — default macOS od Cataliny.
    private static var shell: URL {
        guard let shell = ProcessInfo.processInfo.environment["SHELL"], shell.hasPrefix("/") else {
            return URL(filePath: "/bin/zsh")
        }
        return URL(filePath: shell)
    }

    private static func directories(in path: String) -> [URL] {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
            .filter { !$0.isEmpty }
            .map { URL(filePath: String($0)) }
    }
}
