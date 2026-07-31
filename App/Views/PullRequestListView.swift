import SwiftUI

/// Levý sloupec — seznam PR napříč repozitáři.
struct PullRequestListView: View {
    @Bindable var store: AppStore
    @State private var isRefreshing = false

    var body: some View {
        content
            // Ne `VStack` s bannerem nad seznamem: tím by `List` přestal být tím, co se
            // odsazuje od horní hrany, a řádky by lezly nahoru.
            .safeAreaInset(edge: .top, spacing: 0) {
                PollStatusBanner(status: store.status, lastSuccess: store.lastSuccess)
            }
            .navigationTitle("Pull requesty")
            .toolbar { refreshButton }
    }

    @ViewBuilder private var content: some View {
        if !store.pullRequests.isEmpty {
            list
        } else if store.status == .notStarted {
            ProgressView("Načítám PR…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Žádné PR k review",
                systemImage: "checkmark.circle",
                description: Text("Až po tobě někdo bude chtít review, objeví se tady.")
            )
        }
    }

    private var list: some View {
        List(store.pullRequests, id: \.id, selection: $store.selection) { pullRequest in
            // Stav review je zatím placeholder — spouštění review přijde s M3.
            PullRequestRow(pullRequest: pullRequest, reviewState: .notStarted)
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                isRefreshing = true
                await store.refresh()
                isRefreshing = false
            }
        } label: {
            if isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Label("Obnovit", systemImage: "arrow.clockwise")
            }
        }
        .disabled(isRefreshing)
        .keyboardShortcut("r")
        .help("Obnovit seznam")
    }
}
