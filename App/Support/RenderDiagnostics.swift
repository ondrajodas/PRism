import Foundation

/// Co okno **doopravdy dělá**, když spálí jádro (#361).
///
/// Kolo z #361 se v testu za tři pokusy nepodařilo vyrobit, kdežto na skutečném okně se stalo
/// třikrát. Jediný zdroj pravdy je tedy ta ztuhlá instance — a `sample` z ní ukáže, **kde** hlavní
/// vlákno je, ale ne **kolikrát** se co přeložilo a co si o další kolo řeklo. Tohle je ta druhá
/// polovina: počitadlo průchodů `body` po typech, počet kol runloopu a CPU hlavního vlákna, jeden
/// řádek za sekundu do souboru, který se dá poslat.
///
/// ## Jak se zapíná
///
/// `PRISM_DIAGNOSE=1` v prostředí procesu, čtené **jednou při startu** — nejjednodušeji
/// `./bin/run.sh --diagnose`. Tři důvody, proč proměnná prostředí a ne přepínač v nastavení:
///
/// 1. **Přepínač v nastavení je něco nového na obrazovce**, a to se v tomhle repu kreslí do mockupu
///    a schvaluje dřív, než na to vznikne issue. Diagnostika jednoho konkrétního hledání do produktu
///    nepatří; až se #361 zavře, má zmizet, a to se u proměnné dělá smazáním souboru.
/// 2. **Nedá se přepnout uprostřed sezení**, takže jeden soubor = jeden režim. Přepínač, který se dá
///    otočit v půlce, by dal záznam, ze kterého se nedá poznat, co v něm chybí.
/// 3. **Zapomenout se nedá.** Příznak umře s procesem a `bin/run.sh` restartuje aplikaci po každém
///    mergi, tedy několikrát denně — takže se diagnostika vypne sama, i když si na ni nikdo
///    nevzpomene. Ukazatel v okně by tuhle vlastnost neměl a stál by změnu vzhledu.
///
/// Že je zapnutá, je vidět na třech místech: `bin/run.sh` to vypíše při spuštění, aplikace na
/// stderr, a soubor začíná hlavičkou sezení (`Policy.diagnosticHeaderLine`). **A když se zapnout
/// nepovede** — typicky proto, že soubor už narazil na strop —, `start()` vrátí `false`, `current`
/// zůstane `nil` a důvod jde na stderr; `bin/run.sh --diagnose` to navíc pozná **dřív, než spustí
/// aplikaci**, a řekne, co s tím. „Zapnutá“ a „nic nezapisuje“ tedy nesplynou.
///
/// ## Zapisuje **vlastní vlákno**, ne observer hlavního runloopu
///
/// Do #391 řádky vypisoval observer na `beforeWaiting`, tedy hlavní vlákno samo. Ve čtvrtém
/// záchvatu (#361, 2026-08-20) se ukázalo, že takový nástroj se **v záchvatu vypne**: poslední
/// řádek je `11:01:31`, ztuhnutí trvalo do `11:02:53` a mezi tím není nic. Runloop se totiž do
/// stavu čekání **vůbec nedostane** — SwiftUI si transakce flushuje z `beforeWaiting` observeru
/// (`NSRunLoop.flushObservers`) a z toho se v tom kole nevrátí, takže náš observer s vyšším
/// pořadím nepřijde na řadu. Zbyl by z něj jen záznam toho, co bylo **předtím**.
///
/// Řádek proto zapisuje **zapisovací vlákno** (`Thread` + `Thread.sleep`) a hlavního vlákna se
/// dotýká jedině čtením: `threadCPUSeconds(of:)` nad jeho mach portem. Zaseknuté kolo se z toho
/// pozná na první pohled — `0 kol runloopu` a přitom celá sekunda CPU (viz
/// `Policy.diagnosticLine`).
///
/// ## Čím to nesmí být
///
/// - **Počitadlo není v observable stavu** (#252): je to obyčejná třída se zámkem, ne `@Observable`.
///   Zápis do stavu při každém průchodu tělem je přesně ta chyba, kterou tohle hledá.
/// - **Nic si neplánuje kolo na hlavním vlákně** (#350). Žádný `Timer` na hlavním runloopu, žádná
///   animace, žádný `requestUpdate`, žádný `DispatchQueue.main.async` — zapisovací vlákno je mimo
///   runloop okna a spí, takže si aplikace kvůli diagnostice neprobudí ani jedno kolo. Observer
///   runloopu zůstává, ale **jen jako počitadlo**: inkrement pod zámkem, žádné hodiny a žádný
///   disk.
/// - **`pass(_:)` nečte hodiny ani nesahá na disk.** Je to inkrement pod zámkem a nic jiného —
///   jediná věc, která se v tom kole opakuje tisíckrát za sekundu. Cena vypnuté diagnostiky je
///   načtení jednoho statického `Optional`u.
/// - **Nula se nezapisuje.** Řádek každou sekundu by nečinnou aplikací utopil to, co se hledá, a
///   soubor by rostl nad oknem, kde se nic nedělo. Rozhodnutí, co je „nic“, drží
///   `Policy.diagnosticLine` — a od #391 do něj patří i CPU, protože zaseknuté kolo je zrovna
///   ten stav, kde nejsou ani kola runloopu, ani průchody tělem.
///
/// Zbývá z toho jedno omezení: **záznam končí s procesem.** Zaseknutou aplikaci nemá kdo zavřít
/// jinak než rukou, a poslední rozepsaná sekunda se nezapíše — soubor se plní po celých úsecích.
final class RenderDiagnostics: @unchecked Sendable {
    /// Kdo právě sbírá. `nil` = diagnostika je vypnutá a `pass(_:)` nedělá nic.
    ///
    /// Nastavuje se **jednou při startu** (`start()`) a v testech, které si podstrčí vlastní
    /// instanci. Proto `nonisolated(unsafe)`: mimo tyhle dvě chvíle se to nemění, takže zámek na
    /// čtení by byl cena za souběh, ke kterému nedochází — a `pass(_:)` je to jedno místo, kde na
    /// ceně záleží.
    nonisolated(unsafe) static var current: RenderDiagnostics?

