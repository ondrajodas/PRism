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
///
/// **Není `final`, a je to kvůli testům** (#478): co odsud odejde do procesu, se bez pty nedá
/// přečíst jinak než tím, že si testovací podtřída přepíše `send(source:data:)`.
class EmbeddedTerminalView: LocalProcessTerminalView {
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

    /// Drží zrovna terminál nějaký **cizí job v popředí**? (#460)
    ///
    /// Ptá se jádra na popředí pty (`tcgetpgrp`) — tedy přesně to, co dělá `kill()`, aby vědělo,
    /// koho zabít. **Není to ten pravidelný takt, kvůli kterému kapsle v hlavičce neukazuje běžící
    /// příkaz** (#459): ptá se to jedním voláním ve chvíli kliknutí na `▶`, ne v časovači, a
    /// odpovídá na tvrdou otázku „smí se sem poslat řádka?“, ne na popisku.
    ///
    /// Odpověď je podmínkou toho, aby `▶` nebylo nebezpečné: řádka poslaná do shellu je pro
    /// běžící program **vstup**, takže v běžícím `claude` by z `claude --resume …` byla odeslaná
    /// zpráva a ve `vi` posbírané příkazy. `false` u shellu, který neběží — tam není co přerušit.
    var hasForegroundJob: Bool {
        guard process.running else { return false }
        let descriptor = process.childfd
        guard descriptor >= 0 else { return false }
        let foreground = tcgetpgrp(descriptor)
        // `> 0` schválně, ze stejného důvodu jako v `kill()`: `tcgetpgrp` vrací `-1` u deskriptoru,
        // který není řídicí terminál, a `0` není platná skupina. Ani jedno není běžící job.
        return foreground > 0 && foreground != process.shellPid
    }

    // MARK: - Vstup

    /// Napíše řádku do shellu, jako by ji člověk napsal a odeslal `↵` (#460). `false` = neodešla.
    ///
    /// **`\r`, ne `\n`**: `↵` posílá přes terminál `CR` a ten musí umět zpracovat každý shell —
    /// v kanonickém režimu ho `ICRNL` převede na `NL`, v `ZLE` je navázaný na `accept-line`.
    /// Změřeno pty sondou, že obojí projde stejně (4 běhy z 4 u obou), takže se vybíralo podle
    /// pravidla, ne podle rozdílu.
    ///
    /// **Posílá se rovnou, i do shellu, který se právě spustil.** Změřeno (5 běhů z 5): bajty
    /// zapsané dřív, než `ZLE` naběhne, počká linková disciplína ve vstupním bufferu a shell je
    /// zpracuje na prvním promptu — příkaz tedy proběhne právě jednou. Cenou je, že se řádka
    /// jednou navíc odechuje **nad** promptem (linková disciplína ji echuje před tím, než si `ZLE`
    /// řádek překreslí). Čekat místo toho na první výstup shellu by tu ozvěnu ušetřilo, jenže by
    /// z toho byl stav navíc a nové selhání pro shell, který sám od sebe nic nevypíše — a to je
    /// horší než jeden řádek ozvěny.
    ///
    /// **Přes `send(txt:)` knihovny, ne přímo do `process`.** Ta cesta navíc srovná výřez na kurzor
    /// (`ensureCaretIsVisible`) a ohlásí terminálu vstup — bez toho by řádka odešla do shellu, ale
    /// zásuvka odrolovaná nahoru by zůstala stát a vypadalo by to, že se nic nestalo.
    ///
    /// **Deskriptor se kontroluje zvlášť od `running`**, a není to opatrnost: `LocalProcess` na
    /// `EOF` z pty nastaví `childfd = -1` a `running` nechá na `true`, dokud nedorazí událost
    /// o konci procesu. Zápis do `-1` by tiše selhal a volající by si myslel, že řádka odešla.
    @discardableResult
    func send(line: String) -> Bool {
        guard process.running, process.childfd >= 0 else { return false }
        send(txt: line + "\r")
        return true
    }

    // MARK: - Kolečko (#478)

