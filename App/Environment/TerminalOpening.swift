import Foundation

/// Otevření příkazu v uživatelově terminálu (#453).
///
/// **Není to druhá cesta ven** (tvrdá podmínka č. 1), a je to jádro #453: terminál je **mimo
/// aplikaci**. Je to totéž, jako když si člověk příkaz vlepí sám — jen bez těch tří kroků.
/// Aplikace tu session neřídí a nic jejím jménem neodesílá; plnou moc má to okno tam, kde ho
/// člověk čeká, pod jeho jménem a s jeho `gh`. Uvnitř okna aplikace **žádný terminál nevzniká**,
/// takže `grep ReviewPublishing App/` vypisuje pořád týž seznam.
///
/// Za protokolem ze stejného důvodu jako zbytek `Environment/`: otevřené okno cizí aplikace se
/// v testu nedá ani vyrobit, ani vzít zpátky.
protocol TerminalOpening: Sendable {
    /// Pustí řádku v novém okně terminálu a dá ho dopředu.
    ///
    /// Vyhodí `TerminalError`, když se okno neotevřelo. **Nesmí selhat tiše**: výsledek téhle
    /// akce je vidět mimo aplikaci, takže spolknutá chyba vypadá jako tlačítko, které nic nedělá.
    func open(_ commandLine: String) async throws
}

/// Proč se okno neotevřelo.
///
/// **Jediný případ schválně**: co se pokazilo, ví systém líp než my (nepovolená automatizace,
/// chybějící `osascript`, Terminal, který neodpověděl), a naše rozdělení do kategorií by k tomu
/// nic nepřidalo — jen by rozpadlo text, který se stejně celý ukáže.
enum TerminalError: Error, Equatable {
    case failed(String)
}

/// `Terminal.app` přes `osascript`.
///
/// **Apple event, ne soubor, který se otevře.** Druhá cesta (dočasný `.command` v cache
/// a `open -a Terminal`) by po sobě nechávala skripty, které nikdo nemaže, a hlavně by
/// selhání schovala do Finderu — kdežto `osascript` skončí nenulově a řekne proč, takže se
/// dá splnit „selhání se hlásí, nespolkne“.
struct AppleScriptTerminal: TerminalOpening {
    /// Skript bere příkaz jako **argument (`argv`), ne vlepený do svého zdrojáku.**
    ///
    /// Je to jediné místo, kde se to dá pokazit nenápadně: uvozovka nebo zpětné lomítko v cestě
    /// k pracovnímu stromu by AppleScriptu rozbily řetězcový literál, takže by `do script` dostal
    /// něco jiného, než co se poskládalo — nebo by skript neprošel překladem a okno by se
    /// neotevřelo vůbec. S `argv` se text nikdy nestane kódem.
    ///
    /// `do script` **před** `activate`, aby se okno založilo dřív, než jde Terminal dopředu;
    /// obráceně na okamžik problikne jeho staré okno.
    static let script = """
        on run argv
            tell application "Terminal"
                do script (item 1 of argv)
                activate
            end tell
        end run
        """

    /// Systémová binárka na pevné cestě. `ToolPaths` je o `gh`, `git` a `claude` — tedy o tom, co
    /// si uživatel instaluje sám a co proto hledá `BinaryLocator`; `osascript` je součást macOS.
    static let osascript = URL(filePath: "/usr/bin/osascript")

    /// Strop je štědrý schválně: **napoprvé se macOS zeptá, jestli smí PRism ovládat Terminal**,
    /// a dokud člověk na ten dialog neodpoví, `osascript` čeká. Krátký limit by z první session
    /// udělal chybu, která zmizí sama, až se to zkusí podruhé.
    ///
    /// Hláška po jeho vypršení **číslo nejmenuje** — jinak by tady byly dvě hodnoty, které se
    /// tiše rozejdou při první změně konstanty.
    static let timeout: Duration = .seconds(120)

    let runner: any ProcessRunning

    func open(_ commandLine: String) async throws {
        let result: ProcessResult
        do {
            result = try await runner.run(
                Self.osascript,
                arguments: ["-e", Self.script, commandLine],
                timeout: Self.timeout
            )
        } catch ProcessError.timedOut {
            throw TerminalError.failed(
                "Terminal se v limitu neozval — zůstal nejspíš otevřený dotaz na povolení automatizace."
            )
        } catch {
            throw TerminalError.failed("`osascript` se nepodařilo spustit: \(error).")
        }
        guard result.exitCode == 0 else {
            // Když `osascript` mlčí, zbývá aspoň kód — prázdná věta by vypadala jako by se nic
            // nestalo, a přitom se okno neotevřelo.
            let reason = result.failureText
            throw TerminalError.failed(
                reason.isEmpty ? "`osascript` skončil kódem \(result.exitCode)." : reason
            )
        }
    }
}
