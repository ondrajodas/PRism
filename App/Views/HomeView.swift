import SwiftUI

/// Domácí záložka (#180): obsah podle toho, co je vybrané v railu.
///
/// Seznam PR se z levého sloupce přestěhoval sem. Do #180 byl trvale vedle diffu — což znamenalo,
/// že diff nikdy neměl celou šířku okna a přitom se v seznamu při čtení kódu nehrabe. Teď se na něj
/// jde záložkou domů, a otevřené review zůstává otevřené.
struct HomeView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            // Dashboard si hlavičku kreslí sám, takže nad pozdravem nemá co stát prázdný pruh
            // s linkou. Návrh v něm žádný nemá a v okně to byl řádek, který nic neříkal.
            if store.railSection != .overview {
                toolbar
                Divider()
            }
            content
        }
    }

    /// Akce nad **obsahem**, ne v railu: obnovit a filtrovat se týkají seznamu, ne navigace.
    /// Filtr se kreslí jen u fronty — nad rozdělanými review nemá co zúžit, protože ta se
    /// schovávat nemají (viz `AppStore.pullRequestsWithDraft`).
    private var toolbar: some View {
        HStack(spacing: 10) {
            // Dashboard má vlastní hlavičku s pozdravem, takže by nadpis stál dvakrát pod sebou.
            if store.railSection != .overview {
                Text(verbatim: store.railSection.title)
                    .font(.headline)
            }
            Spacer(minLength: 8)
            if store.railSection == .queue {
                PullRequestFilterButton(
                    options: store.filterOptions,
                    filter: store.filter,
                    hidden: store.hiddenPullRequestCount,
                    apply: store.setFilter
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        switch store.railSection {
        case .overview: DashboardView(store: store, open: store.openTab(_:))
        case .queue: PullRequestListView(store: store)
        case .drafts: draftList
        }
    }

    /// Rozdělaná review. Prázdný stav mluví o **rozdělané práci**, ne o frontě — jsou to dvě
    /// různá prázdna a společná věta by u jednoho z nich lhala.
    @ViewBuilder private var draftList: some View {
        let rows = store.pullRequestsWithDraft
        if rows.isEmpty {
            ContentUnavailableView(
                "Nic rozdělaného",
                systemImage: "square.and.pencil",
                description: Text(verbatim: RailSection.drafts.emptyExplanation)
            )
        } else {
            List(rows, id: \.id, selection: $store.selection) { pullRequest in
                PullRequestRow(
                    pullRequest: pullRequest,
                    reviewState: store.reviewState(for: pullRequest.id),
                    hasDraft: true,
                    row: store.queueRow(for: pullRequest.id)
                )
            }
        }
    }


}
