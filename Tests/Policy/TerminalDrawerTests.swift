import Foundation
import Testing

@testable import PRism

/// Rozhodnutí kolem zásuvky s terminálem (#459).
///
/// Nejcennější je tady tvrzení o **klávesách**: dokud píše člověk do terminálu, nesmí se okenní
/// zkratka uplatnit. Rozbije se to potichu — `⌃W` uprostřed psaní zavře záložku a vypadá to jako
/// omyl uživatele, ne jako chyba aplikace. Testuje se proto **celý katalog výčtem**, ne jedna
/// vybraná kombinace: nová zkratka na `Control`u si tím vynutí, aby se o ní vědělo.
@Suite("Zásuvka s terminálem (#459)")
struct TerminalDrawerTests {
    // MARK: - Klávesy

    /// Vyčerpávající výčet nad katalogem: co nemá `⌘`, ustupuje terminálu.
    ///
    /// **Přes všechny kombinace, ne jen ty primární** — `⌃1` u sekce railu má alternativu `⌃+`
    /// a ta by se na české klávesnici uplatnila stejně.
    @Test("Zkratka bez ⌘ ustupuje terminálu, s ⌘ ne")
    func onlyCommandShortcutsSurviveTerminalFocus() {
        for action in Policy.windowShortcutActions {
            for combination in Policy.windowShortcut(action).combinations {
                let yields = Policy.shortcutYieldsToTerminal(action, combination)
                // `⌃\`` je **jediná** výjimka a je vypsaná přímo v tvrzení: kdyby se výjimkou
                // stala i druhá zkratka, spadne to tady, ne až v okně.
                let expected = !combination.modifiers.contains(.command) && action != .toggleTerminal
                #expect(
                    yields == expected,
                    "\(combination.display) u „\(Policy.windowShortcut(action).title)“"
                )
            }
        }
    }

    /// **`⌃\`` je výjimka, a je jediná.** Bez ní by se zásuvka s fokusem uvnitř nedala zavřít
    /// klávesnicí vůbec — tedy zrovna v té chvíli, kdy se zavírá nejčastěji.
    @Test("Zkratka terminálu neustupuje sama sobě")
    func theDrawerToggleNeverYields() {
        for combination in Policy.windowShortcut(.toggleTerminal).combinations {
            #expect(!Policy.shortcutYieldsToTerminal(.toggleTerminal, combination))
            // A pro jistotu obráceně: kdyby se `⌃\`` přesunula na `⌘`, tenhle test by o tom mlčel.
            #expect(combination.modifiers == .control)
        }
    }

    /// Jmenovitě to, o čem mluví poznámka 110 z návrhu. Vyčerpávající výčet výš by tuhle čtveřici
    /// pokryl taky — jenže by neřekl, **proč** zrovna ony, a to je na téhle zkratce to podstatné.
    @Test("⌃W, ⌃⇥, ⌃1 ani ⎋ se v terminálu neuplatní")
    func theKeysFromTheDesignNoteAllYield() {
        let yielding: [WindowShortcut.Action] = [
            .closeTab, .nextTab, .previousTab, .openSection(.queue), .backFromCommit,
            .nextFinding, .previousFinding,
        ]
        for action in yielding {
            let combination = Policy.windowShortcut(action).primary
            #expect(Policy.shortcutYieldsToTerminal(action, combination), "\(combination.display)")
        }
    }

    // MARK: - Výška

    @Test("Bez uložené výšky se zásuvka otevře na ideál")
    func noStoredHeightOpensAtTheIdeal() {
        #expect(Policy.terminalDrawerHeight(stored: 0, available: 900) == Policy.terminalDrawerIdealHeight)
    }

    /// Nula z `@AppStorage` znamená „nic uloženého“; nesmysl v `UserDefaults` (soubor se dá
    /// editovat rukou) taky.
    @Test("Nesmyslná uložená výška se bere jako neuložená")
    func nonsenseStoredHeightFallsBackToTheIdeal() {
        for stored in [-40.0, .nan, .infinity] {
            #expect(
                Policy.terminalDrawerHeight(stored: stored, available: 900)
                    == Policy.terminalDrawerIdealHeight
            )
        }
    }

    @Test("Uložená výška se použije, dokud se vejde")
    func storedHeightWins() {
        #expect(Policy.terminalDrawerHeight(stored: 420, available: 900) == 420)
    }

    /// **Nad diffem musí něco zůstat** — jinak zásuvka zruší jediný důvod, proč to není záložka.
    @Test("Zásuvka nezabere celý detail")
    func theDrawerLeavesRoomAboveIt() {
        let height = Policy.terminalDrawerHeight(stored: 5_000, available: 700)

        #expect(height == 700 - Policy.terminalDrawerContentFloor)
        #expect(height < 700)
    }

    /// Když se do okna nevejde ani podlaha, rozhoduje podlaha: zásuvka nesmí zmizet ani zdegenerovat
    /// na proužek jen proto, že si někdo stáhl okno.
    @Test("V nízkém okně vyhraje podlaha")
    func theFloorWinsInATinyWindow() {
        #expect(Policy.terminalDrawerHeight(stored: 400, available: 200) == Policy.terminalDrawerMinHeight)
        #expect(Policy.terminalDrawerHeight(stored: 400, available: 0) == 400)
    }

    /// Tažení dolů zmenšuje, nahoru zvětšuje — a obojí se počítá **z výšky na začátku tahu**.
    @Test("Tažení počítá z výšky na začátku tahu")
    func draggingStartsFromTheHeightAtTheStart() {
        #expect(Policy.terminalDrawerResize(from: 300, by: 50, available: 900) == 250)
        #expect(Policy.terminalDrawerResize(from: 300, by: -50, available: 900) == 350)
    }

    /// **Tvrzení o tom, co se nestane**: přetažení za strop se nesmí „nasčítat“, jinak by se
    /// zásuvka po dojetí ke hraně přestala vracet.
    @Test("Tažení za strop se ořízne, ne nasčítá")
    func draggingPastTheCeilingClamps() {
        let ceiling = 800 - Policy.terminalDrawerContentFloor

        #expect(Policy.terminalDrawerResize(from: 300, by: -5_000, available: 800) == ceiling)
        #expect(Policy.terminalDrawerResize(from: 300, by: 5_000, available: 800) == Policy.terminalDrawerMinHeight)
    }

    @Test("Nezměněná výška se neukládá")
    func anUnchangedHeightIsNotWritten() {
        #expect(Policy.terminalDrawerStoredHeight(stored: 300, measured: 300) == nil)
        #expect(Policy.terminalDrawerStoredHeight(stored: 300, measured: 300.4) == nil)
        #expect(Policy.terminalDrawerStoredHeight(stored: 300, measured: 340) == 340)
    }

    /// Pod podlahu se zapsat nedá — menší číslo je mezistav rozvržení, ne velikost, kterou si
    /// někdo natáhl.
    @Test("Pod podlahu se neukládá")
    func belowTheFloorIsNeverStored() {
        #expect(Policy.terminalDrawerStoredHeight(stored: 300, measured: 40) == nil)
        #expect(Policy.terminalDrawerStoredHeight(stored: 300, measured: .nan) == nil)
    }

    // MARK: - Kde shell startuje

    /// Pracovní strom review má přednost: je to jediný adresář, ve kterém `claude --resume`
    /// session **najde** (vlákna se klíčují cestou).
    @Test("Pracovní strom má přednost před klonem")
    func theWorktreeWinsOverTheClone() {
        let worktree = URL(filePath: "/cache/worktrees/cli/cli/42-abc")
        let clone = URL(filePath: "/cache/repos/cli/cli.git")

        #expect(Policy.terminalWorkingDirectory(worktree: worktree, clone: clone) == worktree)
        #expect(Policy.terminalWorkingDirectory(worktree: nil, clone: clone) == clone)
        #expect(Policy.terminalWorkingDirectory(worktree: nil, clone: nil) == nil)
    }

    /// **Zkracuje se jen celý prefix po hranici složky.** Bez té podmínky by `/Users/ondrej`
    /// vyšlo jako `~j`, což je cesta, která neexistuje.
    @Test("Cesta se zkracuje na ~ jen na hranici složky")
    func onlyAWholePathComponentIsAbbreviated() {
        let home = URL(filePath: "/Users/ondra")

        #expect(
            Policy.terminalDirectoryLabel(URL(filePath: "/Users/ondra/Library/x"), home: home)
                == "~/Library/x"
        )
        #expect(Policy.terminalDirectoryLabel(home, home: home) == "~")
        #expect(
            Policy.terminalDirectoryLabel(URL(filePath: "/Users/ondrej/x"), home: home)
                == "/Users/ondrej/x"
        )
        #expect(
            Policy.terminalDirectoryLabel(URL(filePath: "/tmp/x"), home: URL(filePath: "/"))
                == "/tmp/x"
        )
    }

    // MARK: - Co se spustí

    /// Pomlčka v `argv[0]` dělá login shell — bez ní by se v zásuvce nenašlo nic, co není
    /// v `/usr/bin`, protože `PATH` se schválně nedědí.
    @Test("Spouští se login shell z prostředí")
    func theLoginShellComesFromTheEnvironment() {
        let zsh = Policy.terminalShell(["SHELL": "/opt/homebrew/bin/fish"])

        #expect(zsh.executable == URL(filePath: "/opt/homebrew/bin/fish"))
        #expect(zsh.argv0 == "-fish")
    }

    /// Relativní `SHELL` se zahazuje: spustit `zsh` nalezené podle `PATH` aplikace znamená spustit
    /// něco jiného, než co si člověk nastavil.
    @Test("Bez použitelného SHELL se bere /bin/zsh")
    func aMissingShellFallsBackToZsh() {
        for environment in [[:], ["SHELL": ""], ["SHELL": "zsh"]] as [[String: String]] {
            #expect(Policy.terminalShell(environment) == Policy.fallbackShell)
        }
        #expect(Policy.fallbackShell.executable == URL(filePath: "/bin/zsh"))
        #expect(Policy.fallbackShell.argv0 == "-zsh")
    }

    /// **Tvrzení o tom, co se nestane**: `PATH` aplikace se do shellu nedostane. GUI aplikace ho má
    /// osekaný na systémové složky (proto v repu je `BinaryLocator`), takže předat ho dál znamená
    /// zásuvku bez Homebrew.
    @Test("PATH aplikace se do shellu nepředává")
    func theApplicationPathIsNeverInherited() {
        let variables = Policy.terminalEnvironment(["PATH": "/usr/bin:/bin", "HOME": "/Users/ondra"])

        #expect(!variables.contains { $0.hasPrefix("PATH=") })
        #expect(variables.contains("HOME=/Users/ondra"))
    }

    @Test("Terminál dostane xterm a UTF-8")
    func theTerminalGetsXtermAndUtf8() {
        let bare = Policy.terminalEnvironment([:])

        #expect(bare.contains("TERM=xterm-256color"))
        #expect(bare.contains("COLORTERM=truecolor"))
        // Bez UTF-8 locale sype `vi` sekvence, které emulátor přečte jako rozsypaný čaj.
        #expect(bare.contains("LANG=en_US.UTF-8"))
        #expect(Policy.terminalEnvironment(["LANG": "cs_CZ.UTF-8"]).contains("LANG=cs_CZ.UTF-8"))
    }

    // MARK: - Ukončení aplikace

    /// **Tvrzení o tom, co se nestane**: bez běžícího review i shellu se nemá nikdo na nic ptát.
    @Test("Když neběží nic, dialog nevznikne")
    func nothingRunningAsksNothing() {
        #expect(Policy.quitPrompt(reviews: 0, terminals: 0) == nil)
    }

    /// Věty se liší podle toho, co běží — „Běží 2 věci“ nedává důvod kliknout na Zpět.
    @Test("Dotaz pojmenuje, co běží")
    func thePromptNamesWhatIsRunning() {
        #expect(Policy.quitPrompt(reviews: 1, terminals: 0)?.title == "Běží review. Ukončit teď?")
        #expect(Policy.quitPrompt(reviews: 3, terminals: 0)?.title == "Běží 3 review. Ukončit teď?")
        #expect(
            Policy.quitPrompt(reviews: 0, terminals: 1)?.title
                == "V terminálu něco běží. Ukončit teď?"
        )
        // **Počet terminálů se nevypisuje**: rozhoduje se o tom, jestli ukončit, ne kolikrát —
        // a „ve 2 terminálech“ by si kvůli tomu údaji říkalo o skloňování předložky.
        #expect(
            Policy.quitPrompt(reviews: 0, terminals: 2)?.title
                == "V terminálu něco běží. Ukončit teď?"
        )
        #expect(
            Policy.quitPrompt(reviews: 2, terminals: 1)?.title
                == "Běží 2 review a v terminálu něco běží. Ukončit teď?"
        )
    }

    /// **Text nesmí slibovat víc, než co data unesou.** U review se dá dotáhnout, co reviewer
    /// nahlásil; u shellu se neukládá nic, a musí to být napsané.
    @Test("Detail mluví o obojím jen tehdy, když obojí běží")
    func theDetailOnlyMentionsWhatRuns() {
        let reviewsOnly = Policy.quitPrompt(reviews: 1, terminals: 0)?.detail ?? ""
        let shellsOnly = Policy.quitPrompt(reviews: 0, terminals: 1)?.detail ?? ""
        let both = Policy.quitPrompt(reviews: 1, terminals: 1)?.detail ?? ""

        #expect(reviewsOnly.contains("reviewer nahlásil"))
        #expect(!reviewsOnly.contains("Shell"))
        #expect(shellsOnly.contains("nikam neukládá"))
        #expect(!shellsOnly.contains("reviewer nahlásil"))
        #expect(both.contains("reviewer nahlásil"))
        #expect(both.contains("nikam neukládá"))
    }

    // MARK: - Co se řekne po `▶` (#460)

    /// **Nejcennější tvrzení téhle části**: nad povedeným koncem se mlčí. Hláška „session se
    /// pustila“ nad zásuvkou, ve které je ta session vidět, je text navíc nad tím, co má člověk
    /// před očima — a stavový řádek se tím naučí ignorovat.
    @Test("Povedený konec nic nehlásí")
    func aSuccessSaysNothing() {
        #expect(Policy.resumeNotice(.started, in: "php-review") == nil)
        #expect(Policy.resumeNotice(.sent, in: "php-review") == nil)
    }

    /// Obojí je stav, ve kterém se **v zásuvce nic nezměnilo** — bez věty by `▶` vypadalo jako
    /// tlačítko, které nic nedělá. Vyjmenované zvlášť, protože se s každým naloží jinak.
    @Test("Neposlaná řádka se řekne, a s důvodem")
    func aRefusalIsSpelledOut() throws {
        let busy = try #require(Policy.resumeNotice(.busy, in: "php-review"))
        #expect(busy.contains("něco běží"))
        // **Věta jmenuje relaci** (#460): zásuvka jich drží víc, takže „něco běží“ bez jména by
        // nutilo hledat, ve které.
        #expect(busy.contains("php-review"))
        // A říká to podstatnější: z odmítnutí se od #460 **nestává slepá ulička**, protože se
        // zásuvka na tu relaci přepne.
        #expect(busy.contains("přepnutá"))

        let noShell = try #require(Policy.resumeNotice(.noShell, in: "php-review"))
        #expect(noShell.contains("nepodařilo spustit"))
        #expect(noShell.contains("php-review"))
        // Důvod se **nehádá** — sem se dojde, až když selhal i `/bin/zsh`.
        #expect(!noShell.contains("SHELL"))
    }
}
