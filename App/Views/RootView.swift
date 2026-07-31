import SwiftUI

/// Stav startu aplikace. Dokud preflight neprojde, nemá zbytek UI s čím pracovat.
@Observable
@MainActor
final class PreflightModel {
    enum State {
        case checking
        case ready(ToolPaths)
        case blocked(PreflightReport)
    }

    private(set) var state: State = .checking

    private let preflight: Preflight

    init(preflight: Preflight = .live()) {
        self.preflight = preflight
    }

    func check() async {
        state = .checking
        let report = await preflight.run()
        state = report.toolPaths.map(State.ready) ?? .blocked(report)
    }
}

/// Kořen okna. Přepíná mezi kontrolou prostředí, blokující obrazovkou a obsahem aplikace.
struct RootView: View {
    @State private var model = PreflightModel()

    var body: some View {
        content
            .task { await model.check() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .checking:
            ProgressView("Kontroluji prostředí…")
                .frame(minWidth: 600, minHeight: 400)
        case .ready(let toolPaths):
            ContentView(toolPaths: toolPaths)
        case .blocked(let report):
            PreflightGateView(report: report) {
                Task { await model.check() }
            }
        }
    }
}
