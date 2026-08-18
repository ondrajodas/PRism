import SwiftUI

/// Kterou sekci railu seznam kreslí (#331).
///
/// **Vyjmenované, ne `PullRequestOwnership`**, i když od #332 fronta na cizích PR opravdu stojí.
/// Sekce je totiž víc než jedna množina: nese i to, mezi kolika prázdny se rozhoduje (`Moje PR`
/// jich má pět) a jakou větou se mluví o schovaných řádcích. `PullRequestOwnership` by z těch tří
/// věcí odpověděl na jednu a zbylé dvě by se rozhodovaly někde vedle.
enum PullRequestListScope {
    /// Fronta — cizí PR po filtru (#332).
    case queue
    /// Moje PR — tentýž seznam zúžený podle autora na druhou stranu.
    case mine
}

/// Fronta pull requestů — obsah domácí záložky (#180).
///
/// Do #180 to byl **trvalý levý sloupec** vedle diffu. Přestěhoval se, protože se v něm při čtení
/// kódu nehrabe a diff tím přišel o šířku, kterou má mít; akce nad ním (obnovit, filtr, novinky)
/// jsou v liště `HomeView` nad obsahem, ne v toolbaru okna.
///
/// Od #331 kreslí **dvě sekce railu**: frontu a moje PR. Rozdíl je jen v tom, který seznam se
/// vezme a co se řekne nad prázdnem — řádek, filtr, řazení ani otevření záložky se neliší, protože
/// je to pořád seznam pull requestů.
struct PullRequestListView: View {
    @Bindable var store: AppStore
    var scope: PullRequestListScope = .queue
    /// Otevře nastavení — jedině pro prázdný stav `Moje PR` bez zdroje (#331).
    var openSettings: () -> Void = {}

    var body: some View {
        content
            // Ne `VStack` s bannerem nad seznamem: tím by `List` přestal být tím, co se
            // odsazuje od horní hrany, a řádky by lezly nahoru.
            .safeAreaInset(edge: .top, spacing: 0) {
                PollStatusBanner(status: store.status, lastSuccess: store.lastSuccess)
            }
    }

    /// Proč je seznam prázdný. **Dvě různé funkce, jeden typ** (#331): u vlastních PR se rozhoduje
    /// i mezi chybějícím zdrojem a nenačteným loginem, kdežto fronta ta prázdna mít nemůže.
    private var emptyReason: ListEmptyReason? {
        switch scope {
        case .queue: store.listEmptyReason
        case .mine: store.ownListEmptyReason
        }
    }

