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

// MARK: - Zásuvka s terminálem (#459)

extension AppStore {
    /// `⌃\`` — vytáhne nebo schová zásuvku.
    ///
    /// **Schování nic nezabíjí.** Shell běží dál a při dalším vytažení je v něm to, co v něm bylo —
    /// je to tentýž vztah jako mezi sbaleným panelem nálezů a nálezy samotnými. Zabíjí se jedině
    /// zavřením záložky a ukončením aplikace, tedy tam, kde ten kontext doopravdy končí.
    ///
    /// Adresář se hledá **při otevírání**, ne v `body`: rozhodnutí, jestli se startuje v pracovním
    /// stromu review, nebo v klonu, potřebuje sáhnout na disk.
    func toggleTerminal() async {
        isTerminalOpen.toggle()
        guard isTerminalOpen else {
            // Schovaná zásuvka fokus mít nemůže. AppKit ho sice při odebrání plochy z okna sám
            // odevzdá, jenže to je pořadí, na které se nedá spolehnout — a příznak, který zůstane
            // viset, znamená okno s vypnutými zkratkami nad terminálem, který není vidět.
            isTerminalFocused = false
            return
        }
        guard let pr = activeTab.pullRequest else { return }
        await resolveTerminalDirectory(for: pr)
    }

    /// Je v tomhle okně zásuvka? `false` = **`▶` se nekreslí** (testovací store bez hostitele).
    ///
    /// Nekreslí se schválně, místo aby tiše spadlo zpátky na `Terminal.app` (#460): dvě různá
    /// chování pod jednou ikonou znamenají, že se nedá spolehnout ani na jedno. Je to tatáž úvaha
    /// jako u `Policy.terminalSession(of:)`, jen o druhou podmínku dál.
    var hasTerminalDrawer: Bool { terminals != nil }

    /// `▶` v hlavičce dráhy (#460) — pusť `claude --resume …` v **zásuvce**, ne v `Terminal.app`.
    ///
    /// Posílá se **celá `shellLine`**, tedy `cd '<strom>' && claude --resume <id>`, a je to tatáž
    /// řádka, jakou dostával `Terminal.app` od #453. Není to opatrnost navíc: zásuvka smí mít
    /// shell odjinud (otevřený `` ⌃` `` nad klonem, protože review ještě neběželo), a `claude
    /// --resume` hledá vlákno **podle adresáře**. `cd` v řádce je tedy jediné, co zaručí, že se
    /// session naváže i v shellu, který startoval jinde — a s `&&` zůstane po zmizelém stromu
    /// v zásuvce `cd: no such file or directory`, což je pravda, podle které se dá jednat.
    ///
    /// **Zásuvka se otevře vždycky, i když se nic neposlalo**: `busy` znamená, že v ní něco běží,
    /// a to je přesně ta věc, na kterou se má člověk podívat, než se rozhodne, co s tím.
    ///
    /// **Fokus si sama nebere.** Sebrat ho znamená sáhnout na první responder v tomtéž průchodu,
    /// ve kterém se plocha teprve staví (past z #184), a ověřit se to dá jedině na běžící
    /// aplikaci. Kliknout do zásuvky je proti tomu jeden klik.
    func resumeInDrawer(_ session: TerminalSession, for pr: PRIdentifier) {
        // Bez hostitele se `▶` nekreslí, takže sem se nedojde — a kdyby přece, nesmí se vymyslet
        // hláška o něčem, o co se nikdo nepokusil.
        guard let terminals else { return }
        let outcome = terminals.run(session.shellLine, for: pr, in: session.directory)
        // Cesta v hlavičce zásuvky se přepisuje **jen když řádka odešla**: po `busy` shell dál
        // stojí tam, kde stál, a popiska, která by tvrdila jinak, je horší než stará pravda.
        if outcome != .busy { terminalDirectories[pr] = session.directory }
        isTerminalOpen = true
        terminalFailure = Policy.resumeNotice(outcome)
    }

    /// Kde stojí shell toho PR. `nil` = v cache pro něj **není adresář**, a zásuvka to řekne.
    func terminalDirectory(for pr: PRIdentifier) -> URL? { terminalDirectories[pr] }

    /// Najde adresář, ve kterém se má shell pustit, a zapamatuje si ho.
    ///
    /// Volá se při otevření zásuvky a při přepnutí na jiný PR s otevřenou zásuvkou. **Přepisuje se
    /// pokaždé**: pracovní strom se posune s novým commitem a eviction ho umí sebrat, takže
    /// zapamatovaná cesta zestárne — a shell spuštěný ve smazané složce je horší než žádný.
    /// Adresář už běžícího shellu se tím nemění; ten si drží ten svůj, ve kterém startoval.
    func resolveTerminalDirectory(for pr: PRIdentifier) async {
        // Osa posledního review — z ní je cesta ke stromu, ve kterém `claude --resume` session
        // najde (vlákna se klíčují adresářem, viz `TerminalSession.directory`).
        let worktree = timelines(for: pr).compactMap(\.worktree).last
        let clone = checkoutPath(for: pr)
        let candidate = Policy.terminalWorkingDirectory(
            worktree: await existingDirectory(worktree),
            clone: await existingDirectory(clone)
        )
        terminalDirectories[pr] = candidate
    }

    /// Existuje ta složka? **Mimo hlavní vlákno** — je to sice jeden `stat`, ale disk umí zaseknout
    /// (síťový svazek, spící externí disk), a okno se kvůli hledání adresáře zaseknout nesmí.
    private func existingDirectory(_ url: URL?) async -> URL? {
        guard let url else { return nil }
        return await Task.detached {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: url.path(percentEncoded: false),
                isDirectory: &isDirectory
            )
            return exists && isDirectory.boolValue ? url : nil
        }.value
    }

    /// Kolik shellů právě běží — čte se při ukončení aplikace (#264).
    var runningTerminals: Int { terminals?.runningTerminals ?? 0 }

    /// Zabije shell toho pull requestu.
    ///
    /// Volá se ze zavření záložky: ta je jediné místo, kde kontext PR doopravdy končí — cesta ke
    /// checkoutu, nálezy i rozdělané review se dají otevřít znovu, kdežto shell by po zavřené
    /// záložce zůstal běžet bez okna, ve kterém by šel vidět.
    func stopTerminal(for pr: PRIdentifier) {
        terminals?.stopTerminal(for: pr)
        terminalStates[pr] = nil
        terminalDirectories[pr] = nil
    }

    /// Zabije všechny shelly, protože se zavírá aplikace (#264, #351).
    ///
    /// **Synchronní**, na rozdíl od `stopReviewsBeforeTermination()`: signál odchází přímo z téhle
    /// cesty (`kill(2)`), ne přes zrušení tasku, takže není na co čekat — a čekání by naopak dalo
    /// systému čas aplikaci zavřít dřív, než by signál odešel.
    func stopTerminalsBeforeTermination() {
        terminals?.stopAllTerminals()
    }
}
