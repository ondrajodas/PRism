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
/// stderr, a soubor začíná hlavičkou sezení (`Policy.diagnosticHeaderLine`).
///
/// ## Čím to nesmí být
///
/// - **Počitadlo není v observable stavu** (#252): je to obyčejná třída se zámkem, ne `@Observable`.
///   Zápis do stavu při každém průchodu tělem je přesně ta chyba, kterou tohle hledá.
/// - **Nic si neplánuje kolo** (#350). Žádný `Timer`, žádná animace, žádný `requestUpdate`. Řádek se
///   vypisuje z **observeru runloopu**, tedy jedině tehdy, když už runloop běží — diagnostika si
///   nevyžádá ani jedno probuzení navíc. Ticho v souboru proto znamená, že se runloop **vůbec
///   neprobudil**; aplikace se ale sama probouzí kvůli pollingu, takže v běžném provozu chodí
///   levné řádky (jednotky kol, jednotky milisekund CPU) a strop se vyčerpá řádově za den.
/// - **`pass(_:)` nečte hodiny ani nesahá na disk.** Je to inkrement pod zámkem a nic jiného —
///   jediná věc, která se v tom kole opakuje tisíckrát za sekundu. Cena vypnuté diagnostiky je
///   načtení jednoho statického `Optional`u.
///
/// Plyne z toho jedno **omezení, které je potřeba znát**: kdyby se hlavní vlákno zaseklo tak, že se
/// runloop nikdy nevrátí do observeru, nezapíše se nic. Vzorky z #361 tuhle možnost vylučují (v pěti
/// sekundách je `flushObservers` tisíce vzorků, tedy tisíce kol), ale prázdný soubor u hořícího okna
/// **není chyba diagnostiky, je to nález**.
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
    private let lock = NSLock()
    private var passes: [ObjectIdentifier: Int] = [:]
    private var names: [ObjectIdentifier: String] = [:]
    private var cycles = 0
    private var lastFlush: Date
    private var lastCPU: TimeInterval
    /// Vlastní reference na observer. Runloop si ho drží taky, ale životnost měřidla nemá
    /// záviset na tom, jak s ním zachází někdo jiný.
    private var observer: CFRunLoopObserver?

    init(log: DiagnosticsLog, zone: TimeZone = .current, now: Date = Date(), cpu: TimeInterval = 0) {
        self.log = log
        self.zone = zone
        lastFlush = now
        lastCPU = cpu
    }

    /// Zapne sbírání, pokud je `PRISM_DIAGNOSE=1`. Vrací, jestli se zapnulo.
    @MainActor @discardableResult static func start() -> Bool {
        guard isEnabled else { return false }
        let layout = CacheLayout.applicationSupport
        let diagnostics = RenderDiagnostics(
            log: DiagnosticsLog(url: layout.diagnosticsFile, zone: .current),
            now: Date(),
            cpu: threadCPUSeconds()
        )
        diagnostics.log.append(
            Policy.diagnosticHeaderLine(
                at: Date(),
                in: .current,
                bundle: layout.root.lastPathComponent,
                pid: ProcessInfo.processInfo.processIdentifier
            )
        )
        diagnostics.observeRunLoop()
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

    /// Proběhlo kolo runloopu. Když od posledního řádku uplynula sekunda, řádek se zapíše
    /// a počitadla se vynulují.
    func cycle(at moment: Date, cpu: TimeInterval) {
        let line: String? = lock.withLock {
            cycles += 1
            let elapsed = moment.timeIntervalSince(lastFlush)
            guard elapsed >= 1 else { return nil }
            let line = Policy.diagnosticLine(
                at: moment,
                in: zone,
                over: elapsed,
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
        guard let line else { return }
        log.append(line)
    }

    /// Observer runloopu, ze kterého se řádky vypisují. **Žádné probuzení navíc**: `beforeWaiting`
    /// se ozve jedině tehdy, když runloop něco dělal a chystá se spát.
    ///
    /// Pořadí je vysoké schválně — SwiftUI si v `beforeWaiting` observeru flushuje transakce
    /// (`NSRunLoop.flushObservers`), takže s vyšším pořadím se čte stav **po** nich a průchody těla
    /// z toho kola se do řádku vejdou.
    private func observeRunLoop() {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            2_000_000
        ) { [weak self] _, _ in
            self?.cycle(at: Date(), cpu: threadCPUSeconds())
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }
}
