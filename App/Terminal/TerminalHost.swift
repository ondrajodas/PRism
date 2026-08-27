import AppKit

/// Živé terminály v okně (#459) — **jeden shell na pull request**.
///
/// Proč na PR a ne jeden na okno: pracovní adresář je checkout **toho** PR, takže jediný shell by
/// se při přepnutí záložky musel buď restartovat (a zabít rozdělaný `claude --resume`), nebo lhát
/// o tom, kde stojí. Obojí je horší než dva shelly.
///
/// Proč vůbec zvlášť od `AppStore`: shell je `NSView` a cizí proces, kdežto store drží stav, který
/// kreslí okno. Kdyby plocha bydlela ve storu, nešlo by ho složit bez AppKitu a nešlo by napsat
/// test „zavření záložky shell zabilo“ jinak než spuštěním skutečného shellu.
@MainActor
final class TerminalHost: TerminalHosting {
    /// Plochy podle pull requestu. Drží se **silně a jinde než ve SwiftUI stromu**: `makeNSView`
    /// se volá při každém složení stromu, takže plocha vlastněná view by znamenala nový shell po
    /// každém zavření a otevření zásuvky.
    private var views: [PRIdentifier: EmbeddedTerminalView] = [:]

    var report: (@MainActor (PRIdentifier, TerminalRunState) -> Void)?
    var focusChanged: (@MainActor (Bool) -> Void)?

    /// Řez z návrhu: `.term-body { font-family: var(--mono); font-size: 11.5px }`.
    ///
    /// `monospacedSystemFont`, ne `Menlo`: `--mono` z návrhu začíná `ui-monospace`, což je na macOS
    /// právě systémový mono řez — a je to tentýž řez, jakým se v okně sází kapsle i diff.
    static let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)

    var runningTerminals: Int { views.values.count { $0.isRunning } }

    func terminal(for pr: PRIdentifier, in directory: URL) -> NSView {
        surface(for: pr, in: directory)
    }

    /// `▶` v hlavičce dráhy (#460) — napiš do zásuvky řádku, jako by ji člověk odeslal.
    ///
    /// **Plocha se vyrábí toutéž cestou jako pro `` ⌃` ``** (`surface(for:in:)`), takže zásuvka,
    /// která se pak otevře, ukáže tenhle shell a ne druhý — idempotence z `terminal(for:in:)` je
    /// podmínka i tady.
    @discardableResult
    func run(
        _ commandLine: String,
        for pr: PRIdentifier,
        in directory: URL
    ) -> TerminalCommandOutcome {
        let view = surface(for: pr, in: directory)
        if view.isRunning {
            // Pořadí schválně: **napřed se ptáme, jestli je kam psát**. Opačně by se řádka poslala
            // a teprve pak by se zjistilo komu.
            guard !view.hasForegroundJob else { return .busy }
            // Že řádka odešla, se **čte z výsledku**: shell umí hlásit `running` i po zavření pty
            // (viz `send(line:)`), a `start(in:)` by nad ním neudělal nic — takže tam už není co
            // zkoušet a jediná pravdivá odpověď je „shell nemá kdo přečíst“.
            return view.send(line: commandLine) ? .sent : .noShell
        }
        // Shell po `exit` nebo po pádu. `start(in:)` si běžící proces hlídá sám, takže tady
        // znamená „pusť ho znovu“ — starý výpis přitom v ploše zůstane, což je pro čtení
        // předchozí session spíš dobře.
        view.start(in: directory)
        // **Stav se čte, ne předpokládá** (tatáž úvaha jako u `start(in:)`): `SHELL` umí mířit na
        // binárku, která neexistuje, a `fork`/`exec` umí selhat. `started` nad neběžícím shellem
        // by tvrdilo, že se něco pustilo, a řádka by se přitom neměla kde přečíst.
        return view.send(line: commandLine) ? .started : .noShell
    }

    /// Plocha toho pull requestu — **vyrobí ji, když ještě není, jinak vrátí tutéž**.
    ///
    /// Vrací `EmbeddedTerminalView`, ne `NSView`: `run(_:for:in:)` se jí potřebuje ptát na stav
    /// shellu, a přetypovávat zpátky to, co jsme právě vyrobili, je jen zdroj druhé pravdy.
    private func surface(for pr: PRIdentifier, in directory: URL) -> EmbeddedTerminalView {
        if let existing = views[pr] { return existing }
        // Nenulový rámec schválně: `SwiftTerm` si z něj počítá sloupce a řádky, a na nulové ploše
        // by z toho vyšlo `0×0`. Skutečnou velikost dostane hned prvním rozvržením, které pošle
        // `TIOCSWINSZ` (`setFrameSize` → `processSizeChange`).
        let view = EmbeddedTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        view.font = Self.font
        view.applyPalette()
        view.focusChanged = { [weak self] hasFocus in self?.focusChanged?(hasFocus) }
        view.stateChanged = { [weak self] state in self?.report?(pr, state) }
        views[pr] = view
        view.start(in: directory)
        return view
    }

    @discardableResult
    func stopTerminal(for pr: PRIdentifier) -> Bool {
        guard let view = views.removeValue(forKey: pr) else { return false }
        let wasRunning = view.isRunning
        view.kill()
        // Fokus se hlásí ručně: zabitá plocha zmizí z hierarchie, aniž by jí AppKit stihl poslat
        // `resignFirstResponder` — a okno by pak mělo zkratky vypnuté nad terminálem, který není.
        focusChanged?(false)
        return wasRunning
    }

    /// Zabije všechny — ukončení aplikace (#264).
    ///
    /// **Synchronně a bez čekání na runloop**: `applicationShouldTerminate` odpovídá systému hned
    /// po tomhle, takže cokoli odloženého by se už nespustilo a shell by osiřel na `launchd`.
    func stopAllTerminals() {
        // `Array(views.keys)` schválně: `stopTerminal` mapu mění, a iterovat přes její vlastní
        // klíče při zápisu do ní je past, která se dneska nechová špatně jen proto, že si `Array`
        // vyrobí kopii při prvním zápisu (COW). Napsat to rovnou je levnější než to vysvětlovat.
        for pr in Array(views.keys) { stopTerminal(for: pr) }
    }
}
