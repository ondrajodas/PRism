import AppKit
import Darwin
import SwiftTerm

/// Plocha vestavěného terminálu (#459) — `SwiftTerm` obarvený podle návrhu a se dvěma věcmi navíc,
/// které knihovna dělat nemá: hlásí fokus a umí ten shell **doopravdy zabít**.
///
/// **Proč knihovna a ne vlastní renderer** (záznam rozhodnutí je i ve specifikaci): `claude` je
/// celoobrazovkové TUI — kurzor, barvy, alternativní buffer, překreslování při změně velikosti —,
/// takže pod tím musí být pty a VT/xterm emulace. Napsat ji je řádově víc práce než celý zbytek
/// tohohle issue a bylo by to jediné místo v repu, kde by se chyba projevila jako „vypadá to
/// rozbitě“ bez toho, aby šlo říct proč.
///
/// `LocalProcessTerminalView` si `terminalDelegate` nastavuje sám a proxuje ho do `processDelegate`
/// — proto se do prvního nesahá; přepsat ho znamená rozbít vnitřek knihovny (píše to v její
/// dokumentaci).
final class EmbeddedTerminalView: LocalProcessTerminalView {
    /// Komu se hlásí fokus. Na něm stojí to, že se okenní zkratky na `Control` neuplatní
    /// (`Policy.shortcutYieldsToTerminal`).
    var focusChanged: (@MainActor (Bool) -> Void)?

    /// Komu se hlásí, že shell skončil — sám od sebe (`exit`) i po našem `SIGKILL`u.
    ///
    /// Konec chodí z `DispatchSource.makeProcessSource` na hlavní frontě (`LocalProcess` si ji bere
    /// jako výchozí), takže se odsud smí sahat na stav okna.
    var stateChanged: (@MainActor (TerminalRunState) -> Void)?

    /// Běží pod námi ještě něco?
    var isRunning: Bool { process.running }

    /// PID shellu, dokud běží. `nil` je „nemáme co zabíjet ani co zapisovat do `sessions.json`“.
    var shellPid: pid_t? { process.running && process.shellPid > 0 ? process.shellPid : nil }

    // MARK: - Start

    /// Pustí login shell v tom adresáři.
    ///
    /// **Pracovní adresář se předává procesu, nesází se do příkazu.** `cd <cesta> && zsh` by
    /// znamenalo uvozovkovat cestu do shellu, a přesně tam se dělají chyby, kvůli kterým skončí
    /// terminál v domovské složce (viz `TerminalSession.shellLine`, kde se ta řádka skládat musí,
    /// protože ji čte cizí `Terminal.app`).
    ///
    /// **Značka do `sessions.json` (#351) je součást startu, ne kosmetika**: zabitá aplikace nemá
    /// kde spustit úklid, takže osiřelý shell — a v něm `claude`, který platí tokeny — by běžel dál
    /// pod `launchd`. Zapisuje se identita `(pid, startedAt)`, kterou si registr přečte z jádra sám.
    /// **Binárka se před spuštěním ověří, a není to opatrnost.** `SwiftTerm` staví na `forkpty`
    /// a v potomkovi po neúspěšném `execve` **nedělá nic** — `Pty.fork(andExec:)` se z něj vrátí
    /// stejně jako v rodiči, takže by dál běžela **kopie naší aplikace** jako podproces sebe sama.
    /// `SHELL` je přitom uživatelská proměnná a binárka z ní umí zmizet (odinstalovaný `fish`).
    /// Když neexistuje, bere se `/bin/zsh` — přijít o svůj shell je pořád lepší než přijít
    /// o zásuvku a mít v tabulce procesů dvojníka.
    func start(in directory: URL) {
        guard !process.running else { return }
        let configured = Policy.terminalShell(ProcessInfo.processInfo.environment)
        let isExecutable = FileManager.default.isExecutableFile(
            atPath: configured.executable.path(percentEncoded: false)
        )
        let command = isExecutable ? configured : Policy.fallbackShell
        startProcess(
            executable: command.executable.path(percentEncoded: false),
            args: [],
            environment: Policy.terminalEnvironment(ProcessInfo.processInfo.environment),
            execName: command.argv0,
            currentDirectory: directory.path(percentEncoded: false)
        )
        // **Stav se hlásí podle toho, co se doopravdy stalo, ne podle toho, že se o to někdo
        // pokusil** (nález Copilota). `SHELL` je uživatelská proměnná, takže může ukazovat na
        // binárku, která neexistuje — `fork`/`exec` pak selže a `running` zůstane `false`.
        // Bezpodmínečné `.running` by v hlavičce zásuvky svítilo „běží“ nad prázdnou plochou,
        // ve které nic není a nikdy nebude.
        guard let shellPid else {
            stateChanged?(.exited(code: nil))
            return
        }
        RunningSessions.shared.remember(pid: shellPid)
        stateChanged?(.running)
    }

    // MARK: - Konec

