import SwiftUI

/// Hlavní okno: vlevo seznam PR, vpravo místo pro diff a nálezy.
struct ContentView: View {
    @State private var store: AppStore

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
    }

    @ViewBuilder private var detail: some View {
        if let selected = store.pullRequests.first(where: { $0.id == store.selection }) {
            VStack(spacing: 8) {
                Text(selected.title).font(.title2)
                Text(selected.id.description).foregroundStyle(.secondary)
                Text("Diff a nálezy sem přijdou v dalších fázích.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Vyber pull request",
                systemImage: "sidebar.left",
                description: Text("Vlevo je seznam PR, u kterých se po tobě chce review.")
            )
        }
    }
}
