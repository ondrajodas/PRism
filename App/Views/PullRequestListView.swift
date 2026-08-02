import AppKit
import SwiftUI

/// Levý sloupec — seznam PR napříč repozitáři.
struct PullRequestListView: View {
    @Bindable var store: AppStore
    @State private var isRefreshing = false
    @State private var isShowingSettings = false

    var body: some View {
        content
            // Ne `VStack` s bannerem nad seznamem: tím by `List` přestal být tím, co se
            // odsazuje od horní hrany, a řádky by lezly nahoru.
            .safeAreaInset(edge: .top, spacing: 0) {
                PollStatusBanner(status: store.status, lastSuccess: store.lastSuccess)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { unreadableWarning }
            .navigationTitle("Pull requesty")
            .toolbar {
                settingsButton
                refreshButton
            }
    }

    /// Rozbitý soubor s nálezy znamená, že se nějaké ztratily — a ztracený nález se v UI
    /// nesmí tvářit jako „review neběželo“. Je to stav celé cache, ne jednoho PR, takže
    /// patří pod seznam; když je všechno v pořádku, nekreslí se vůbec.
    @ViewBuilder private var unreadableWarning: some View {
        // Rozbitá konfigurace nesmí projít tiše — jinak uživatel hledá, proč mu nastavení
        // nefunguje, a aplikace mezitím běží na výchozích hodnotách.
        if let failure = store.configurationFailure {
            Label(failure, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        if store.unreadableReviewFiles > 0 {
            Label(
                "\(store.unreadableReviewFiles) uložených nálezů se nepodařilo přečíst.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Konfigurace se edituje v souboru, ne v okně (editor je #70). Ozubené kolo ale
    /// slibuje nastavení, takže pod ním musí něco takového být: kde soubor je a jak ho
    /// otevřít. Načítat ho ručně netřeba — děje se to při návratu do aplikace.
    private var settingsButton: some View {
        Button { isShowingSettings = true } label: {
            Label("Nastavení", systemImage: "gearshape")
        }
        .help("Nastavení aplikace")
        .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) { settingsPopover }
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nastavení").font(.headline)
            Text("Zatím se edituje v souboru — editor v okně teprve přijde. Změny se načtou, jakmile se do aplikace vrátíš.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: CacheLayout.applicationSupport.configFile.path(percentEncoded: false))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Otevřít soubor", systemImage: "square.and.pencil") {
                NSWorkspace.shared.open(CacheLayout.applicationSupport.configFile)
                isShowingSettings = false
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
    }
}
