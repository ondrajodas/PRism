import Foundation

/// Které podprocesy aplikace právě drží — zapsané na disk, aby se po zabité aplikaci daly
/// dohledat a zabít (#351).
///
/// Značka se zapíše hned po spuštění procesu a **maže se jeho koncem**. Co v souboru po startu
/// zbylo a nemá živého vlastníka, jsou sirotci: `claude -p`, který aplikaci přežil, běží dál pod
/// `launchd` a pořád platí tokeny za review, jehož výsledek nemá kam doručit.
///
/// **Proč to nejde vyřešit prevencí:** změřeno, že potomek spuštěný `Foundation.Process`em přežije
/// rodičovi `SIGTERM` i `SIGKILL` a přejde pod `launchd` (`ps -o ppid` → 1) — a macOS nemá čím tomu
/// zabránit: v `sys/spawn.h` není nic jako `PDEATHSIG` a `PROC_SETPC_TERMINATE`, který se nabízel,
/// je podle `libproc.h` o hladovění po paměti, nastavuje se **sám sobě** a s koncem rodiče nesouvisí.
/// Záruka z #264 (`SIGKILL` z `LaunchedProcess` při zrušení i ukončení) proto pokrývá jen normální
/// ukončení; zabití zvenčí a zaseknuté hlavní vlákno nemají kde úklid spustit. Zbývá úklid **po**,
/// a jeho cena je, že sirotek žije do dalšího spuštění aplikace — což je zpravidla vteřiny, protože
/// se zaseknutá aplikace zabíjí právě proto, aby se spustila znovu.
///
/// **Vlastní soubor, ne příznak v `InterruptedRuns`.** Nabízelo se to (obojí je stav rozdělaného
/// běhu), ale klíč je jiný: `InterruptedRun` se klíčuje `ReviewRunKey`, tedy `(PR, commit, skill)`,
/// kdežto tady je klíč **operační systém** a záznam nemá s review nic společného kromě toho, že ho
/// review spustilo. Slepit je by znamenalo, že dotahování nálezů z transcriptu (#97) čte pole,
/// která ho nezajímají, a naopak.
///
/// **Bez paměťové cache, na rozdíl od `InterruptedRuns`.** Ten samý soubor umí psát druhá instance
/// téhož bundlu — testovací host `xcodebuild test` má stejné `CFBundleName`, takže i stejnou cache —
/// a cache v paměti by jí značky přepsala. Čte se dvakrát za session (spuštění a konec), tedy ne
/// v tiku pollingu ani při každém uložení.
///
/// Zámek, ne aktor: značky se zapisují z `LaunchedProcess`, tedy i z `terminationHandler`u, který
/// není `async` — a čekat na aktor uvnitř něj by znamenalo odložit zápis do doby, kdy už aplikace
/// nemusí existovat.
final class RunningSessions: @unchecked Sendable {
    /// Jedna instance na aplikaci, a schválně: soubor je jeden, takže druhá instance by byla
    /// druhá pravda o tom, co běží. Úklid při startu (`AppDelegate`) i zapisování běhů
    /// (`SubprocessStreamer`) sahají na totéž.
    static let shared = RunningSessions()

