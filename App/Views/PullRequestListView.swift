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
            .safeAreaInset(edge: .bottom, spacing: 0) { notices }
            .navigationTitle("Pull requesty")
            .toolbar {
                settingsButton
                refreshButton
            }
    }

    /// Pruh pod seznamem: co je špatně a co se kvůli tomu neděje.
    ///
    /// **Musí mít neprůhledné pozadí.** `safeAreaInset` sice místo vyhradí, ale průhledný
    /// obsah nechá řádky seznamu prosvítat skrz a texty se míchají do sebe. A když není co
    /// říct, nekreslí se vůbec — trvalý pruh ubírá místo seznamu a oko se ho naučí
    /// přehlížet.
    ///
    /// Kde tyhle hlášky nakonec skončí, řeší #31 (stavový řádek).
    @ViewBuilder private var notices: some View {
        if hasNotices {
            VStack(alignment: .leading, spacing: 4) {
                // Rozbitá konfigurace nesmí projít tiše — jinak uživatel hledá, proč mu
                // nastavení nefunguje, a aplikace mezitím běží na výchozích hodnotách.
                if let failure = store.configurationFailure {
                    notice(failure, icon: "exclamationmark.triangle")
                }
                // Pozastavený automat se **musí** ukázat. Bez toho vypadá jako rozbitý: PR
                // přibývají, nic se nespouští a proč se nedá zjistit odnikud.
                if store.remainingAutomaticRuns == 0 {
                    notice(
                        "Automatické review pozastavené — vyčerpaný denní limit "
                            + "(\(store.configuration.global.autoRunsPerDay)). Ručně jde dál.",
                        icon: "pause.circle"
                    )
                }
                // Rozbitý soubor s nálezy znamená, že se nějaké ztratily — a ztracený nález
                // se nesmí tvářit jako „review neběželo“.
                if store.unreadableReviewFiles > 0 {
                    notice(
                        "\(store.unreadableReviewFiles) uložených nálezů se nepodařilo přečíst.",
                        icon: "exclamationmark.triangle"
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .top) { Rectangle().fill(.separator).frame(height: 1) }
        }
    }

    private var hasNotices: Bool {
        store.configurationFailure != nil
            || store.remainingAutomaticRuns == 0
            || store.unreadableReviewFiles > 0
    }

    private func notice(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        let rows = store.pullRequests.map { ($0, store.reviewState(for: $0.id)) }

        return List(rows, id: \.0.id, selection: $store.selection) { pullRequest, state in
            PullRequestRow(pullRequest: pullRequest, reviewState: state)
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
