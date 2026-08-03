import SwiftUI

/// Levý sloupec — seznam PR napříč repozitáři.
struct PullRequestListView: View {
    @Bindable var store: AppStore
    @Environment(\.openSettings) private var openSettings
    @State private var isRefreshing = false

    var body: some View {
        content
            // Ne `VStack` s bannerem nad seznamem: tím by `List` přestal být tím, co se
            // odsazuje od horní hrany, a řádky by lezly nahoru.
            .safeAreaInset(edge: .top, spacing: 0) {
                PollStatusBanner(status: store.status, lastSuccess: store.lastSuccess)
            }
            .navigationTitle("Pull requesty")
            .toolbar {
                settingsButton
                refreshButton
            }
    }

    @ViewBuilder private var content: some View {
        switch store.emptyReason {
        case nil:
            list
        case .loading:
            ProgressView("Načítám PR…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noPullRequests:
            ContentUnavailableView(
                "Žádné PR k review",
                systemImage: "checkmark.circle",
                description: Text("Až po tobě někdo bude chtít review, objeví se tady.")
            )
        case .failure(let reason):
            ContentUnavailableView(
                "Seznam PR se nepodařilo načíst",
                systemImage: "exclamationmark.triangle",
                description: Text(reason.userDescription)
            )
        case .rateLimited(let retryAt):
            ContentUnavailableView(
                "GitHub omezuje dotazy",
                systemImage: "hourglass",
                description: Text("Zkusím to znovu v \(retryAt.formatted(date: .omitted, time: .shortened)).")
            )
        }
    }

    private var list: some View {
        // Stavy se čtou **tady**, ne až uvnitř řádku: `List` staví řádky líně a mimo
        // sledování závislostí rodiče, takže změna stavu by seznam nemusela překreslit.
        // Platí to i pro rozdělané review — bez toho by indikátor naskočil až po
        // překreslení z jiného důvodu.
        let rows = store.pullRequests.map {
            ($0, store.reviewState(for: $0.id), store.hasDraft($0.id))
        }

        return List(rows, id: \.0.id, selection: $store.selection) { pullRequest, state, hasDraft in
            PullRequestRow(pullRequest: pullRequest, reviewState: state, hasDraft: hasDraft)
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

    /// Otevře okno nastavení — totéž, co ⌘, v menu. Ozubené kolo je zvyklost, ale samo
    /// o sobě se nedá najít klávesnicí, a naopak zkratku hledá málokdo v toolbaru.
    private var settingsButton: some View {
        Button { openSettings() } label: {
            Label("Nastavení", systemImage: "gearshape")
        }
        .help("Nastavení aplikace (⌘,)")
    }
}
