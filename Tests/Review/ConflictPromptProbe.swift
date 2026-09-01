import Foundation
import Testing

@testable import PRism

/// Sonda, ne test: vypíše **skutečný prompt a skutečné argumenty** jednoho kola slévání konfliktů
/// (#467) do souboru, aby se daly spustit na živém `claude` nad skutečným konfliktním rebasem.
///
/// **Proč sonda a ne test:** co v promptu být musí, tvrdí `ConflictCommandTests` výčtem. Tohle
/// odpovídá na jinou otázku — **jestli model s tím textem a s tou sadou povolení konflikt doopravdy
/// slije a vrátí čitelný účet**. To se v harnessu ověřit nedá: je to cizí model, síť a peníze.
///
/// Ověřit se to musí **spuštěním**, protože prompt je kontrakt se dvěma stranami naráz: brána
/// `Write(//…)` musí zápis do stromu pustit (a mimo něj ne) a odpověď musí projít
/// `ConflictCommand.parse`. Kdyby se rozešla kterákoli z těch stran, aplikace by konflikt nechala
/// rozdělaný a vypadalo by to jako slabý model.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR`. Bez nich se sonda nespustí a vypadá to, že prošla.
@Suite(
    "Sonda — prompt slévání konfliktů (#467)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct ConflictPromptProbe {
    @Test("Vypsat prompt a argumenty jednoho kola")
    func writesThePromptAndArguments() throws {
        let directory = URL(
            filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory()
        )
        let worktree = URL(
            filePath: ProcessInfo.processInfo.environment["PRISM_CONFLICT_WORKTREE"] ?? "/tmp/prism-conflict"
        )
        let files = (ProcessInfo.processInfo.environment["PRISM_CONFLICT_FILES"] ?? "f.txt")
            .split(separator: ",")
            .map(String.init)
        let base = ProcessInfo.processInfo.environment["PRISM_CONFLICT_BASE"] ?? "master"

        let prompt = Policy.conflictPrompt(files: files, base: base)
        try prompt.write(to: directory.appending(path: "conflict-prompt.txt"), atomically: true, encoding: .utf8)
        try ConflictCommand.arguments(prompt: prompt, worktree: worktree)
            .joined(separator: "\n")
            .write(to: directory.appending(path: "conflict-args.txt"), atomically: true, encoding: .utf8)
        print("SONDA prompt: \(directory.appending(path: "conflict-prompt.txt").path)")
        print("SONDA allowedTools: \(ConflictCommand.allowedTools(in: worktree))")
    }
}
