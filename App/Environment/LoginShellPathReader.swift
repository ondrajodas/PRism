import Foundation

/// Přečtení `PATH` z login shellu. Fallback pro binárky, které neleží na známém místě.
protocol ShellPathReading: Sendable {
    /// Složky z `PATH` login shellu. Prázdné, když se ho nepodařilo přečíst.
    func loginShellPath() async -> [URL]
}

/// Spustí login shell a nechá si vypsat `PATH`.
///
/// Login shell (`-lc`), protože doplňky `PATH` jako `eval $(brew shellenv)` leží
/// v `.zprofile` nebo `.zshenv`, a ty aplikace spuštěná z Finderu nikdy nevidí.
///
/// **Známé omezení: `.zshrc` se takhle nepřečte.** Neinteraktivní login shell čte `.zshenv`,
/// `.zprofile` a `.zlogin` — `.zshrc` patří interaktivním. Kdo má `PATH` doplněný jen tam
/// a binárku mimo známá místa, tomu tenhle fallback nepomůže.
///
/// Přidat `-i` se zkoušelo a **zahodilo**: interaktivní shell se z aplikace zasekl (jinak
/// než z terminálu, kde běží pod půl sekundy) a navíc ignoruje `SIGTERM`, takže ho vytáhla
/// až eskalace na `SIGKILL`. Za pokrytí `.zshrc` to není — zaseknutý start je horší selhání
/// než nenalezená binárka, kterou gate obrazovka umí vysvětlit.
///
/// Výstup se čte po **posledním neprázdném řádku**: `PATH` je to, co vypsal náš `echo`,
/// a startup soubory si do stdout klidně napíšou svoje.
///
/// Když shell selže nebo se zasekne, výsledkem je prázdný seznam. Binárka pak vyjde jako
/// nenalezená a gate to řekne — což je lepší než aby aplikace uvízla na startu.
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

    private static func directories(in output: String) -> [URL] {
        guard let path = lastNonEmptyLine(of: output) else { return [] }
        return path
            .split(separator: ":")
            .filter { !$0.isEmpty }
            .map { URL(filePath: String($0)) }
    }

    private static func lastNonEmptyLine(of output: String) -> String? {
        output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }
}