    @ViewBuilder private var content: some View {
        switch emptyReason {
        case nil:
            list
        // **Vlastní vysvětlení, ne `Žádné PR k review`.** Zelené „všechno vyřízeno“ nad zapnutým
        // filtrem tvrdí opak toho, co je pravda — tatáž lekce jako `Nálezy jsou schované filtrem
        // reviewerů` v panelu. A nabízí filtr **vypnout**, ať se z toho stavu dá vyjít jedním
        // kliknutím: schovaný PR vypadá jako vyřízený.
        case .filtered(let hidden):
            EmptyStateView(
                // **Ne `calm`.** Zelené „vyřízeno“ nad zapnutým filtrem tvrdí opak toho, co je
                // pravda: práce je, jen ji nevidím.
                nature: .waiting,
                symbol: "line.3.horizontal.decrease",
                title: "Filtr schoval všechno",
                message: filteredMessage(hidden),
                primary: .init(title: "Vymazat filtr") { store.clearFilter() }
            )
        case .poll(.loading):
            ProgressView("Načítám PR…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .poll(.noPullRequests):
            EmptyStateView(
                nature: .calm,
                symbol: "checkmark",
                title: "Žádné PR k review",
                message: lastTick.map { "Až po tobě někdo bude chtít review, objeví se tady. Poslední tik v \($0)." }
                    ?? "Až po tobě někdo bude chtít review, objeví se tady."
            )
        case .poll(.failure(let reason)):
            EmptyStateView(
                nature: .failure,
                symbol: "exclamationmark.triangle",
                title: "Seznam PR se nepodařilo načíst",
                message: "Zkusím to znovu při dalším tiku.",
                // Syrový text od `gh` zůstává — je to jediné, z čeho se pozná, co dělat dál.
                detail: reason.userDescription,
                primary: .init(title: "Zkusit znovu") { Task { await store.refresh() } }
            )
        case .poll(.rateLimited(let retryAt)):
            EmptyStateView(
                // Čekání, ne porucha: nic se nerozbilo, jen se aplikace ptala moc.
                nature: .waiting,
                symbol: "hourglass",
                title: "GitHub omezuje dotazy",
                message: "Zkusím to znovu v \(retryAt.formatted(date: .omitted, time: .shortened)). Seznam zůstává takový, jaký dorazil naposled."
            )
        // **Nenastavená aplikace není uklizený stůl** (#331). Bez zdroje `author:@me is:open` se
        // aplikace na vlastní PR vůbec neptá, takže „nic tu není“ by byla nepravda o mojí práci.
        // Konfigurace se kvůli tomu nemigruje (#330), a tohle je to místo, které to má říct.
        case .ownSourceMissing:
            EmptyStateView(
                nature: .waiting,
                symbol: "text.badge.plus",
                title: "Vlastní PR se nesledují",
                // Dotaz je v textu vypsaný celý a **bez zpětných apostrofů**: `EmptyStateView`
                // sází `Text(verbatim:)`, takže by se nakreslily jako znaky.
                message: "Mezi zdroji chybí dotaz na moje pull requesty: author:@me is:open. Dopiš si ho v nastavení a objeví se tady.",
                primary: .init(title: "Otevřít nastavení", run: openSettings)
            )
        // Login se nedotáhl (`gh api user`), takže je podle autora všechno cizí (#330). Prázdno
        // proto neznamená „nic nemám“, ale „nevím, kdo jsem“ — a to se nesmí slít.
        case .unknownViewer:
            EmptyStateView(
                nature: .waiting,
                symbol: "person.crop.circle.badge.questionmark",
                title: "Nevím, kdo jsi",
                message: "Login přihlášeného účtu se nepodařilo zjistit, takže se nedá poznat, které PR jsou tvoje. Zkontroluj přihlášení v gh a spusť aplikaci znovu."
            )
        case .noOwnPullRequests:
            EmptyStateView(
                nature: .calm,
                symbol: "checkmark",
                title: "Nic vlastního otevřeného",
                message: RailSection.mine.emptyExplanation
            )
        }
    }

    /// Věta u schovaného seznamu. **Na sekci jiná**: „čeká na review“ o vlastních PR nemluví —
    /// u nich je moje práce opravit a pushnout, ne odpovědět.
    private func filteredMessage(_ hidden: Int) -> String {
        switch scope {
        case .queue:
            "\(Plural.czech(hidden, one: "pull request čeká", few: "pull requesty čekají", many: "pull requestů čeká")) na review, ale filtr je schovává."
        case .mine:
            "Filtr schovává \(Plural.czech(hidden, one: "tvůj otevřený pull request", few: "tvoje otevřené pull requesty", many: "tvých otevřených pull requestů"))."
        }
    }

    /// Kdy naposledy tik prošel — do věty prázdného stavu, jak to má návrh. `nil`, dokud
    /// se nepovedl ani jeden: „poslední tik nikdy“ by nebyla informace.
    private var lastTick: String? {
        store.lastSuccess?.formatted(date: .omitted, time: .shortened)
    }

    private var list: some View {
        // Stavy se čtou **tady**, ne až uvnitř řádku: `List` staví řádky líně a mimo
        // sledování závislostí rodiče, takže změna stavu by seznam nemusela překreslit.
        // Platí to i pro rozdělané review a pro odvozená čísla z #172 — bez toho by indikátor
        // naskočil až po překreslení z jiného důvodu.
        // **Zúžený seznam, ne `pullRequests`** (#117): filtr je pohled, takže se ho smí dotknout
        // jedině seznam a detail vybraného řádku. Cokoli dalšího nad zúženým seznamem by ze
        // zapnutí filtru udělalo mazání cache — viz `AppStore.pullRequests`. Rozřazení podle
        // autora (#331, #332) je **další zúžení nad tímtéž**, ne nový zdroj pravdy.
        let rows = summaries.map {
            ListRow(
                pullRequest: $0,
                state: store.reviewState(for: $0.id),
                hasDraft: store.hasDraft($0.id),
                summary: store.queueRow(for: $0.id),
                ownership: store.ownership(of: $0)
            )
        }

        // Výběr otevře **záložku** (#180): seznam je rozcestník, ne polovina okna, takže
        // kliknutí má PR otevřít, ne ho jen označit vedle diffu.
        return List(rows, selection: selectionOpeningTab) { row in
            PullRequestRow(
                pullRequest: row.pullRequest,
                reviewState: row.state,
                hasDraft: row.hasDraft,
                row: row.summary,
                ownership: row.ownership,
                // `Prompt →` (#333) — otevře PR a v něm panel `Zadání`. Store se tady drží, takže
                // uzávěr nese jen identitu řádku; skládání textu je věc panelu, ne seznamu.
                openPrompt: { store.openAgentPrompt(in: row.id) }
            )
        }
    }

    /// Obě sekce stojí na **zúžených** getterech (#332): filtr, pak autor. `visiblePullRequests`
    /// (celý pohled) tady schválně nefiguruje — po #332 by ve frontě kreslil i vlastní PR, které
    /// je hned pod ní ve své sekci.
    private var summaries: [PullRequestSummary] {
        switch scope {
        case .queue: store.visibleQueuePullRequests
        case .mine: store.visibleOwnPullRequests
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

    /// Co seznam o jednom řádku ví. Pojmenovaný typ, ne čtveřice: od #172 se skládá z pěti
    /// věcí a `\.0.id` v `List`u by přestalo jít přečíst.
    private struct ListRow: Identifiable {
        let pullRequest: PullRequestSummary
        let state: ReviewState
        let hasDraft: Bool
        let summary: QueueRow
        /// Čí PR to je (#331) — u vlastního má řádek vpravo `Prompt →` místo verdiktu. Čte se
        /// **tady**, ne v řádku: řádek nemá store a `List` ho staví líně.
        let ownership: PullRequestOwnership

        var id: PRIdentifier { pullRequest.id }
    }
}
