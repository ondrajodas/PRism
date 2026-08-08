import SwiftUI

/// Pravý panel: diff vybraného PR, nálezy pod ním a ovládání nahoře.
///
/// Diff dostává plnou šířku — PHP na 120 znaků se má vejít. Bubliny nálezů u kódu jsou
/// #19, tabulka nálezů #20; zatím je pod diffem surový seznam.
struct PullRequestDetailView: View {
    let store: AppStore
    let pullRequest: PullRequestSummary

    /// Rozbalený panel nálezů. Je to předvolba pohledu, ne údaj o PR, takže **smí**
    /// přetéct mezi pull requesty — na rozdíl od stavu pracovní kopie, který se proto
    /// drží ve store.
    @State private var findingsExpanded = true

    /// Řádek diffu, na který se má odscrollovat po kliknutí na nález.
    @State private var scrollTarget: String?

    /// Místo, na které se právě skočilo. Zvýraznění po chvíli zhasne — trvalý rámeček by
    /// se pletl s blokujícím nálezem.
    @State private var highlighted: FindingHighlight?

    /// Reviewery, jejichž nálezy jsou schované. Filtr je pohled, ne údaj o PR, takže
    /// **smí** přetéct mezi pull requesty — jméno skillu znamená všude totéž.
    @State private var mutedReviewers: Set<String> = []

    /// Který tab spodního panelu je vidět. Drží ho detail, ne panel: poznámka přidaná
    /// z diffu do těla review se musí umět přepnout na tab, kam spadla.
    @State private var panelTab: FindingsPanel.Tab = .findings

