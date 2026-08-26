import Foundation

/// Uzávorkování hodnoty pro shell. Jedno místo, protože se to plete **potichu**: apostrof
/// uvnitř hodnoty uzávorkování předčasně uzavře a příkaz se pak vloží rozstřelený — a pozná
/// se to teprve tehdy, až ho někdo spustí.
///
/// Vzniklo u #453 jako **druhé** místo, kde se to potřebuje: `ClaudeCommand.shellCommand` skládá
/// příkaz pro `Zkopírovat příkaz` a `TerminalSession.shellLine` řádek `cd … && claude --resume …`
/// pro Terminál. Obojí jsou příkazy, které pak někdo doopravdy spustí, takže se rozejít nesmí.
///
/// **Escapování uvnitř už uzávorkovaného řetězce sem nepatří**, a je to jiná operace:
/// `ClaudeCommand.environment` i `GitRepoCheckout` skládají hodnotu, kterou do apostrofů
/// zabalí až vrstva nad nimi (`!'<cesta>' auth git-credential`), takže by ji tahle funkce
/// uzávorkovala podruhé.
enum ShellQuoting {
    /// Hodnota jako jeden argument pro shell.
    ///
    /// Apostrof se v apostrofech uzavírá a otevírá znovu (`'\''`) — je to jediný způsob, jak ho
    /// do jednoduchých uvozovek dostat.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Cesta jako jeden argument. Bere se **bez procentového kódování** — do shellu jde ta
    /// cesta, kterou má soubor na disku, ne její URL podoba.
    static func quoted(_ url: URL) -> String {
        quoted(url.path(percentEncoded: false))
    }
}
