import SwiftUI

/// Hlavní okno: vlevo seznam PR, vpravo místo pro diff a nálezy.
struct ContentView: View {
    @State private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    init(toolPaths: ToolPaths) {
        _store = State(initialValue: AppStore(toolPaths: toolPaths))
    }

    init(store: AppStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        NavigationSplitView {
            PullRequestListView(store: store)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
        } detail: {
            detail
        }
        // Smyčka žije, dokud žije okno — zavření okna task zruší a polling se zastaví.
        .task { await store.keepFresh() }
        // Konfigurace se edituje v souboru mimo aplikaci, takže se načte pokaždé, když se
        // do ní člověk vrátí. Sledovat soubor by znamenalo řešit atomický zápis, po kterém
        // hlídaný deskriptor přestane platit — a tlačítko by byl krok navíc za něco, co se
        // dá udělat samo.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.reloadConfiguration() }
        }
    }

    @ViewBuilder private var detail: some View {
        if let selected = store.pullRequests.first(where: { $0.id == store.selection }) {
            PullRequestDetailView(store: store, pullRequest: selected)
        } else {
            ContentUnavailableView(
                "Vyber pull request",
                systemImage: "sidebar.left",
                description: Text("Vlevo je seznam PR, u kterých se po tobě chce review.")
            )
        }
    }
}
