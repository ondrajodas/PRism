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

    private let preflight: Preflight
    private let makeStore: @MainActor (ToolPaths) -> AppStore

    init(
        preflight: Preflight = .live(),
        makeStore: @escaping @MainActor (ToolPaths) -> AppStore = AppStore.init(toolPaths:)
    ) {
        self.preflight = preflight
        self.makeStore = makeStore
    }

    func check() async {
        // Store se po opakované kontrole staví znovu jen tehdy, když ještě žádný není:
        // jinak by „Zkusit znovu“ zahodilo načtené PR i rozdělaná review.
        if store != nil { return }
        state = .checking
        let report = await preflight.run()
        state = report.toolPaths.map { .ready(makeStore($0)) } ?? .blocked(report)
    }
}

/// Kořen okna. Přepíná mezi kontrolou prostředí, blokující obrazovkou a obsahem aplikace.
struct RootView: View {
    /// `let` stačí — `@Observable` sleduje **čtení** v `body`, ne obal vlastnosti, a žádný
    /// `$binding` odsud nevede.
    let model: PreflightModel

    var body: some View {
        content
            // Podlaha okna. Patří sem, ne k jednotlivým stavům: se `.contentMinSize`
            // v `PRismApp` je minimum obsahu i minimem okna, takže bez toho by se okno dalo
            // stáhnout na pár bodů. Čísla jsou stejná jako u obrazovky s kontrolou prostředí.
            .frame(minWidth: 700, minHeight: 400)
            .task { await model.check() }
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