    /// Řádek v bufferu, u kterého výřez zůstane, i když pod ním přiteče výstup. `nil` = jedeme
    /// s ním, jako to dělá knihovna sama.
    ///
    /// Existuje proto, že `SwiftTerm 1.11.2` má na tohle vlastní příznak (`Terminal.userScrolling`),
    /// ale **nikdy ho nenastaví** — čte se na třech místech a nezapisuje se do něj z jediného.
    /// Každý řádek, který přiteče, proto srovná výřez dolů (`buffer.yDisp = buffer.yBase`), a nad
    /// programem, který si spodek plochy překresluje sám, z toho je „kolečko nefunguje“: odrolovaný
    /// pohled se vrátí dřív, než ho stačí kdo přečíst. Měřeno na `claude` v zásuvce, viz
    /// `docs/testovani.md`.
    ///
    /// **Obyčejná vlastnost plochy, ne sledovaný stav** — mění se při každé otočce kolečka, takže
    /// v observable stavu by z ní byl přepočet okna na každý snímek rolování (#252, #472).
    private var pinnedRow: Int?

    /// Stojí výřez dole, tedy jede s výstupem?
    ///
    /// `canScroll` je v tom schválně: v alternativním bufferu a nad plochou bez historie **není co
    /// držet**, takže „dole“ je tam jediná pravdivá odpověď.
    private var followsOutput: Bool { !canScroll || scrollPosition >= 1 }

    /// Odběr kolečka, dokud je plocha v okně. `Any?` je neprůhledný token, který vydá `NSEvent`.
    private var wheelMonitor: Any?

