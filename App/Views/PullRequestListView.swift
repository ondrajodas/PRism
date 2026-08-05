import SwiftUI

/// Levý sloupec — seznam PR napříč repozitáři.
struct PullRequestListView: View {
    @Bindable var store: AppStore
    /// Otevře okno s novinkami (#127).
    ///
    /// Předává se **shora**, ne přes `@Environment(\.openWindow)` tady: v toolbaru bočního
    /// panelu je ta akce **němá** — tlačítko projde, ale okno se neotevře. Ověřeno na běžící
    /// aplikaci proti dvěma známým dobrým cestám: `openSettings` ze **stejného** toolbaru
    /// funguje a `openWindow` s tímtéž id funguje z menu i z `RootView`. `ContentView` ji
    /// proto čte v těle okna a sem posílá jako uzávěr.
    let openReleaseNotes: () -> Void
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
                releaseNotesButton
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

    /// Otevře okno s novinkami — totéž, co položka v menu aplikace (#127).
    ///
    /// Stojí **vedle nastavení**, protože je to totéž patro: obojí je o aplikaci, ne o pull
    /// requestu, který je zrovna vybraný. `Obnovit` zůstává vpravo — je to jediná z těch tří
    /// věcí, která se mačká často. Odznak s počtem nepřečtených tady **není**: seznam PR ke
    /// stavu novinek nemá přístup a protahovat ho sem kvůli tečce znamená druhé místo, které
    /// se s oknem umí rozejít.
    private var releaseNotesButton: some View {
        Button(action: openReleaseNotes) {
            Label(ReleaseNotesWindow.title, systemImage: "sparkles")
        }
        .help("Co se v které verzi změnilo")
    }
}