    /// Zabije, co v zásuvce běží — **`SIGKILL`, a ne jen shellu**.
    ///
    /// Knihovní `terminate()` posílá `SIGTERM` samotnému shellu a to na tenhle závazek nestačí
    /// (#264, #351) ze dvou důvodů. Zaprvé `SIGTERM` se dá ignorovat. Zadruhé — a to je to
    /// podstatnější — **shell není to, co běží**: `claude` spuštěný v interaktivním shellu dostane
    /// vlastní process group (job control), takže by ho signál poslaný shellu minul a osiřel by na
    /// `launchd` úplně stejně, jako to popisuje #351.
    ///
    /// Zabíjí se proto **popředí pty** (`tcgetpgrp`, tedy ten job, který zrovna drží terminál) a až
    /// pak shell. V tomhle pořadí schválně: po smrti shellu se pty zavírá a `tcgetpgrp` už nemá
    /// koho vrátit.
    ///
    /// `terminate()` se volá i tak — je to jediná cesta, jak knihovna zavře `DispatchIO` a
    /// deskriptor; bez něj by zůstal viset otevřený pty.
    func kill() {
        guard process.running else { return }
        let descriptor = process.childfd
        let shell = process.shellPid
        if descriptor >= 0 {
            let foreground = tcgetpgrp(descriptor)
            // `> 0` schválně: `tcgetpgrp` vrací `-1`, když deskriptor není řídicí terminál, a `0`
            // není platná skupina. `killpg(0, …)` by přitom znamenalo **naši vlastní** skupinu,
            // tedy zabít aplikaci.
            if foreground > 0, foreground != shell { _ = killpg(foreground, SIGKILL) }
        }
        if shell > 0 { _ = Darwin.kill(shell, SIGKILL) }
        // Značka se maže tady, ne až v `processTerminated`: to zavolá knihovna asynchronně, kdežto
        // při ukončení aplikace už žádné další kolo runloopu nemusí přijít.
        if shell > 0 { RunningSessions.shared.forget(pid: shell) }
        process.terminate()
    }

    /// Shell skončil — `exit`, pád, nebo náš `SIGKILL`.
    ///
    /// Značka v `sessions.json` se maže i tady, ne jen v `kill()`: shell umí skončit sám (`exit`,
    /// `⌃D`) a nechaná značka by při dalším startu ukázala na PID, který mezitím dostal někdo jiný.
    /// Zabít cizí proces `Policy.orphanVerdict` sice nedovolí (identita se neshoduje), ale nechávat
    /// v souboru řádky, o kterých se ví, že neplatí, je stav, na který se dá zapomenout.
    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        super.processTerminated(source, exitCode: exitCode)
        if source.shellPid > 0 { RunningSessions.shared.forget(pid: source.shellPid) }
        stateChanged?(.exited(code: exitCode))
    }

    // MARK: - Fokus

    /// Naposledy ohlášený fokus. Existuje kvůli tomu, aby se do stavu okna nepsalo bezpodmínečně
    /// (#358): setter `hasFocus` volá knihovna i tam, kde se hodnota nemění, a každý takový zápis
    /// by zneplatnil tělo okna.
    private var reportedFocus = false

    /// Fokus se hlásí ven, protože na něm stojí poznámka 110 z návrhu: dokud je zásuvka aktivní,
    /// okenní zkratky bez `⌘` se neuplatní. Rozhodnutí, které to jsou, drží `Policy`; tohle je jen
    /// místo, kde se pozná „teď“.
    ///
    /// **Přes `hasFocus`, ne přes `becomeFirstResponder`**: knihovna má ty dvě metody `public`, ne
    /// `open`, takže je z jiného modulu přepsat nejde (ověřeno překladačem). `hasFocus` je `open`
    /// a knihovna ho z obou nastavuje, takže je to tentýž okamžik.
    override var hasFocus: Bool {
        get { super.hasFocus }
        set {
            super.hasFocus = newValue
            guard newValue != reportedFocus else { return }
            reportedFocus = newValue
            focusChanged?(newValue)
        }
    }

    // MARK: - Barvy

    /// Barvy z palety, ne ze systému.
    ///
    /// **Musí se dát nasadit znovu**, protože `SwiftTerm` si dynamickou `NSColor` převede na svoje
    /// hodnoty **ve chvíli přiřazení** — od té chvíle o přepnutí režimu neví. Aplikace přitom režim
    /// umí vynutit v railu (#278), takže by zásuvka po přepnutí zůstala v barvách toho předchozího.
    ///
    /// Vyhodnocuje se uvnitř `performAsCurrentDrawingAppearance`, jinak by se dynamická barva
    /// rozhodla podle toho, co je zrovna `NSAppearance.current` — což při volání mimo kreslení není
    /// nutně vzhled tohohle view.
    func applyPalette() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            nativeBackgroundColor = NSColor(Palette.background)
            nativeForegroundColor = NSColor(Palette.ink)
            caretColor = NSColor(Palette.accent)
            selectedTextBackgroundColor = NSColor(Palette.accentWeak)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }
}