    /// Přečteno **jednou při startu procesu**, viz dokumentace typu.
    static let isEnabled = ProcessInfo.processInfo.environment["PRISM_DIAGNOSE"] == "1"

    /// Jeden průchod tělem `View`u. Volá se jako `let _ = RenderDiagnostics.pass(Self.self)` na
    /// začátku `body`.
    ///
    /// Jméno typu se skládá **jen u prvního průchodu** (`@autoclosure`): `String(describing:)` je
    /// reflexe a v tomhle kole by běžela tisíckrát za sekundu.
    static func pass<V>(_ type: V.Type) {
        current?.note(id: ObjectIdentifier(type), name: String(describing: type))
    }

    private let log: DiagnosticsLog
    private let zone: TimeZone
    /// Jak často se zapisuje řádek. Je to **cadence zapisovacího vlákna**, ne strop: co se za tu
    /// dobu nasbíralo, to je v řádku, a `elapsed` v něm je skutečně uplynulý čas.
    private let interval: TimeInterval
    /// Vlákno, jehož CPU se měří. Port se bere na **něm** (viz `threadCPUSeconds(of:)`), takže se
    /// instance musí postavit tam, kde se má měřit — v aplikaci na hlavním vlákně.
    private let watched: mach_port_t
    private let lock = NSLock()
    private var passes: [ObjectIdentifier: Int] = [:]
    private var names: [ObjectIdentifier: String] = [:]
    private var cycles = 0
    private var lastFlush: Date
    private var lastCPU: TimeInterval
    private var isStopped = false
    /// Vlastní reference na observer. Runloop si ho drží taky, ale životnost měřidla nemá
    /// záviset na tom, jak s ním zachází někdo jiný.
    private var observer: CFRunLoopObserver?