    /// Rozdělané odeslání review. Zakládá se tady, ale **drží ho `ContentView`** — detail
    /// zmizí, jakmile PR vypadne ze seznamu, a odeslané review `review-requested` ruší, takže
    /// se to na příštím tiku stane. Sheet by tím zmizel i s hláškou, kvůli které je otevřený.
    @Binding var submission: ReviewSubmission?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            // Záložky nesou vlastní linku po celé šířce, takže samostatný `Divider()` mezi
            // hlavičkou a obsahem by byl druhá čára pod sebou.
            tabs
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: highlighted) {
            guard highlighted != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            highlighted = nil
        }
        // Klon je jeden pro celé repo, takže druhé PR ze stejného repa může mít hotovo,
        // aniž by o tom kdo řekl. Zjistí se to při výběru řádku, ne klonováním.
        .task(id: pullRequest.id) { await store.noteExistingCheckout(for: pullRequest.id) }
        // Návštěva se zapisuje **při zobrazení**, ne až po načtení konverzace: kdyby se čekalo
        // na data, PR otevřený bez sítě by se za viděný nepovažoval a banner by příště ukázal
        // i to, co jsem už četl.
        .task(id: pullRequest.id) { store.noteVisit(to: pullRequest.id) }
        // Klíčem je celé shrnutí, ne jen identifikátor: nový commit změní `updatedAt`,
        // a to je přesně chvíle, kdy se má diff načíst znovu i bez přepnutí PR.
        .task(id: pullRequest) { await store.loadDiff(for: pullRequest) }
        // Konverzace stejnou cestou jako diff, ne pollingem: pro všech N PR by to byla
        // tatáž N+1 past, kvůli které se netahá ani detail.
        .task(id: pullRequest) { await store.loadConversation(for: pullRequest) }
        // A detail taky — z něj je `headSha`, proti kterému se píše rozdělané review a proti
        // kterému se pozná, že zastaralo.
        .task(id: pullRequest) { await store.loadDetail(for: pullRequest) }
    }

    /// Dva řádky, ne čtyři bloky: cesta ke klonu, stav kopie i spuštění review se vejdou
    /// vedle titulku. Místo v okně patří diffu.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(pullRequest.title)
                    .font(.title3)
                    .lineLimit(2)
                Spacer(minLength: 12)
                review
            }
            HStack(spacing: 10) {
                Text(pullRequest.id.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link("otevřít na GitHubu", destination: pullRequest.url).font(.callout)
                checkout
                draftChip
            }
            reviewers
            // Selhání checkoutu se do lišty nevejde, a právě u něj je text od `gitu`
            // to jediné, z čeho se pozná, co dělat dál.
            if case .failed(let detail) = store.checkoutState(for: pullRequest.repo) {
                checkoutFailure(detail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Záložky na úrovni PR. Sedí **pod hlavičkou**, ne nad ní: titulek, stav kopie
    /// i spuštění review platí pro obojí, takže by se v každém tabu musely kreslit znovu.
    ///
    /// Odznak u `Přehledu` říká, kolik je toho k přečtení.
    private var tabs: some View {
        PullRequestTabBar(selection: tabSelection) { tab in
            // Jen to, co je **k přečtení** — události časové osy se nepočítají (#171), jinak by
            // na PR s dvaceti commity odznak ukazoval třicet a přestal by o diskuzi něco říkat.
            tab == .overview ? store.overview(for: pullRequest.id).count { $0.isReadable } : nil
        }
    }

    /// Volba tabu žije ve store (per PR), takže si ji vlastní binding jen podává dál.
    private var tabSelection: Binding<PullRequestTab> {
        Binding(
            get: { store.detailTab(for: pullRequest.id) },
            set: { store.setDetailTab($0, for: pullRequest.id) }
        )
    }

    /// Obsah vybraného tabu a pod ním spodní panel.
    ///
    /// Panel je vidět **vždycky**, i u PR, na kterém review nikdy neběželo (**změna proti
    /// #20**): od #66 v něm bydlí i rozdělané review, a to se zakládá od nuly. Kdyby se panel
    /// ukazoval až s prvním nálezem, nebylo by kde vybrat verdikt ani napsat tělo.
    ///
    /// A je vidět **v obou tabech**, ne jen u diffu (**doplněno proti zadání #72**, které
    /// psalo, že `Změněné soubory` jsou dnešní obrazovka beze změny — v té době ještě panel
    /// draft neobsahoval). Nálezy bez místa v kódu, průběh běhu i moje rozdělané review se
    /// vážou k celému PR, ne k diffu; schovat je za přepnutí tabu by znamenalo, že se
    /// rozepsané review přepnutím na `Přehled` „ztratí“.
    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            switch store.detailTab(for: pullRequest.id) {
            case .filesChanged: diff
            case .overview: overview
            }
            // Panel se ukáže i **bez** záznamu, jakmile něco běží: při prvním review je
            // průběh to jediné, co je, a čekat na uložený výsledek by ho schovalo.
            let record = store.reviewRecord(for: pullRequest.id)
            FindingsPanel(
                record: record,
                // `nil` = není co zahodit. Rozhoduje uložený záznam, ne to, co je vidět
                // po filtru reviewerů — filtr je pohled, ne obsah.
                clear: record == nil ? nil : { try await store.clearFindings(for: pullRequest.id) },
                isExpanded: $findingsExpanded,
                jump: jump,
                findings: visibleFindings,
                dismissals: dismissals,
                findingActions: findingActions,
                blockingCategories: blockingCategories,
                timelines: store.timelines(for: pullRequest.id),
                isRunning: store.isReviewing(pullRequest.id),
                pullRequest: pullRequest.id,
                draft: store.draft(for: pullRequest.id),
                // Verdikt jde vedle draftu, ne z něj: předvyplněný návrh (#114) se neukládá,
                // takže v draftu není a panel by nad ním ukazoval „nevybráno“.
                draftVerdict: store.effectiveVerdict(for: pullRequest.id),
                isDraftStale: store.isDraftStale(for: pullRequest.id),
                isOwnPullRequest: store.isOwnPullRequest(pullRequest.id),
                draftUnavailable: draftUnavailable,
                draftActions: draftActions,
                jumpToComment: jumpToComment,
                tab: $panelTab
            )
            // Panel si o místo říká **první**: má vlastní strop (výšku, kterou si uživatel
            // vytáhl), takže víc než ten si nevezme — a zbytek dostane diff, který se umí
            // stáhnout na nulu. Bez priority dělí `VStack` místo mezi dva pružné prvky
            // rovnoměrně a v nízkém okně vyjde panel na půlku obrazovky.
            .layoutPriority(1)
        }
    }

    /// Chipy reviewerů a návrh verdiktu. Ukazují se, jakmile je co říct — u PR, na kterém
    /// review nikdy neběželo, by to byl jen řádek prázdných odznaků.
    @ViewBuilder private var reviewers: some View {
        let record = store.reviewRecord(for: pullRequest.id)
        if record != nil || store.isReviewing(pullRequest.id) {
            HStack(spacing: 12) {
                ReviewerChipsView(
                    chips: Policy.chips(
                        for: record,
                        skills: store.reviewSkills(for: pullRequest.repo),
                        running: store.runningReviewers(for: pullRequest.id)
                    ),
                    muted: $mutedReviewers,
                    // Opakování jednoho revieweera (#149). Ostatní běhy zůstávají uložené,
                    // takže se za ně neplatí znovu.
                    rerun: { store.startReview(for: pullRequest.id, skills: [$0]) },
                    isReviewing: store.isReviewing(pullRequest.id)
                )
                Spacer(minLength: 12)
                if let record {
                    VerdictView(record: record, blockingCategories: blockingCategories)
                }
            }
            .padding(.top, 2)
        }
    }

    /// Co se na tomhle repu považuje za blokující. Bere se z konfigurace, ne z konstanty
    /// v `Policy` — právě kvůli tomu je to jediný knoflík, kterým se doladí, co je vážné.
    private var blockingCategories: Set<String> {
        store.resolved(for: pullRequest.repo).blockingCategories
    }

    /// Nálezy po odfiltrování ztlumených reviewerů. Verdikt se tím **nemění** — filtr je
    /// pohled, ne tvrzení o pull requestu.
    ///
    /// Odmítnuté (#113) tady zůstávají: filtr reviewerů schovává, odmítnutí ztlumuje. Kdyby
    /// se odmítnuté vyřadily už tady, zmizely by z okna — a schovaný nález se nedá odlišit od
    /// neexistujícího, natož zkontrolovat.
    private var visibleFindings: [Finding] {
        (store.reviewRecord(for: pullRequest.id)?.findings ?? [])
            .filter { !mutedReviewers.contains($0.reviewer) }
    }

    /// Jak jsem nálezy posoudil. Bere se z uloženého záznamu, ne z filtru — je to obsah,
    /// ne pohled.
    private var dismissals: [FindingKey: FindingDismissal] {
        store.reviewRecord(for: pullRequest.id)?.dismissals ?? [:]
    }

    /// Odmítnutí nálezu (#113) — jedno místo pro bubliny u kódu i pro tabulku v panelu.
    private var findingActions: FindingActions {
        let id = pullRequest.id
        return FindingActions(
            dismiss: { finding, reason in
                Task { await store.dismissFinding(finding, as: reason, for: id) }
            },
            restore: { finding in
                Task { await store.restoreFinding(finding, for: id) }
            }
        )
    }

    /// Pohled na diff. Žije ve store (globálně, do zavření aplikace), takže si ho vlastní
    /// binding jen podává dál — stejně jako volbu tabu.
    private var diffLayout: Binding<DiffLayout> {
        Binding(get: { store.diffLayout }, set: { store.setDiffLayout($0) })
    }

    /// Rozbaluje se obsah souboru **na hlavě PR**, takže u přejmenovaného souboru platí
    /// nová cesta — a `displayPath` je právě ona.
    private var expansionActions: DiffExpansionActions {
        DiffExpansionActions(
            state: { store.expansion(of: $0.displayPath, in: pullRequest.id) },
            reveal: { store.reveal($1, of: $0.displayPath, in: pullRequest.id) },
            collapse: store.hasRevealedLines(in: pullRequest.id)
                ? { store.collapseRevealedLines(in: pullRequest.id) }
                : nil
        )
    }

    // MARK: - Rozdělané review

    /// Indikátor rozdělaného review v detailu — a zkratka do tabu, kde se píše.
    ///
    /// Slovu „draft“ se v textu vyhýbá schválně: tím se v tomhle okně označuje **rozpracovaný
    /// pull request** (chip v řádku seznamu), což je něco úplně jiného.
    @ViewBuilder private var draftChip: some View {
        if store.hasDraft(pullRequest.id) {
            let isStale = store.isDraftStale(for: pullRequest.id)
            Button {
                showDraftTab()
            } label: {
                Label(
                    isStale ? "rozdělané review · starší commit" : "rozdělané review",
                    systemImage: "square.and.pencil"
                )
                .font(.callout)
                .foregroundStyle(isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(isStale
                ? "Review je psané proti staršímu commitu — takhle se odeslat nedá"
                : "Otevřít tab Moje review")
        }
    }

    /// Proč se do rozdělaného review nedá psát. `nil` = dá se.
    ///
    /// Bez `headSha` nemá draft proti čemu vzniknout, a mlčky zakázaná tlačítka vypadají jako
    /// rozbitá aplikace. Rozepsaného draftu se to netýká — ten svůj commit už zná.
    private var draftUnavailable: String? {
        guard !store.canComposeDraft(for: pullRequest.id) else { return nil }
        if case .failed(let detail) = store.detailState(for: pullRequest.id) {
            return "Nevím, na kterém commitu PR stojí, takže se review nemá k čemu psát. \(detail)"
        }
        return "Zjišťuji, na kterém commitu PR stojí…"
    }

    private var draftActions: DraftActions {
        let id = pullRequest.id
        return DraftActions(
            canCompose: store.canComposeDraft(for: id),
            addComment: { path, anchor in store.addDraftComment(at: anchor, path: path, for: id) },
            extendComment: { path, anchor in store.extendDraftComment(to: anchor, path: path, for: id) },
            dragRange: { path, from, to in
                store.dragCommentRange(path: path, from: from, to: to, for: id)
            },
            endRangeDrag: { store.finishCommentRange() },
            draggedRange: store.commentDrag.map { (path: $0.path, anchor: $0.anchor) },
            addNote: { path, line in
                store.appendDraftBodyItem(text: "", path: path, line: line, for: id)
                showDraftTab()
            },
            adopt: { finding in
                // Kam nález spadl, se musí poznat: řádkový komentář je vidět hned pod
                // řádkem, kdežto položka v těle je jinde v okně, takže se na ni přepne.
                let goesToBody: Bool = if case .body = store.draftTarget(for: finding, in: id) {
                    true
                } else {
                    false
                }
                store.adoptFinding(finding, for: id)
                if goesToBody { showDraftTab() }
            },
            isAdopted: { store.isAdopted($0, in: id) },
            target: { store.draftTarget(for: $0, in: id) },
            updateComment: { store.updateDraftComment($0, body: $1, for: id) },
            removeComment: { store.removeDraftComment($0, for: id) },
            setBody: { store.setDraftBody($0, for: id) },
            setVerdict: { store.setDraftVerdict($0, for: id) },
            discard: { store.discardDraft(for: id) },
            // Otevře sheet, nic neodesílá. `submission(for:)` vrátí `nil`, když odeslat
            // nejde — nad zastaralým draftem se tedy sheet neotevře ani omylem.
            send: { submission = store.submission(for: pullRequest) },
            sendBlock: store.draftSendBlock(for: id),
            // Zastaralý draft se dá poslat **po kontrole kotev v tomtéž okně** (#69), takže
            // tlačítko není zakázané — jen se jinak jmenuje. Bez diffu nebo bez známé hlavy PR
            // není proti čemu kontrolovat a zůstává zakázané s důvodem.
            canTransfer: store.canTransferDraft(for: id)
        )
    }

    private func showDraftTab() {
        panelTab = .draft
        findingsExpanded = true
    }

    /// Skok na můj komentář v diffu.
    ///
    /// Vlastní cesta, ne `jump(to finding:)`: komentář k odebranému řádku má číslo ze staré
    /// verze souboru, takže kotva podle nového čísla by skončila u hlavičky souboru.
    ///
    /// Pohled se předává, protože **na něm identita řádku závisí**: ve split pohledu je
    /// odebraný řádek slitý do dvojice, jejíž id je z pravé strany. Skok z nálezu ho naopak
    /// nepotřebuje — ten hledá podle nového čísla, a to je vpravo v obou pohledech.
    private func jumpToComment(_ comment: ReviewDraftComment) {
        guard case .loaded(let diff, _) = store.diffState(for: pullRequest.id),
              let file = diff.file(at: comment.path),
              let anchor = DiffRow.anchor(in: diff, comment: comment, layout: store.diffLayout)
        else { return }
        store.unfold(file.displayPath, in: pullRequest.id)
        scroll(to: anchor)
    }

    /// Odscrolluje diff na místo — a **přepne se do něj**, když je vidět `Přehled`.
    ///
    /// Bez toho kliknutí na nález v `Přehledu` neudělalo nic: diff v tu chvíli v okně vůbec
    /// není, takže se nemá kde scrollovat. Přepnout tab je správnější než kliknutí ignorovat —
    /// kdo klikne na nález, chce vidět ten kód.
    private func scroll(to anchor: String) {
        store.setDetailTab(.filesChanged, for: pullRequest.id)
        scrollTarget = anchor
    }

    private var foldingActions: DiffFoldingActions {
        DiffFoldingActions(
            isFolded: { store.isFolded($0.displayPath, in: pullRequest.id) },
            toggle: { store.toggleFolded($0.displayPath, in: pullRequest.id) },
            foldAll: { store.foldAll($0.map(\.displayPath), in: pullRequest.id) },
            unfoldAll: { store.unfoldAll(in: pullRequest.id) }
        )
    }

    /// Nález ukazuje na `file:line`; kde to je v diffu, ví `DiffRow`. Když se místo najít
    /// nedá (soubor v diffu není), nestane se nic — skákat naslepo je horší než nehnout se.
    private func jump(to finding: Finding) {
        guard case .loaded(let diff, _) = store.diffState(for: pullRequest.id),
              let path = finding.file,
              // Rozbalený kontext je uložený pod **novou** cestou souboru, kdežto nález umí
              // přijít pod starou. Bez překladu by kotva u přejmenovaného souboru rozbalený
              // kontext neviděla a skok by spadl na hlavičku.
              let file = diff.file(at: path),
              let anchor = DiffRow.anchor(
                  in: diff,
                  file: path,
                  line: finding.line,
                  revealed: store.expansion(of: file.displayPath, in: pullRequest.id).revealed
              )
        else { return }
        // Sbalený soubor nemá řádky, takže by skok skončil nikde. Rozbalit se musí
        // **předtím**, než se nastaví cíl — jinak `scrollTo` míří na id, které v líném
        // seznamu ještě není.
        store.unfold(file.displayPath, in: pullRequest.id)
        scroll(to: anchor)
        // Zvýraznění se porovnává s tím, co nahlásil reviewer, ne s cestou v diffu — bublina
        // nese jeho `file`, ne `displayPath`.
        highlighted = FindingHighlight(file: path, line: finding.line)
    }

    /// Co se dá dělat s vlákny (#73) — jedno místo pro diff i `Přehled`, ať se v jednom
    /// z nich nezapomene.
    ///
    /// `block` je věta, proč odesílat nejde. Skládá se z `PublishError`, aby okno hlásilo
    /// **tentýž** důvod, na kterém by odeslání doopravdy skončilo — stejná úvaha jako
    /// u `DraftSendBlock.publishingNotAllowed`, který si větu taky nepíše sám.
    private var threadActions: ThreadActions {
        ThreadActions(
            isExpanded: { store.isThreadExpanded($0, in: pullRequest.id) },
            toggle: { store.toggleThread($0, in: pullRequest.id) },
            reply: { store.threadReply(for: $0.id, in: pullRequest.id) },
            setReply: { store.setThreadReply($1, for: $0.id, in: pullRequest.id) },
            send: { thread in
                Task { await store.sendThreadReply(to: thread, in: pullRequest) }
            },
            setResolved: { thread, resolved in
                Task { await store.setThreadResolved(resolved, of: thread, in: pullRequest) }
            },
            state: { store.threadState(for: $0.id, in: pullRequest.id) },
            block: store.canPublishToThreads(in: pullRequest.repo)
                ? nil
                : PublishError.publishingNotAllowed(pullRequest.repo).userDescription
        )
    }

    /// Tab `Přehled` — popis PR a konverzace bez kotvy v diffu.
    private var overview: some View {
        OverviewView(
            description: store.description(of: pullRequest.id),
            entries: store.overview(for: pullRequest.id),
            state: store.conversationState(for: pullRequest.id),
            viewer: store.conversation(for: pullRequest.id)?.viewer ?? "",
            missing: store.conversation(for: pullRequest.id).map(ConversationShortfall.init)
                ?? ConversationShortfall(),
            threadActions: threadActions,
            refresh: { Task { await store.refreshConversation(for: pullRequest) } },
            changes: store.changesSinceLastVisit(for: pullRequest.id),
            lastVisit: store.visitSnapshots[pullRequest.id],
            // Obojí je „to, co mám na obrazovce, už neplatí“, takže se do banneru slévá do
            // jedné věty — rozdíl mezi zastaralými nálezy a zastaralým draftem se řeší
            // v panelu, kde se s nimi něco dělá.
            isStale: store.reviewRecord(for: pullRequest.id)?.isStale == true
                || store.isDraftStale(for: pullRequest.id),
            rerun: { store.startReview(for: pullRequest.id) },
            dismissChanges: { store.markChangesAsSeen(for: pullRequest.id) },
            pullRequest: pullRequest
        )
    }

    @ViewBuilder private var diff: some View {
        switch store.diffState(for: pullRequest.id) {
        case .loaded(let diff, _) where diff.isEmpty:
            placeholder("Diff je prázdný — tenhle pull request nic nemění.")
        case .loaded(let diff, _):
            DiffView(
                diff: diff,
                scrollTarget: $scrollTarget,
                expansion: expansionActions,
                folding: foldingActions,
                findings: Policy.groups(of: visibleFindings, dismissals: dismissals),
                findingActions: findingActions,
                blockingCategories: blockingCategories,
                highlighted: highlighted,
                threads: store.anchoredThreads(for: pullRequest.id),
                missingThreads: store.conversation(for: pullRequest.id)?.threads.missing ?? 0,
                viewer: store.conversation(for: pullRequest.id)?.viewer ?? "",
                threadActions: threadActions,
                comments: store.draftComments(for: pullRequest.id),
                draft: draftActions,
                layout: diffLayout
            )
        case .failed(let detail):
            diffFailure(detail)
        case .loading, nil:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Načítám diff…")
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func diffFailure(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Diff se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(detail)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Zkusit znovu", systemImage: "arrow.clockwise") {
                Task { await store.loadDiff(for: pullRequest) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Spuštění a zrušení review. Tlačítko je tady, ne v toolbaru: patří k vybranému PR
    /// a v toolbaru by nebylo vidět, ke kterému.
    @ViewBuilder private var review: some View {
        if store.isReviewing(pullRequest.id) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(runningLabel)
                Button("Zrušit", systemImage: "stop.circle") {
                    store.cancelReview(for: pullRequest.id)
                }
            }
        } else {
            HStack(spacing: 12) {
                Button("Spustit review", systemImage: "play.circle") {
                    store.startReview(for: pullRequest.id)
                }
                if case .failed(let detail) = store.reviewPhases[pullRequest.id] {
                    Label(detail, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var runningLabel: String {
        switch store.reviewPhases[pullRequest.id] {
        case .running(let finished, let total): "Běží review — hotovo \(finished) z \(total)"
        default: "Připravuji pracovní kopii a stahuji commit…"
        }
    }

    /// Stav pracovní kopie jako jeden údaj v liště. Cesta ke klonu visí na nápovědě:
    /// potřeba je zřídka, ale jako samostatný řádek zabírala pruh, který patří diffu.
    ///
    /// Vždycky podle stavu ve store, nikdy podle vlastního `@State`. `PullRequestDetailView`
    /// si SwiftUI mezi PR drží (stejná pozice ve stromu), takže vlastní příznak by přetekl
    /// z jednoho pull requestu na druhý.
    @ViewBuilder private var checkout: some View {
        switch store.checkoutState(for: pullRequest.repo) {
        case .preparing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("připravuji kopii…")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        case .ready(let path):
            Label("kopie připravená", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.green)
                .help(path.path(percentEncoded: false))
        case .failed:
            EmptyView()   // vypisuje se celé pod lištou, viz `checkoutFailure`
        case .absent:
            Button("připravit kopii", systemImage: "arrow.down.circle", action: prepare)
                .buttonStyle(.link)
                .font(.callout)
        }
    }

    /// Vlastní rámeček místo `GroupBox`u: ten je AppKit kontejner a `ImageRenderer` ho
    /// nevykreslí, takže by tenhle stav nešlo zkontrolovat jinak než ručně v aplikaci.
    private func checkoutFailure(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pracovní kopii se nepodařilo připravit", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            // Text od `gitu` je to, z čeho se pozná, co dělat dál — proto celý
            // a k vybrání, ne zkrácený do jedné věty.
            Text(detail)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                // Bez `fixedSize` se dlouhý výstup `gitu` ořízne a nejde ani zkopírovat —
                // přitom právě z něj se pozná, co se stalo.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Zkusit znovu", systemImage: "arrow.clockwise", action: prepare)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: .rect(cornerRadius: 8))
    }

    private func prepare() {
        Task { await store.prepareCheckout(for: pullRequest.id) }
    }
}
