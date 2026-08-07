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
                filterButton
                refreshButton
            }
    }

    private var filterButton: some View {
        PullRequestFilterButton(
            options: store.filterOptions,
            filter: store.filter,
            hidden: store.hiddenPullRequestCount,
            apply: store.setFilter
        )
    }

    @ViewBuilder private var content: some View {
        switch store.listEmptyReason {
        case nil:
            list
        // **Vlastní vysvětlení, ne `Žádné PR k review`.** Zelené „všechno vyřízeno“ nad zapnutým
        // filtrem tvrdí opak toho, co je pravda — tatáž lekce jako `Nálezy jsou schované filtrem
        // reviewerů` v panelu. A nabízí filtr **vypnout**, ať se z toho stavu dá vyjít jedním
        // kliknutím: schovaný PR vypadá jako vyřízený.
        case .filtered(let hidden):
            ContentUnavailableView {
                Label("Filtr schoval všechno", systemImage: "line.3.horizontal.decrease.circle.fill")
            } description: {
                Text(verbatim: "\(Plural.czech(hidden, one: "pull request čeká", few: "pull requesty čekají", many: "pull requestů čeká")) na review, ale filtr je schovává.")
            } actions: {
                Button("Vymazat filtr") { store.clearFilter() }
            }
        case .poll(.loading):
            ProgressView("Načítám PR…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .poll(.noPullRequests):
            ContentUnavailableView(
                "Žádné PR k review",
                systemImage: "checkmark.circle",
                description: Text("Až po tobě někdo bude chtít review, objeví se tady.")
            )
        case .poll(.failure(let reason)):
            ContentUnavailableView(
                "Seznam PR se nepodařilo načíst",
                systemImage: "exclamationmark.triangle",
                description: Text(reason.userDescription)
            )
        case .poll(.rateLimited(let retryAt)):
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
        // **`visiblePullRequests`, ne `pullRequests`** (#117): filtr je pohled, takže se ho smí
        // dotknout jedině seznam a detail vybraného řádku. Cokoli dalšího nad zúženým seznamem by
        // ze zapnutí filtru udělalo mazání cache — viz `AppStore.pullRequests`.
        let rows = store.visiblePullRequests.map {
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