    private let layout: CacheLayout
    private let inspector: any ProcessInspecting
    /// Identita téhle instance aplikace. `nil` by znamenalo, že se sama v tabulce procesů
    /// nenašla — pak se nic nezapisuje, protože značka bez vlastníka by se při dalším startu
    /// tvářila jako sirotek.
    private let owner: ProcessIdentity?
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        layout: CacheLayout = .applicationSupport,
        inspector: any ProcessInspecting = SystemProcessInspector(),
        owner: ProcessIdentity? = nil
    ) {
        self.layout = layout
        self.inspector = inspector
        self.owner = owner ?? inspector.identity(of: ProcessInfo.processInfo.processIdentifier)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// Zapamatuje si běžící podproces.
    ///
    /// Identitu si přečte z jádra sama a **nebere ji od volajícího**: značka, která se dá zapsat
    /// s vymyšleným `startedAt`, by úklid při startu poslala na cizí proces. Když se pod tím PID
    /// už nic neběží (proces doběhl mezi spuštěním a tímhle voláním), nezapíše se nic — není co
    /// zabíjet.
    func remember(pid: pid_t) {
        guard let owner, let process = inspector.identity(of: pid) else { return }
        let session = RunningSession(owner: owner, process: process)
        lock.withLock {
            var sessions = load().filter { !isMine($0, pid: pid) }
            sessions.append(session)
            write(sessions)
        }
    }

    /// Podproces doběhl, takže se o něj už nikdo starat nemusí.
    ///
    /// Maže **jen vlastní** značky. Značka cizí instance se pozná podle `owner` a nechává se jí:
    /// smazat ji by znamenalo, že o jejím běhu nikdo neví a její sirotek nikdy neodejde.
    func forget(pid: pid_t) {
        lock.withLock {
            let sessions = load()
            let kept = sessions.filter { !isMine($0, pid: pid) }
            guard kept.count != sessions.count else { return }
            write(kept)
        }
    }

    /// Zabije, co po zabité aplikaci zbylo, a vrátí počet odeslaných signálů.
    ///
    /// Rozhodnutí o každé značce dělá `Policy.orphanVerdict` — tady zůstává jen I/O: přečíst
    /// soubor, zeptat se jádra na dvě identity, poslat signál a zapsat zpátky to, co dál platí.
    ///
    /// **Když se nic nezahodilo, nezapisuje se vůbec** — a není to úspora bajtů. Za prvé je to
    /// běžný stav (aplikace se obvykle zavírá normálně, takže po ní nic nezůstává) a start by za
    /// něj platil sáhnutím na disk i zakládáním složky, která by jinak nemusela vzniknout. Za
    /// druhé je to jediná ochrana proti tomu, aby úklid **přepsal značku cizí instance**, která
    /// vznikla mezi čtením a zápisem — dvě instance téhož slotu nad jednou cache jsou stav, který
    /// nic nezakazuje, a druhá z nich by uměla zahodit značku právě spuštěné session; její sirotek
    /// by pak neodešel nikdy.
    ///
    /// **Testovací host mezi ně od #421 nepatří.** Do té doby ano, a byl to ten hlavní případ:
    /// `CFBundleName` se skládal z `PRISM_SLOT_LABEL` s prázdnou výchozí hodnotou, takže
    /// `xcodebuild test` pouštěl aplikaci nad **tou samou cache** jako instalace v `/Applications`.
    /// Dnes má host vlastní kořen (`PRism-testhost`) a hlídají to `ProcessPreferencesTests`.
    @discardableResult
    func reapOrphans() -> Int {
        lock.withLock {
            let sessions = load()
            var kept: [RunningSession] = []
            var killed = 0
            for session in sessions {
                let verdict = Policy.orphanVerdict(
                    for: session,
                    ownerNow: inspector.identity(of: session.owner.pid),
                    processNow: inspector.identity(of: session.process.pid)
                )
                switch verdict {
                case .keep:
                    kept.append(session)
                case .kill:
                    if inspector.kill(session.process) { killed += 1 }
                case .discard:
                    break
                }
            }
            if kept.count != sessions.count { write(kept) }
            return killed
        }
    }

    /// Je to značka téhle instance na tenhle PID?
    private func isMine(_ session: RunningSession, pid: pid_t) -> Bool {
        session.owner == owner && session.process.pid == pid
    }

    /// Nečitelný soubor se bere jako prázdný — stejně jako u `InterruptedRuns`. Nejhorší následek
    /// je neuklizený sirotek, tedy stav před #351; vyhozená chyba by proti tomu položila start
    /// aplikace, a tohle je záchranná síť, ne cesta, na které něco stojí.
    private func load() -> [RunningSession] {
        guard let data = try? Data(contentsOf: layout.sessionsFile),
            let stored = try? decoder.decode([RunningSession].self, from: data)
        else { return [] }
        return stored
    }

    /// Selhání zápisu se spolkne, a je to tentýž kompromis jako u `InterruptedRuns`: nezapsaná
    /// značka znamená sirotka, kterého příští start neuklidí — tedy stav před #351. Zabít
    /// běžící session kvůli tomu, že se nepovedl zápis, by bylo dražší.
    private func write(_ sessions: [RunningSession]) {
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: layout.sessionsFile, options: .atomic)
    }
}
