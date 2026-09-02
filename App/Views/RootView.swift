import SwiftUI

/// Stav startu aplikace. Dokud preflight neprojde, nemá zbytek UI s čím pracovat.
///
/// Drží i `AppStore`, protože ten vzniká právě z toho, co preflight našel. Vlastnit ho
/// musí něco nad oknem: okno nastavení je **vlastní scéna**, takže ke store uvnitř
/// `ContentView` by se nedostalo.
@Observable
@MainActor
final class PreflightModel {
    enum State {
        case checking
        case ready(AppStore)
        case blocked(PreflightReport)
    }

    private(set) var state: State = .checking

    /// Store, jakmile prostředí prošlo. `nil` po celou dobu, kdy aplikace nemá s čím
    /// pracovat — okno nastavení se podle toho zamkne.
    var store: AppStore? {
        guard case .ready(let store) = state else { return nil }
        return store
    }

    /// Novinky (#127). Taky až po preflightu — bez `gh` se nemají čím stáhnout — a taky
    /// **nad okny**, protože okno s novinkami je vlastní scéna jako nastavení.
    private(set) var releaseNotes: ReleaseNotesModel?

    private let preflight: Preflight
    private let makeStore: @MainActor (ToolPaths) -> AppStore
    private let makeReleaseNotes: @MainActor (ToolPaths) -> ReleaseNotesModel

    init(
        preflight: Preflight = .live(),
        makeStore: @escaping @MainActor (ToolPaths) -> AppStore = AppStore.init(toolPaths:),
        makeReleaseNotes: @escaping @MainActor (ToolPaths) -> ReleaseNotesModel = {
            ReleaseNotesModel(gateway: GhGateway(gh: $0.gh, runner: SubprocessRunner()))
        }
    ) {
        self.preflight = preflight
        self.makeStore = makeStore
        self.makeReleaseNotes = makeReleaseNotes
    }

    /// Pull request, o který si někdo řekl přes `prism://`, než byl store na světě (#531).
    ///
    /// **Odkaz umí aplikaci spustit**, takže obvyklé pořadí je obrácené: `onOpenURL` přijde dřív,
    /// než preflight doběhne. Zahodit ho by znamenalo, že kliknutí na odkaz spustí PRism a **nic
    /// neotevře** — tedy ten nejhorší možný výsledek, protože podruhé už aplikace poběží a odkaz
    /// zabere. Vyzvedne se v `check()` a hned se zapomene.
    private var pendingPullRequest: PRIdentifier?

    /// Otevře pull request z `prism://open?url=…`.
    ///
    /// **Adrese, které se nerozumí, se nedělá nic** a je to vědomé: schéma může vyvolat kdokoli,
    /// takže z nerozluštěné adresy nemá být ani chybová obrazovka, ani otevřená záložka. Co je
    /// adresa PR, rozhoduje `Policy` na jednom místě — tomtéž, které rozebírá vložený odkaz v ⌘K.
    func open(_ url: URL) {
        guard let pullRequest = Policy.openedPullRequest(from: url) else { return }
        guard let store else {
            pendingPullRequest = pullRequest
            return
        }
        store.openPullRequest(pullRequest)
    }

    func check() async {
        // Store se po opakované kontrole staví znovu jen tehdy, když ještě žádný není:
        // jinak by „Zkusit znovu“ zahodilo načtené PR i rozdělaná review. Totéž platí
        // o novinkách — stažená historie by se zahodila spolu s ním.
        if store != nil { return }
        state = .checking
        let report = await preflight.run()
        guard let paths = report.toolPaths else {
            state = .blocked(report)
            return
        }
        releaseNotes = makeReleaseNotes(paths)
        let store = makeStore(paths)
        state = .ready(store)
        // Odložená žádost z `prism://` (#531). **Až za `state`**, aby záložka vznikla nad
        // storem, který okno už kreslí — a **jen jednou**: druhé spuštění preflightu
        // (`Zkusit znovu`) se sem stejně nedostane, protože store už existuje.
        if let pendingPullRequest {
            self.pendingPullRequest = nil
            store.openPullRequest(pendingPullRequest)
        }
    }
}

/// Kořen okna. Přepíná mezi kontrolou prostředí, blokující obrazovkou a obsahem aplikace.
struct RootView: View {
    /// `let` stačí — `@Observable` sleduje **čtení** v `body`, ne obal vlastnosti, a žádný
    /// `$binding` odsud nevede.
    let model: PreflightModel
    @Environment(\.openWindow) private var openWindow

    /// Obrázky uživatelů u událostí v přehledu (#171).
    ///
    /// Žije **tady**, ne v `PreflightModel`: preflight na avatary nemá vliv (jde se na
    /// veřejné HTTP, ne přes `gh`) a potřebuje je jedině hlavní okno — nastavení ani novinky
    /// ne. `@State` navíc drží cache po celou dobu života okna, takže se týž obrázek netahá
    /// znovu při každém překreslení.
    @State private var avatars = AvatarLoader()

    var body: some View {
        content
            .environment(avatars)
            // Podlaha okna. Patří sem, ne k jednotlivým stavům: se `.contentMinSize`
            // v `PRismApp` je minimum obsahu i minimem okna, takže bez toho by se okno dalo
            // stáhnout na pár bodů. Čísla jsou stejná jako u obrazovky s kontrolou prostředí.
            .frame(minWidth: 700, minHeight: 400)
            .task {
                await model.check()
                // Novinky až po preflightu — bez `gh` se nemají čím stáhnout. Otevřít okno
                // umí jedině view, takže rozhodnutí („je co ukázat?“) je v modelu a akce tady.
                // Že se okno nabídne **jednou za běh**, hlídá model: hlavní okno jde zavřít
                // a otevřít znovu, čímž se tenhle task pustí podruhé.
                guard let notes = model.releaseNotes, await notes.showsNewReleaseAfterStart() else {
                    return
                }
                openWindow(id: ReleaseNotesWindow.id)
            }
            // `prism://open?url=…` (#531). Patří to sem, ne do `PRismApp`: adresa se vykonává nad
            // store, a ten vzniká teprve po preflightu — takže se o pořadí musí postarat model
            // (`open(_:)` si žádost schová, dokud store nebude).
            .onOpenURL { model.open($0) }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .checking:
            ProgressView("Kontroluji prostředí…")
                .frame(minWidth: 600, minHeight: 400)
        case .ready(let store):
            ContentView(store: store)
        case .blocked(let report):
            PreflightGateView(report: report) {
                Task { await model.check() }
            }
        }
    }
}
