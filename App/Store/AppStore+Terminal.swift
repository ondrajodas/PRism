import Foundation

extension AppStore {
    /// Otevření session v `Terminal.app` (#453). **Od #460 to v aplikaci nikdo nevolá.**
    ///
    /// Drží se jako **záloha, ne jako mrtvý kód**, a je to zapsané rozhodnutí (viz specifikace,
    /// *Osud `AppleScriptTerminal`*): `▶` odteď míří do zásuvky (`resumeInDrawer(_:for:)`), jenže
    /// shell v zásuvce se **zavřením aplikace zabije** (#264, #459) a PRism se restartuje po
    /// každém mergi — kdežto okno `Terminal.app` session přežije. Jestli to v praxi chybí, se
    /// pozná jedině používáním, takže se ta cesta smaže teprve tehdy, až bude jasné, že ne.
    /// Až ten čas přijde, jde ven celá naráz: `TerminalOpening`, `AppleScriptTerminal`,
    /// `AppStore.terminal`, tahle metoda, `FakeTerminal`, `AppStoreTerminalTests`
    /// a `NSAppleEventsUsageDescription` z `Info.plist`.
    ///
    /// **Uvnitř aplikace tím nic nevzniká** a tvrdá podmínka č. 1 se nemění: složí se řádka pro
    /// shell a předá se `Terminal.app`. Co se v tom okně bude dít dál, aplikace neví a neřídí —
    /// je to totéž, jako když si člověk příkaz vlepí sám.
    func openInTerminal(_ session: TerminalSession) async {
        // Bez závislosti se nic nestane. V aplikaci je vždycky (`init(toolPaths:)`); tohle je ta
        // půlka testů, která terminál nedostane — a ty si tlačítko ani nekreslí.
        guard let terminal else { return }
        do {
            try await terminal.open(session.shellLine)
            // Až po úspěchu: hláška po nepovedeném pokusu má zmizet teprve tehdy, když se to
            // doopravdy povedlo, ne při dalším kliknutí.
            terminalFailure = nil
        } catch {
            terminalFailure = Self.terminalFailureText(error)
        }
    }

    /// Věta do stavového řádku.
    ///
    /// Důvod se **opisuje doslova** z toho, co řekl systém (`Not authorized to send Apple events
    /// to Terminal.`, `-1743`): je to jediné, podle čeho se dá jednat, a naše převyprávění by
    /// muselo hádat, který z důvodů to byl.
    private static func terminalFailureText(_ error: any Error) -> String {
        let reason = switch error {
        case TerminalError.failed(let text): text
        // Sem se nedojde přes `AppleScriptTerminal`, který jiný typ nevyhazuje — je to pojistka
        // pro jinou implementaci protokolu, ne mrtvá větev: mlčet o chybě je horší než ji vypsat
        // syrovou.
        default: "\(error)"
        }
        return "Session se nepodařilo otevřít v Terminálu: \(reason)"
    }
}
