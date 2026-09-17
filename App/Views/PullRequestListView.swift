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
            // Blok `Odložené` (#512) — **na `content`, ne na `list`**, a je to celý smysl téhle
            // věci: musí být vidět i nad **prázdným** seznamem. Fronta, ve které je odložené
            // všechno, je zrovna ten stav, ve kterém by tichá díra bolela nejvíc.
            .safeAreaInset(edge: .bottom, spacing: 0) { snoozedBlock }
    }

    /// Blok `Odložené · 2` pod frontou (#512). V sekci `Moje PR` se nekreslí — vlastní PR se
    /// odložit nedá (`Policy.canSnooze`), takže by tam byl vždycky prázdný.
    @ViewBuilder private var snoozedBlock: some View {
        if scope == .queue {
            SnoozedBlockView(
                pullRequests: store.snoozedQueuePullRequests,
                // Kolik odložených schoval filtr — jinak by `do fronty →` z desky (kde se počítá
                // před filtrem) vedlo na menší číslo bez vysvětlení. Tatáž slovní zásoba jako
                // u prázdného stavu `filtered(hidden:)`.
                hidden: store.hiddenSnoozedPullRequestCount,
                note: store.snoozeNote(for:),
                open: { store.openTab($0) },
                wake: { pr in Task { await store.wake(pr) } }
            )
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
        // Fronta prázdná **není** — všechno je odložené (#512). Vlastní věta, ne `Žádné PR
        // k review`: zelené „vyřízeno“ nad prací, kterou jsem si sám schoval, tvrdí opak toho, co
        // je pravda. Tlačítko tu není schválně — blok `Odložené` visí hned pod tímhle stavem,
        // takže cesta zpátky je na obrazovce vidět, ne schovaná za akci.
        case .allSnoozed(let count):
            EmptyStateView(
                nature: .waiting,
                symbol: "alarm",
                title: "Všechno odložené",
                message: snoozedMessage(count)
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

    /// Věta u fronty, ze které je všechno odložené (#512). Říká **kolik** a **kde to je** —
    /// samotné „všechno odložené“ by neřeklo, že se s tím dá něco udělat.
    private func snoozedMessage(_ count: Int) -> String {
        let subject = Plural.czech(
            count,
            one: "pull request čeká",
            few: "pull requesty čekají",
            many: "pull requestů čeká"
        )
        return "\(subject) na review, ale odložil jsem je. Vrátit je jde v bloku Odložené pod seznamem."
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
        // Série a popisky nad skupinami (#513) — **jednou na seznam, ne dotazem na řádek**:
        // `Policy.series` je jeden průchod se slovníkem, a ptát se na něj u každého řádku by tu
        // práci udělalo tolikrát, kolik je řádků. Popisky se počítají nad `summaries`, tedy nad
        // tím, co seznam doopravdy kreslí — nad členem, kterého schoval filtr nebo odložení,
        // popisek nevznikne.
        //
        // **Pilulka se počítá v obou sekcích, popisek jen ve frontě**: stát na cizí větvi je
        // vlastnost pull requestu (vlastní PR můžou být stohované stejně jako cizí, a na desce se
        // jim pilulka kreslí), kdežto popisek tvrdí něco o pořadí v seznamu — a to drží jedině
        // fronta, protože jedině ona členy přeskládá.
        let series = store.pullRequestSeries
        let captions = scope == .queue ? store.queueSeriesCaptions : [:]
        let rows = summaries.map { summary -> ListRow in
            let ownership = store.ownership(of: summary)
            // **Jen u vlastních PR** (#334, #335) a **jeden report na řádek**: skládá položky zadání
            // (nálezy i celou konverzaci), takže dvě volání kvůli pilulce a textu novinek by byla
            // tatáž práce dvakrát — a `List` řádky staví při každém překreslení. U cizího řádku se
            // nekreslí ani jedno, takže se nepočítá nic.
            let handoff = ownership == .mine ? store.handoffReport(for: summary.id) : .never
            return ListRow(
                pullRequest: summary,
                state: store.reviewState(for: summary.id),
                hasDraft: store.hasDraft(summary.id),
                summary: store.queueRow(for: summary.id),
                // Mapa PR do mini pásu (#502) — **čte se tady, ne v řádku**, ze stejného důvodu
                // jako stavy: `List` staví řádky líně a mimo sledování závislostí rodiče, takže
                // by se pás po doběhnutí review nemusel překreslit. `nil` u PR, o kterém se pás
                // nemá z čeho složit; rozhoduje o tom store, protože jedině on ví, co je načtené.
                map: store.queueMap(for: summary.id),
                ownership: ownership,
                pending: handoff.pending,
                activity: handoff.activity,
                // Dráha smyčky do řádku (#509) — **z už spočítaného reportu**, ne podruhé:
                // `Policy.handoff` je nejdražší vstup dráhy a řádek si ho skládá o dva řádky výš.
                // Vlastnictví se ptá **tady**, ne uvnitř: je to týž předfiltr jako u `handoff`u
                // a na cizím řádku by dráha byla práce za odpověď, kterou nikdo nenakreslí.
                loop: ownership == .mine ? store.ownLoopRow(for: summary, handoff: handoff) : nil,
                series: Policy.seriesPlacement(
                    of: summary.id,
                    in: series,
                    refs: store.branchRefs(for:)
                ),
                seriesCaption: captions[summary.id]
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
                map: row.map,
                ownership: row.ownership,
                // `Prompt →` (#333) — otevře PR a v něm panel `Zadání`. Store se tady drží, takže
                // uzávěr nese jen identitu řádku; skládání textu je věc panelu, ne seznamu.
                openPrompt: { store.openAgentPrompt(in: row.id) },
                pending: row.pending,
                activity: row.activity,
                // Agent na vlastním PR (#511) — **jeden řádek, jedna podoba**, tedy i tady:
                // z pilulky se pozná, že nad PR běží něco, co jsem nespustil, nebo že v kopii repa
                // leží commit k přetlačení.
                agent: store.agentRowPill(for: row.pullRequest),
                // Odložit (#512) — jedna hodnota z jednoho místa (`AppStore.snoozeAction(for:)`),
                // stejně jako na desce a v sekci `Rozdělaná`. Brána `Policy.canSnooze` je uvnitř,
                // takže na vlastním řádku přijde prázdná nabídka a nenakreslí se nic.
                snoozeAction: store.snoozeAction(for: row.pullRequest),
                loop: row.loop,
                // Série (#513) — pilulka v řádku a popisek nad skupinou. **Jediné místo, kde se
                // popisek kreslí**: fronta je jediný seznam, ve kterém členové drží pohromadě
                // (`visibleQueuePullRequests` je přeskládá) a nic se z něj neořezává.
                series: row.series,
                seriesCaption: row.seriesCaption
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
        /// Mapa PR do mini pásu (#502). `nil` = pás se nekreslí.
        let map: PullRequestMap?
        /// Čí PR to je (#331) — u vlastního má řádek vpravo `Prompt →` místo verdiktu. Čte se
        /// **tady**, ne v řádku: řádek nemá store a `List` ho staví líně.
        let ownership: PullRequestOwnership
        /// Kolik zbývá předat agentovi (#334). Ze stejného důvodu tady: `Policy.handoff` potřebuje
        /// razítko, nálezy a konverzaci, tedy store.
        let pending: Int
        /// Co od minule udělal někdo jiný (#335) — z **téhož** reportu jako `pending`.
        let activity: ForeignActivity
        /// Dráha smyčky vlastního PR (#509). `nil` na cizím — a z **téhož** reportu jako
        /// `pending`, takže se `Policy.handoff` na řádek počítá pořád jednou.
        let loop: OwnLoopRow?
        /// Kde v sérii ten PR stojí (#513). `nil` = v žádné není.
        let series: SeriesPlacement?
        /// Popisek nad skupinou. `nil` = tenhle řádek ho nedostane.
        let seriesCaption: String?

        var id: PRIdentifier { pullRequest.id }
    }
}
