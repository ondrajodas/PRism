import SwiftUI

/// Domácí záložka (#180): obsah podle toho, co je vybrané v railu.
///
/// Seznam PR se z levého sloupce přestěhoval sem. Do #180 byl trvale vedle diffu — což znamenalo,
/// že diff nikdy neměl celou šířku okna a přitom se v seznamu při čtení kódu nehrabe. Teď se na něj
/// jde záložkou domů, a otevřené review zůstává otevřené.
struct HomeView: View {
    @Bindable var store: AppStore
    /// Otevře okno nastavení. **Uzávěr z těla okna, ne `@Environment`** — viz `ContentView`.
    /// Potřebuje ho prázdný stav sekce `Moje PR`, když mezi zdroji chybí `author:@me` (#331).
    var openSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Dashboard a dění si hlavičku kreslí samy, takže nad nadpisem nemá co stát prázdný
            // pruh s linkou. Návrh v nich žádný nemá a v okně to byl řádek, který nic neříkal.
            if !store.railSection.drawsOwnHeader {
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
                    // Počet z **fronty** (#332): kdyby to bylo číslo z celého seznamu, lišta by
                    // nad frontou hlásila „filtr schoval 1“ i tehdy, když schoval jedno vlastní
                    // PR — tedy řádek, který ve frontě nikdy nebyl.
                    hidden: store.hiddenQueuePullRequestCount,
                    apply: store.setFilter
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        switch store.railSection {
        // Uzávěr, ne odkaz `store.openTab(_:)`: od #409 bere `openTab` i tab, na kterém se má PR
        // otevřít, a odkaz na metodu s výchozím parametrem se ve Swiftu složit nedá. Dashboard tab
        // nejmenuje — karta vede na PR, ne do jeho záložky.
        case .overview: DashboardView(store: store, open: { store.openTab($0) })
        case .queue: PullRequestListView(store: store, scope: .queue)
        // Tentýž seznam nad druhou množinou (#331) — filtr, řazení i detail se použijí beze
        // změny. Druhé view by znamenalo dvě podoby jednoho řádku.
        case .mine: PullRequestListView(store: store, scope: .mine, openSettings: openSettings)
        case .drafts: draftList
        // Dění (#414) — vlastní obrazovka, ne seznam PR: řádek mluví o **události**, ne o pull
        // requestu, a jeden PR jich v něm má klidně pět.
        case .activity: activityFeed
        }
    }

    /// Sekce `Dění` (#414). Hlavičku si kreslí sama, jako dashboard — proto se nad ní nekreslí
    /// lišta s nadpisem (viz `body`).
    private var activityFeed: some View {
        ActivityFeedView(
            days: store.activityFeed,
            empty: store.activityEmptyState,
            subtitle: Policy.activityHeaderSentence(
                lastVisit: store.activityVisitSnapshot,
                hasEvents: !store.activityEvents.isEmpty,
                now: store.time.now
            ),
            lastVisit: store.activityVisitSnapshot,
            lastSuccess: store.lastSuccess,
            // **Jedny hodiny na celou obrazovku**, a ze zdroje času storu: dělení po dnech,
            // věta v hlavičce, pruh i časy u řádků musí mluvit o témže „teď“.
            now: store.time.now,
            open: { store.show($0) },
            openSettings: openSettings,
            openSystemSettings: { SystemSettings.openNotifications() }
        )
    }

    /// Rozdělaná review. Prázdný stav mluví o **rozdělané práci**, ne o frontě — jsou to dvě
    /// různá prázdna a společná věta by u jednoho z nich lhala.
    @ViewBuilder private var draftList: some View {
        let rows = store.pullRequestsWithDraft
        if rows.isEmpty {
            EmptyStateView(
                nature: .calm,
                symbol: "square.and.pencil",
                title: "Nic rozdělaného",
                message: RailSection.drafts.emptyExplanation
            )
        } else {
            List(rows, id: \.id, selection: $store.selection) { pullRequest in
                let ownership = store.ownership(of: pullRequest)
                // Jeden report na řádek (#334, #335): pilulka i text novinek se ptají téže funkce,
                // takže dvě volání by byla tatáž práce dvakrát. U cizího řádku se nekreslí ani jedno.
                let handoff = ownership == .mine ? store.handoffReport(for: pullRequest.id) : .never
                PullRequestRow(
                    pullRequest: pullRequest,
                    reviewState: store.reviewState(for: pullRequest.id),
                    hasDraft: true,
                    row: store.queueRow(for: pullRequest.id),
                    // Vlastní PR vypadá jako vlastní PR i tady (#331) — jeden řádek, jedna podoba.
                    // Od #333 to platí i o akci: `Prompt →` bez akce se nekreslí, takže bez tohohle
                    // řádku by se sekce od seznamu lišila zrovna tím, čím se lišit nemá. Vlastní PR
                    // se sem dostane jedině s draftem z dřívějška — a ten se má dát dořešit.
                    ownership: ownership,
                    openPrompt: { store.openAgentPrompt(in: pullRequest.id) },
                    pending: handoff.pending,
                    activity: handoff.activity
                )
            }
        }
    }


}