    /// **`scrollWheel` se přebít nedá, a je to vlastnost knihovny, ne přehlédnutí.**
    /// `TerminalView` je sice `open`, ale tuhle metodu deklaruje jako `public override` — a `public`
    /// se z cizího modulu přepsat nesmí (`overriding non-open instance method outside of its
    /// defining module`, ověřeno překladačem). Událost se proto bere **dřív, než se k ploše
    /// dostane**, lokálním odběrem: ten je dokumentovaně volaný **před** doručením do okna, takže
    /// vrácené `nil` znamená, že se k `MacTerminalView.scrollWheel` událost vůbec nedostane.
    ///
    /// Zamítnuté bylo položit přes plochu podhled, který si o kolečko řekne v `hitTest`u:
    /// `hitTest` typ události nezná, takže „ber jen kolečko“ se tou cestou dá říct jedině přes
    /// `NSApp.currentEvent` — a ten je za hit testem jen **naposledy doručená** událost, tedy
    /// domněnka. Pořadí odběru je proti tomu popsané v dokumentaci.
    ///
    /// Odběr žije jen s oknem — plocha mimo okno nemá co zachytávat.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopWatchingWheel() } else { startWatchingWheel() }
    }

    private func startWatchingWheel() {
        guard wheelMonitor == nil else { return }
        // **Dovnitř `assumeIsolated` jde rozhodnutí, ven `Bool`.** Návratová hodnota musí být
        // `Sendable` a `NSEvent` není (`conformance of 'NSEvent' to 'Sendable' is unavailable`),
        // takže se událost zahazuje až tady venku. Odběr je volaný z doručování událostí, tedy
        // z hlavního vlákna — `assumeIsolated` je tvrzení o tom, ne převod fronty.
        //
        // **`?? false` je odpověď, ne zametená chyba**: `self` je slabé a zaniklá plocha nemá co
        // zachytávat, takže se událost propustí dál — přesně jako by odběr neexistoval.
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let taken = MainActor.assumeIsolated { self?.takeWheel(event) ?? false }
            return taken ? nil : event
        }
    }

    private func stopWatchingWheel() {
        guard let wheelMonitor else { return }
        NSEvent.removeMonitor(wheelMonitor)
        self.wheelMonitor = nil
    }

    /// Pojistka pro plochu, která zanikne i s oknem — tam `viewDidMoveToWindow(nil)` přijít nemusí.
    ///
    /// **`isolated deinit`, ne `MainActor.assumeIsolated`**: běžný `deinit` je nezaizolovaný, takže
    /// by na cizím vlákně `assumeIsolated` **spadl** a `NSEvent.removeMonitor` by na něm byl navíc
    /// volání AppKitu mimo hlavní vlákno. Izolovaný `deinit` si o hlavní actor řekne sám.
    isolated deinit {
        stopWatchingWheel()
    }

    /// Vezmi si tuhle otočku, pokud je naše. `false` = ať jde dál, kam měla.
    private func takeWheel(_ event: NSEvent) -> Bool {
        guard claimsWheel(event) else { return false }
        handle(wheel: event)
        return true
    }

    /// Je tahle otočka kolečka naše? Rozhoduje **poloha kurzoru**, ne fokus — tak se kolečko
    /// v macOS doručuje a tak se chová i knihovna.
    ///
    /// **Napřed obdélník, teprve pak hit test**, a není to mikrooptimalizace: odběr je na celý
    /// proces, takže tímhle projde **každá** otočka kolečka v aplikaci — i ta nad diffem, kde je
    /// cena projíždění měřená věc (#469). `visibleRect` je obdélníkové porovnání a odmítne skoro
    /// všechno; hit test celého okna se pustí teprve nad plochou.
    ///
    /// **`visibleRect`, ne `bounds`**: v zásuvce může být víc relací (#460) a ta neaktivní je
    /// v hierarchii pořád — s prázdným výřezem, takže si o kolečko neřekne. Hit test za tím pak
    /// odpoví na druhou půlku: neleží nad plochou ještě něco (popover, sheet)?
    private func claimsWheel(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        guard visibleRect.contains(convert(event.locationInWindow, from: nil)) else { return false }
        // `hitTest` bere bod v souřadnicích **nadřazeného** view, a nadřazený obsahovému je rám
        // okna — tedy `locationInWindow` beze změny. Převádět ho do souřadnic `contentView` je
        // tichá chyba: v okně s titulkem to sedne, s `fullSizeContentView` ne.
        guard let hit = window.contentView?.hitTest(event.locationInWindow) else { return false }
        return hit.isDescendant(of: self)
    }

    /// Kolečko — buď hlášení myši aplikaci, nebo vlastní historie.
    ///
    /// **Knihovna kolečko aplikaci nepředá nikdy** (`MacTerminalView.scrollWheel` roluje jen
    /// historii), přestože kliknutí a pohyb myši předává. Program, který si o myš řekl, tak
    /// dostával všechno kromě kolečka — tohle je ta chybějící půlka.
    ///
    /// **Ptá se při každé události**, ne jednou při vzniku plochy: `mouseMode` si mění aplikace pod
    /// námi. `allowMouseReporting` je vypínač knihovny (kvůli výběru textu myší) a platí i tady.
    ///
    /// Historii odroluje **tenhle kód, ne knihovna**, i když se nehlásí nic. Je to kvůli pořadí:
    /// zaklesnutí výřezu se musí zapsat **po** posunu, kdežto propuštěná událost by se rolovala až
    /// po návratu odsud a zapsala by se poloha před ním. `scrollUp`/`scrollDown` jsou veřejné
    /// a `Policy.terminalWheelLines` je táž křivka, jakou knihovna počítá sama (hlídá to test),
    /// takže se tím nemění chování — jen se to děje ve známém pořadí.
    ///
    /// **Internal, ne private, a je to kvůli testům** (#478): bez pty se tahle vidlička nedá projet
    /// jinak než zavoláním napřímo, protože odběr událostí testovací host nerozpohybuje.
    func handle(wheel event: NSEvent) {
        guard
            let report = Policy.terminalWheelReport(
                deltaY: event.deltaY,
                reportsMouse: allowMouseReporting && terminal.mouseMode != .off,
                rows: terminal.rows
            )
        else {
            scrollHistory(deltaY: event.deltaY)
            return
        }
        send(wheel: report, at: event)
    }

    /// Vlastní historie terminálu — to, co se dělo dosud, když aplikace o myš nestojí.
    private func scrollHistory(deltaY: CGFloat) {
        guard deltaY != 0, deltaY.isFinite else { return }
        let lines = Policy.terminalWheelLines(deltaY: deltaY, rows: terminal.rows)
        if deltaY > 0 { scrollUp(lines: lines) } else { scrollDown(lines: lines) }
        pinViewport()
    }

    /// Pošle hlášení kolečka na buňku pod kurzorem, `count`krát za sebou.
    ///
    /// **Tolikrát, o kolik řádků by se posunula historie** — hlášení nese jen „cvaklo“, takže
    /// rychlost je v počtu. Jedno na událost by znamenalo, že se v `claude` nebo `htop` roluje
    /// řádek po řádku, kdežto v shellu vedle po trojicích.
    private func send(wheel report: TerminalWheelReport, at event: NSEvent) {
        let modifiers = event.modifierFlags
        let buttonFlags = terminal.encodeButton(
            button: report.button,
            release: false,
            shift: modifiers.contains(.shift),
            meta: modifiers.contains(.option),
            control: modifiers.contains(.control)
        )
        let target = wheelTarget(of: event)
        for _ in 0..<report.count {
            terminal.sendEvent(
                buttonFlags: buttonFlags,
                x: target.column,
                y: target.row,
                pixelX: target.pixelX,
                pixelY: target.pixelY
            )
        }
    }

    /// Buňka pod kurzorem. Hlášení myši je **adresné** — aplikace s víc oblastmi (třeba `tmux`
    /// s panely) podle toho pozná, čeho se kolečko týká.
    private func wheelTarget(of event: NSEvent) -> (column: Int, row: Int, pixelX: Int, pixelY: Int) {
        let point = convert(event.locationInWindow, from: nil)
        let cell = cellSize
        let x = min(max(point.x, 0), bounds.width)
        let y = min(max(point.y, 0), bounds.height)
        return (
            column: min(Int(x / cell.width), max(0, terminal.cols - 1)),
            row: min(Int((bounds.height - y) / cell.height), max(0, terminal.rows - 1)),
            pixelX: Int(x),
            pixelY: Int(bounds.height - y)
        )
    }

    /// Rozměr jedné buňky.
    ///
    /// **Dopočítává se z `getOptimalFrameSize()`**, protože `cellDimension` knihovny je `internal`.
    /// Ta metoda vrací `buňka × (cols, rows)` a k šířce **přičítá posuvník** — a ten se proto měří
    /// na skutečném `NSScroller`u v podhledech, ne z konstanty: šířku si posuvník bere ze stylu,
    /// který si knihovna drží u sebe (taky `internal`), takže opsané číslo by se s ní umělo rozejít
    /// potichu. Dělit `bounds` by bylo o chlup jednodušší a **špatně**: řádků se vejde
    /// `floor(výška / buňka)`, takže zbytek pod posledním řádkem by se rozpustil do všech a spodní
    /// řádky by vycházely o jeden vedle.
    private var cellSize: CGSize {
        let optimal = getOptimalFrameSize().size
        let scroller = subviews.compactMap { $0 as? NSScroller }.first?.frame.width ?? 0
        return CGSize(
            width: max((optimal.width - scroller) / CGFloat(max(1, terminal.cols)), 1),
            height: max(optimal.height / CGFloat(max(1, terminal.rows)), 1)
        )
    }

    /// Zapamatuje si, kde výřez zůstal.
    private func pinViewport() {
        pinnedRow = Policy.terminalViewportPin(row: terminal.buffer.yDisp, atBottom: followsOutput)
    }

    /// Přepnutí mezi normálním a alternativním bufferem (`ESC[?1049h/l`) — **zaklesnutí padá**.
    ///
    /// Bez toho by zaklesnutí přežilo start celoobrazovkového TUI: `claude` má vlastní buffer, ve
    /// kterém se `yDisp` drží na nule, takže by se v něm zapamatovaný řádek neuplatnil — a ožil by
    /// až po jeho skončení, kdy je poloha z doby před ním dávno nesmyslná. Výřez by se tedy sám od
    /// sebe odrolil nahoru ve chvíli, kdy se člověk vrátil do shellu.
    override func bufferActivated(source: Terminal) {
        super.bufferActivated(source: source)
        pinnedRow = nil
    }

    /// Výstup z pty. Po nakrmení se výřez vrací tam, kde ho člověk nechal.
    ///
    /// **Až po `super`**, protože teprve to nakrmení výřezem hne. Vrací se jedině **dolů → nahoru**
    /// (`terminalViewportRewind`), takže rolování mezitím tahle cesta nikdy nepřebije.
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        let rewind = Policy.terminalViewportRewind(pinned: pinnedRow, current: terminal.buffer.yDisp)
        guard rewind > 0 else { return }
        scrollUp(lines: rewind)
    }

    /// Cokoli, co jde z plochy do procesu — klávesy, vložený text, řádka z `▶` i **odpověď emulátoru
    /// na dotaz aplikace**.
    ///
    /// Zaklesnutí se tu **přepočítá, ne zruší natvrdo**, a ten rozdíl je celý smysl: `send(data:)`
    /// srovná výřez na kurzor (`ensureCaretIsVisible`) **ještě před** tímhle voláním, takže po
    /// vstupu od člověka jsme dole a zaklesnutí padá — napsat něco znamená chtít vidět, co to
    /// udělá. Odpověď na dotaz (`DA`, `XTVERSION`) tou cestou nejde, takže odrolovaný pohled
    /// nechá být.
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        pinViewport()
        super.send(source: source, data: data)
    }

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