    /// `watching` je **port volajícího vlákna**, protože default se vyhodnocuje na místě volání:
    /// `start()` je `@MainActor`, takže se hlídá hlavní vlákno. Test si může podstrčit svůj.
    ///
    /// `cpu` je výchozí hodnota té řady, ze které se počítají rozdíly. `nil` znamená „vezmi ji
    /// z hlídaného vlákna“ — celá řada pak jde z jednoho zdroje. Testy si ji dosazují, aby se
    /// rozdíl v řádku dal napsat literálem.
    ///
    /// To `?? 0` na konci **není spolknutá chyba**: port se bere z vlákna, které o sebe právě
    /// požádalo, takže selhat může jedině neplatným portem — a ten selže i v zapisovacím vlákně,
    /// které se pak vypne dřív, než něco napíše. Nula se tedy nemá kde projevit.
    init(
        log: DiagnosticsLog,
        zone: TimeZone = .current,
        interval: TimeInterval = 1,
        now: Date = Date(),
        watching thread: mach_port_t = currentThreadPort(),
        cpu: TimeInterval? = nil
    ) {
        self.log = log
        self.zone = zone
        self.interval = interval
        watched = thread
        lastFlush = now
        lastCPU = cpu ?? threadCPUSeconds(of: thread) ?? 0
    }

    /// Zapne sbírání, pokud je `PRISM_DIAGNOSE=1`. Vrací, jestli se zapnulo.
    @MainActor @discardableResult static func start() -> Bool {
        guard isEnabled else { return false }
        let layout = CacheLayout.applicationSupport
        let diagnostics = RenderDiagnostics(
            log: DiagnosticsLog(url: layout.diagnosticsFile, zone: .current),
            now: Date()
        )
        // **Na hlavičce se to láme** (nález Copilota na #386). Když se nezapsala, nezapíše se ani nic
        // dalšího — typicky proto, že soubor už narazil na strop v minulém sezení. Zapnout se
        // v takovém případě nesmí: „diagnostika je zapnutá“ a „nic se nezapisuje“ jsou dva různé
        // stavy a mlčky splynout nemají, protože právě to `bin/run.sh` a dokumentace slibují.
        guard diagnostics.log.append(
            Policy.diagnosticHeaderLine(
                at: Date(),
                in: .current,
                bundle: layout.root.lastPathComponent,
                pid: ProcessInfo.processInfo.processIdentifier
            )
        ) else {
            FileHandle.standardError.write(Data("""
                PRism: diagnostika kreslení (#361) se NEZAPNULA — do \
                \(layout.diagnosticsFile.path) nejde zapsat (nejspíš vyčerpaný strop \
                \(DiagnosticsLog.byteLimit) B). Smaž ten soubor a spusť aplikaci znovu.\n
                """.utf8))
            return false
        }
        diagnostics.observeRunLoop()
        diagnostics.startWriting()
        current = diagnostics
        FileHandle.standardError.write(
            Data("PRism: diagnostika kreslení (#361) ZAPNUTÁ → \(layout.diagnosticsFile.path)\n".utf8)
        )
        return true
    }

    /// Přišel jeden průchod tělem.
    func note(id: ObjectIdentifier, name: @autoclosure () -> String) {
        lock.withLock {
            if passes[id] == nil { names[id] = name() }
            passes[id, default: 0] += 1
        }
    }

    /// Co se od posledního řádku nasbíralo. **Nic tím nenuluje** — je to čtení pro sondy, které
    /// počitadla vyhodnocují samy a řádek do souboru nepotřebují.
    func snapshot() -> [String: Int] {
        lock.withLock { namedPasses() }
    }

    /// Zahodí, co se nasbíralo. Pro sondy, které měří po úsecích: bez toho by druhý úsek nesl
    /// i to, co se stalo v prvním, a „po gestu se nic nepřekresluje“ by se z čísel nedalo
    /// přečíst. Jména typů zůstávají — jsou to konstanty, ne data.
    func reset() {
        lock.withLock { passes.removeAll(keepingCapacity: true) }
    }

    /// Počitadla po jménech typů. **Sčítá, nedosazuje**: dva typy se stejným jménem (jeden
    /// v aplikaci, druhý v testu) by `uniqueKeysWithValues` položily; tady se sečtou a řádek o tom
    /// řekne pravdu. Volá se **pod zámkem**.
    private func namedPasses() -> [String: Int] {
        passes.reduce(into: [:]) { out, entry in
            guard let name = names[entry.key] else { return }
            out[name, default: 0] += entry.value
        }
    }

