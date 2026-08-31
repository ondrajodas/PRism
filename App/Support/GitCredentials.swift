import Foundation

/// Jak se `gitu` řekne, kde vzít přihlášení — **na jednom místě** (#466).
///
/// Aplikace token nedrží (tvrdá podmínka č. 4), takže se přihlášení deleguje na `gh`. Helper se
/// předává jako `-c` u jednoho volání, ne přes `gh auth setup-git`: ten zapisuje do **globálního**
/// git configu uživatele, a do toho aplikace sahat nemá.
///
/// **Vlastní typ, protože to potřebují dva** — `GitRepoCheckout` (klon, fetch, worktree)
/// a `GitBranchPush` (jediný zápis do remote). Opsat to podruhé by znamenalo dvě místa, na kterých
/// se dá zapomenout na escapování, a jedno z nich by bylo zrovna to, které pushuje.
enum GitCredentials {
    /// Argumenty `-c credential.helper=…`. `gh` se volá **absolutní cestou**, protože helper
    /// spouští shell, který `PATH` z GUI aplikace nezdědil.
    static func configuration(gh: URL) -> [String] {
        // Helper spouští shell, takže cesta musí do apostrofů — a apostrof v ní se musí
        // odescapovat, jinak by je předčasně uzavřela. Cesta k `gh` sice pochází z preflightu,
        // ne od uživatele, ale skládat shellový příkaz bez escapování je zvyk, který se dřív nebo
        // později vymstí.
        let quoted = gh.path(percentEncoded: false).replacingOccurrences(of: "'", with: "'\\''")
        return ["-c", "credential.helper=!'\(quoted)' auth git-credential"]
    }

    /// Prostředí pro `git`. Bez `GIT_TERMINAL_PROMPT=0` by se `git` na chybějící heslo zeptal
    /// a čekal — podproces bez terminálu by na tom visel až do timeoutu.
    static let environment = ["GIT_TERMINAL_PROMPT": "0"]
}
