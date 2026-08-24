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
/// - **Klid se nezapisuje po sekundách.** Řádek každou sekundu by nečinnou aplikací utopil to, co se
///   hledá, a soubor by rostl nad oknem, kde se nic nedělo — změřeno nad záznamem z provozu: 89 %
///   hlavních řádků a 60 % objemu souboru. Rozhodnutí, co je „klid“, drží `Policy.diagnosticLine`
///   (od #391 v něm je i CPU, protože zaseknuté kolo je zrovna ten stav, kde nejsou ani kola
///   runloopu, ani průchody tělem) a klidné úseky se sčítají do **minutového souhrnu** (#412).
///
/// ## Sezení má svůj soubor
///
/// Dosavadní záznam se při startu uloží vedle (`DiagnosticsArchive`), takže strop 8 MB platí na
/// **tohle** sezení. Do #412 se přípisovalo a strop platil na soubor napříč sezeními — naměřeno, že
/// záznam narazil na strop ve 4:01 a dalších 42 hodin aplikace běžela bez záznamu, tedy zrovna
/// v tom, na co nástroj je.
///
/// Zbývá z toho jedno omezení: **záznam končí s procesem.** Zaseknutou aplikaci nemá kdo zavřít
/// jinak než rukou, a poslední rozepsaná sekunda se nezapíše — soubor se plní po celých úsecích.
/// Od #412 k tomu patří i nasbíraný klid: z konce chybí až minuta, ve které se nic nedělo.
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

    /// Kolik vzorků evaluačního zásobníku se smí vzít za jeden úsek (#361).
    ///
    /// Osm je kompromis mezi dvěma věcmi, které jdou proti sobě: jeden vzorek za sekundu je
    /// **náhodný bod** v kole, které za tu sekundu proběhne milionkrát, kdežto z osmi je už
    /// histogram, ze kterého se pozná, jestli se kořen opakuje. A víc už se nevejde do souboru:
    /// v záznamu je za úsek souhrn plus **jeden** zásobník vypsaný celý, takže osm vzorků stojí
    /// dva řádky a šestnáct rámců.
    static let stackBudget = 8

    /// Jeden průchod tělem `View`u. Volá se jako `let _ = RenderDiagnostics.pass(Self.self)` na
    /// začátku `body`.
    ///
    /// Jméno typu se skládá **jen u prvního průchodu** (`@autoclosure`): `String(describing:)` je
    /// reflexe a v tomhle kole by běžela tisíckrát za sekundu.
    static func pass<V>(_ type: V.Type) {
        current?.note(id: ObjectIdentifier(type), name: String(describing: type))
    }

    /// Proběhlo jedno místo, které běží **uvnitř aktualizace grafu** (#361) — dotaz na identitu
    /// v líném seznamu nebo čtení geometrie. Viz `GraphSite`, kde je i důvod, proč zrovna tahle
    /// místa.
    ///
    /// Na rozdíl od `pass(_:)` je tohle ta cesta, která v **hořícím** kole doopravdy běží: tělo se
    /// v něm nepřeloží ani jedno, kdežto identita a geometrie se přepočítávají tisíckrát za
    /// sekundu. Odsud se proto bere i vzorek evaluačního zásobníku.
    static func inGraph(_ site: GraphSite) {
        current?.note(site: site)
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
    /// Kolikrát se v tomhle úseku ozvalo které místo uvnitř aktualizace grafu (#361).
    private var sites: [String: Int] = [:]
    /// Odebrané evaluační zásobníky — **vejde se jich do úseku nejvýš `stackBudget`**.
    private var stacks: [String] = []
    /// Kolikrát se v úseku vzorek **vzal** (i když z něj nic nepřišlo, viz `note(site:)`).
    private var samples = 0
    /// Který úsek to je. Zvyšuje se s každým vynulováním a slouží k jediné věci: poznat vzorek,
    /// který se začal odebírat ještě v předchozím úseku (viz `note(site:)`).
    private var generation = 0
    /// Kdy se bral naposled, v sekundách monotónních hodin. Přes hranici úseku se **nenuluje**:
    /// je to odstup mezi vzorky, ne poloha v úseku.
    private var lastSample: TimeInterval = 0
    private var cycles = 0
    /// Klid, který čeká na souhrn (#412) — kolik úseků, jak dlouho, kolik kol, kolik CPU a kolik
    /// z nich bylo **bez jediného kola runloopu**. Pět čísel pod týmž zámkem jako počitadla; nic se
    /// tím neplánuje a nic to nezapisuje, dokud si o to `flush` neřekne.
    private var quietSections = 0
    private var quietElapsed: TimeInterval = 0
    private var quietCycles = 0
    private var quietCPU: TimeInterval = 0
    private var quietStalled = 0
    private var lastFlush: Date
    private var lastCPU: TimeInterval
    private var isStopped = false
    /// Běží zapisovací vlákno? Drží to, aby druhé volání `startWriting()` nepustilo druhé — viz
    /// komentář u té metody.
    private var isWriting = false
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
        // **Sezení dostane vlastní soubor** (#412): dosavadní záznam se uloží vedle a strop 8 MB
        // tak platí na tohle sezení, ne na zbytek po předchůdcích. Viz `DiagnosticsArchive`.
        let diagnostics = RenderDiagnostics(
            log: DiagnosticsLog(
                url: layout.diagnosticsFile,
                zone: .current,
                archive: DiagnosticsArchive(url: layout.diagnosticsFile)
            ),
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
        // **Co rotace udělala, jde do záznamu** (#412), hned za hlavičku sezení: kde leží zbytek
        // a co se cestou smazalo. Bez toho by soubor začínající od nuly vypadal jako aplikace, která
        // o předchozím sezení neví — a historie by se ztrácela potichu. Láme se to stejně jako
        // hlavička, ze stejného důvodu jako u řádku o grafu níž.
        let rotation = Policy.diagnosticsRotationLines(
            diagnostics.log.rotation,
            at: Date(),
            in: .current
        )
        for line in rotation {
            guard diagnostics.log.append(line) else {
                FileHandle.standardError.write(Data("""
                    PRism: diagnostika kreslení (#361) se NEZAPNULA — do \
                    \(layout.diagnosticsFile.path) se vešla hlavička, ale řádek o rotaci už ne \
                    (strop \(DiagnosticsLog.byteLimit) B). Smaž ten soubor a spusť aplikaci znovu.\n
                    """.utf8))
                return false
            }
        }
        // **Privátní framework se otevírá jedině tady**, tedy jen se zapnutou diagnostikou — a to,
        // jak to dopadlo, se hned zapíše do souboru. Bez té věty by „graf nic neřekl“ a „graf nejde
        // otevřít“ splynulo v tichu (viz `GraphProbe`).
        //
        // **Láme se na tom stejně jako na hlavičce** (nález Copilota na #397). Do #397 se tady
        // návratová hodnota ignorovala s odůvodněním, že zápis už jednou prošel — jenže strop platí
        // na **bajty**, takže hlavička projít může a tenhle řádek už narazit. Diagnostika by se pak
        // zapnula, háky by nesly svou cenu a v souboru by nebylo nic; to je zrovna to splynutí
        // „zapnutá“ a „nic nezapisuje“, kterému se tady vyhýbáme dvakrát.
        let hasGraph = GraphProbe.prepare()
        guard diagnostics.log.append(
            Policy.diagnosticGraphLine(at: Date(), in: .current, available: hasGraph)
        ) else {
            FileHandle.standardError.write(Data("""
                PRism: diagnostika kreslení (#361) se NEZAPNULA — do \
                \(layout.diagnosticsFile.path) se vešla hlavička, ale řádek o grafu už ne \
                (strop \(DiagnosticsLog.byteLimit) B). Smaž ten soubor a spusť aplikaci znovu.\n
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

    /// Ozvalo se místo uvnitř aktualizace grafu (#361): inkrement, a když je čas, **vzorek
    /// evaluačního zásobníku**.
    ///
    /// Vzorek se bere `GraphProbe.stack()`em **mimo zámek**: je to volání do cizí knihovny (0,0063 ms
    /// změřeno), takže pod zámkem by o ně zapisovací vlákno zbytečně čekalo.
    ///
    /// **Vzorek, který přeteče přes hranici úseku, se zahodí** (nález Copilota na #397). Mezi
    /// odebráním a zapsáním se zapisovací vlákno může dostat ke `flush()`u, a pak by zásobník
    /// spadl do **nového** úseku, ve kterém pro něj není započítaný dotaz — z řádku by vyšlo
    /// „0 dotazů, 1 vzorků“. Rozhoduje o tom `generation`: dotaz zůstává v tom úseku, ve kterém
    /// začal, a do dalšího se vzorek nepřenáší, protože do už zapsaného řádku nemá kudy.
    func note(site: GraphSite) {
        let armed: Int? = lock.withLock { armSample(site) ? generation : nil }
        guard let armed else { return }
        guard let stack = GraphProbe.stack() else { return }
        lock.withLock {
            guard generation == armed else { return }
            stacks.append(stack)
        }
    }

    /// Co se od posledního řádku nasbíralo. **Nic tím nenuluje** — je to čtení pro sondy, které
    /// počitadla vyhodnocují samy a řádek do souboru nepotřebují.
    func snapshot() -> [String: Int] {
        lock.withLock { namedPasses() }
    }

    /// Totéž pro místa uvnitř aktualizace grafu.
    func graphSnapshot() -> [String: Int] {
        lock.withLock { sites }
    }

    /// Odebrané zásobníky — pro sondu, která si řádky skládá sama a do souboru nezapisuje.
    func graphStacks() -> [String] {
        lock.withLock { stacks }
    }

    /// Kolik **dotazů** na zásobník v úseku bylo. Není to `graphStacks().count`: dotaz, ze kterého
    /// nic nepřišlo, se počítá taky a právě ten rozdíl je informace (nález Copilota na #397 — sonda
    /// ho odvozovala z pole úspěchů, takže by tiskla „1 dotaz, 1 vzorek“ místo „8 dotazů, 1 vzorek“).
    func graphSampleAttempts() -> Int {
        lock.withLock { samples }
    }

    /// Zahodí, co se nasbíralo. Pro sondy, které měří po úsecích: bez toho by druhý úsek nesl
    /// i to, co se stalo v prvním, a „po gestu se nic nepřekresluje“ by se z čísel nedalo
    /// přečíst. Jména typů zůstávají — jsou to konstanty, ne data.
    func reset() {
        lock.withLock {
            passes.removeAll(keepingCapacity: true)
            resetGraph()
            // I nasbíraný klid (#412): bez toho by souhrn v druhém úseku nesl minuty z prvního
            // a „po gestu se nic nepřekresluje“ by se z čísel nedalo přečíst.
            resetQuiet()
        }
    }

    /// Má se **teď** odebrat vzorek zásobníku? Volá se **pod zámkem** a zároveň počítá to místo,
    /// které se ozvalo.
    ///
    /// Dvě meze, obě vyjmenované: `stackBudget` na úsek (jinak by hořící kolo vyrobilo tisíce
    /// vzorků za sekundu) a odstup `interval / stackBudget` mezi nimi, aby se rozprostřely po
    /// úseku a byl z nich **histogram**, ne osm vzorků z jedné milisekundy. Hodiny se čtou až za
    /// rozpočtem, takže po vyčerpání je z celého téhle metody inkrement pod zámkem.
    private func armSample(_ site: GraphSite) -> Bool {
        sites[site.rawValue, default: 0] += 1
        guard samples < Self.stackBudget else { return false }
        let now = monotonicSeconds()
        guard now - lastSample >= interval / TimeInterval(Self.stackBudget) else { return false }
        lastSample = now
        samples += 1
        return true
    }

    /// Monotónní hodiny pro odstup mezi vzorky — `DispatchTime`, ne `Date`.
    ///
    /// `Date` jde za systémovým časem, takže posun hodin (NTP, uspání stroje) by odstup poslal do
    /// minusu nebo naopak zablokoval vzorky na hodiny. Tady se čte `mach_absolute_time` a je to
    /// jednotky nanosekund na volání.
    private func monotonicSeconds() -> TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    /// Zahodí, co se nasbíralo o grafu. Volá se **pod zámkem**.
    private func resetGraph() {
        sites.removeAll(keepingCapacity: true)
        stacks.removeAll(keepingCapacity: true)
        samples = 0
        generation += 1
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

    /// Přidá klidný úsek do souhrnu (#412). Volá se **pod zámkem**.
    private func fold(elapsed: TimeInterval, cycles: Int, cpu: TimeInterval) {
        quietSections += 1
        quietElapsed += elapsed
        quietCycles += cycles
        quietCPU += cpu
        // Úsek bez jediného kola runloopu, ve kterém se přitom nehořelo, je hlavní vlákno zaseknuté
        // **bez** spalování CPU. Do #412 takový úsek v záznamu nebyl vůbec, protože se nezapisoval.
        if cycles == 0 { quietStalled += 1 }
    }

    /// Souhrn nasbíraného klidu — a **vynuluje ho**. `nil` = není co sečíst. Volá se **pod zámkem**.
    ///
    /// Nasbíraný klid, který nikdo nevyzvedne, se s procesem **zahodí**. Je to tatáž mez jako
    /// u posledního rozepsaného úseku (viz dokumentace typu), jen delší: z konce záznamu chybí až
    /// minuta, a to zrovna ta, ve které se nic nedělo.
    private func quietSummary(at moment: Date) -> String? {
        guard quietSections > 0 else { return nil }
        let line = Policy.diagnosticQuietLine(
            at: moment,
            in: zone,
            over: quietElapsed,
            sections: quietSections,
            cycles: quietCycles,
            cpu: quietCPU,
            stalled: quietStalled
        )
        resetQuiet()
        return line
    }

    /// Zahodí nasbíraný klid. Volá se **pod zámkem**.
    private func resetQuiet() {
        quietSections = 0
        quietElapsed = 0
        quietCycles = 0
        quietCPU = 0
        quietStalled = 0
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
    ///
    /// **Klidný úsek se po sekundách nezapisuje** (#412): sečte se do minutového souhrnu
    /// (`Policy.diagnosticQuietLine`), který jde do souboru buď po minutě, nebo hned, jak se něco
    /// stane — **před** tím řádkem, ať jsou časy v souboru vzestupně. Záchvat se tím nedotkne:
    /// hoření ani průchod tělem klid není, takže se pořád zapisuje po sekundách i s náběhem.
    @discardableResult func flush(at moment: Date, cpu: TimeInterval) -> Bool {
        let lines: [String] = lock.withLock {
            let elapsed = moment.timeIntervalSince(lastFlush)
            let burned = cpu - lastCPU
            let line = Policy.diagnosticLine(
                at: moment,
                in: zone,
                over: elapsed,
                cycles: cycles,
                cpu: burned,
                passes: namedPasses()
            )
            var out: [String] = []
            if let line {
                if let summary = quietSummary(at: moment) { out.append(summary) }
                out.append(line)
                // Řádky o grafu jdou **za** hlavní řádek a jen tehdy, když ten je: bez něj je úsek
                // klid, a klid nemá mít přílohu. Nasbírané se ale zahodí tak i tak, jinak by je
                // nesl další úsek. Změřeno nad záznamem z provozu: pod klidným řádkem nestála ani
                // jedna příloha z 2 601, takže se folding nemá čím dotknout toho, na co je záznam.
                out += Policy.graphDiagnosticLines(sites: sites, stacks: stacks, samples: samples)
            } else {
                fold(elapsed: elapsed, cycles: cycles, cpu: burned)
                if quietElapsed >= Policy.diagnosticQuietInterval,
                   let summary = quietSummary(at: moment) {
                    out.append(summary)
                }
            }
            cycles = 0
            passes.removeAll(keepingCapacity: true)
            resetGraph()
            lastFlush = moment
            lastCPU = cpu
            return out
        }
        // **Nemám co říct** není konec zapisování: nečinná aplikace se zas rozjede.
        for line in lines {
            guard log.append(line) else { return false }
        }
        return true
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
        // **Druhé vlákno by se do záznamu vešlo**, jen by si dva zapisovatelé přebírali počitadla
        // po sobě: každý flush je nuluje, takže by se úseky rozpadly na polovic a řádky by
        // vypadaly, jako že se nic nedělo. Po `stop()` se už nerozjíždí vůbec.
        let allowed = lock.withLock { () -> Bool in
            guard !isWriting, !isStopped else { return false }
            isWriting = true
            return true
        }
        guard allowed else { return }
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
