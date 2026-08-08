import SwiftUI

/// Fronta pull requestů — obsah domácí záložky (#180).
///
/// Do #180 to byl **trvalý levý sloupec** vedle diffu. Přestěhoval se, protože se v něm při čtení
/// kódu nehrabe a diff tím přišel o šířku, kterou má mít; akce nad ním (obnovit, filtr, novinky)
/// jsou v liště `HomeView` nad obsahem, ne v toolbaru okna.
struct PullRequestListView: View {
    @Bindable var store: AppStore

    var body: some View {
        content
            // Ne `VStack` s bannerem nad seznamem: tím by `List` přestal být tím, co se
            // odsazuje od horní hrany, a řádky by lezly nahoru.
            .safeAreaInset(edge: .top, spacing: 0) {
                PollStatusBanner(status: store.status, lastSuccess: store.lastSuccess)
            }
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
        // Platí to i pro rozdělané review a pro odvozená čísla z #172 — bez toho by indikátor
        // naskočil až po překreslení z jiného důvodu.
        // **`visiblePullRequests`, ne `pullRequests`** (#117): filtr je pohled, takže se ho smí
        // dotknout jedině seznam a detail vybraného řádku. Cokoli dalšího nad zúženým seznamem by
        // ze zapnutí filtru udělalo mazání cache — viz `AppStore.pullRequests`.
        let rows = store.visiblePullRequests.map {
            ListRow(
                pullRequest: $0,
                state: store.reviewState(for: $0.id),
                hasDraft: store.hasDraft($0.id),
                summary: store.queueRow(for: $0.id)
            )
        }

        // Výběr otevře **záložku** (#180): seznam je rozcestník, ne polovina okna, takže
        // kliknutí má PR otevřít, ne ho jen označit vedle diffu.
        return List(rows, selection: selectionOpeningTab) { row in
            PullRequestRow(
                pullRequest: row.pullRequest,
                reviewState: row.state,
                hasDraft: row.hasDraft,
                row: row.summary
            )
        }
    }

    /// Výběr, který otevře záložku. Čte se pořád `store.selection`, aby řádek zůstal
    /// zvýrazněný — zapisuje se ale přes `openTab`, protože to je celá akce.
    private var selectionOpeningTab: Binding<PRIdentifier?> {
        Binding(
            get: { store.selection },
            set: { chosen in
                guard let chosen else { return }
                store.openTab(chosen)
            }
        )
    }

    /// Co seznam o jednom řádku ví. Pojmenovaný typ, ne čtveřice: od #172 se skládá ze čtyř
    /// věcí a `\.0.id` v `List`u by přestalo jít přečíst.
    private struct ListRow: Identifiable {
        let pullRequest: PullRequestSummary
        let state: ReviewState
        let hasDraft: Bool
        let summary: QueueRow

        var id: PRIdentifier { pullRequest.id }
    }



    /// Otevře okno s novinkami — totéž, co položka v menu aplikace (#127).
    ///
}