    /// Proběhlo jedno kolo runloopu. **Jen inkrement pod zámkem** — žádné hodiny, žádný disk:
    /// tohle běží desítky až stovky krát za sekundu a v hořícím okně je to zrovna ta věc, která
    /// se dělat přestane.
    func noteCycle() {
        lock.withLock { cycles += 1 }
    }

    /// Uzavře úsek a zapíše za něj řádek. Vrací, jestli se ještě zapisuje — `false` znamená
    /// vyčerpaný strop nebo chybu zápisu, tedy že zapisovací vlákno může skončit.
    ///
    /// Volá to **zapisovací vlákno** (a testy, které si čas i CPU dosazují literálem). Průchody
    /// tělem, kola runloopu i CPU se nulují tady — bez toho by druhý řádek nesl i to, co se stalo
    /// v prvním.
    @discardableResult func flush(at moment: Date, cpu: TimeInterval) -> Bool {
        let line: String? = lock.withLock {
            let line = Policy.diagnosticLine(
                at: moment,
                in: zone,
                over: moment.timeIntervalSince(lastFlush),
                cycles: cycles,
                cpu: cpu - lastCPU,
                passes: namedPasses()
            )
            cycles = 0
            passes.removeAll(keepingCapacity: true)
            lastFlush = moment
            lastCPU = cpu
            return line
        }
        // **Nemám co říct** není konec zapisování: nečinná aplikace se zas rozjede.
        guard let line else { return true }
        return log.append(line)
    }

    /// Přestane zapisovat a odregistruje počitadlo kol. Pro sondy a testy — aplikace diagnostiku
    /// drží po celou dobu procesu, takže tam to nikdo nevolá.
    func stop() {
        lock.withLock { isStopped = true }
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = nil
        }
    }

    /// Zapisovací vlákno. **Tohle je celá oprava z #391**: kdo měří zaseknuté hlavní vlákno, nesmí
    /// na něm běžet.
    ///
    /// `Thread` + `Thread.sleep`, ne `Timer` ani `DispatchSourceTimer`: časovač potřebuje runloop
    /// nebo frontu, kdežto tady stačí vlákno, které se probouzí samo a nikomu nic neplánuje.
    /// Reference na sebe je **slabá**, takže se vlákno ukončí i tehdy, když se instance zahodí bez
    /// `stop()` (typicky v sondě) — bez toho by testovací instance zapisovala do konce běhu.
    func startWriting() {
        let interval = interval
        let thread = Thread { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: interval)
                guard let self, !lock.withLock({ isStopped }) else { return }
                // Bez čtení CPU by řádek tvrdil, že hlavní vlákno nic nedělalo — a to je zrovna
                // ta věta, kvůli které se tenhle soubor bere. Radši úsek přeskočit.
                guard let cpu = threadCPUSeconds(of: watched) else { return }
                guard flush(at: Date(), cpu: cpu) else { return }
            }
        }
        thread.name = "PRism.RenderDiagnostics"
        // `utility`, ne `userInitiated`: hlavní vlákno má přednost, protože se měří ono.
        thread.qualityOfService = .utility
        thread.start()
    }

    /// Počitadlo kol runloopu. **Žádné probuzení navíc**: `beforeWaiting` se ozve jedině tehdy,
    /// když runloop něco dělal a chystá se spát.
    ///
    /// Pořadí je vysoké schválně — SwiftUI si v `beforeWaiting` observeru flushuje transakce
    /// (`NSRunLoop.flushObservers`), takže s vyšším pořadím se počítá kolo, které už transakce
    /// proběhlo. **A právě proto se z observeru nezapisuje**: když se SwiftUI z toho flushe
    /// nevrátí, tenhle blok se nespustí a v souboru by nebylo nic (#361, čtvrtý záchvat).
    func observeRunLoop() {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            2_000_000
        ) { [weak self] _, _ in
            self?.noteCycle()
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }
}
