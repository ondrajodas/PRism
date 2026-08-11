import AppKit
import SwiftUI

/// Obsah záložky PR: hlavička, pruh záložek, obsah vybrané záložky a panel vpravo.
///
/// Diff dostává plnou šířku — PHP na 120 znaků se má vejít. Bubliny nálezů u kódu jsou #19,
/// tabulka nálezů v tabu `Nálezy` #242.
struct PullRequestDetailView: View {
    let store: AppStore
    let pullRequest: PullRequestSummary

    /// Řádek diffu, na který se má odscrollovat po kliknutí na nález.
    @State private var scrollTarget: String?

    /// Místo, na které se právě skočilo. Zvýraznění po chvíli zhasne — trvalý rámeček by
    /// se pletl s blokujícím nálezem.
    @State private var highlighted: FindingHighlight?

    /// Reviewery, jejichž nálezy jsou schované. Filtr je pohled, ne údaj o PR, takže
    /// **smí** přetéct mezi pull requesty — jméno skillu znamená všude totéž.
    @State private var mutedReviewers: Set<String> = []

    /// Kde jsem v procházení nálezů (#187).
    ///
    /// Na rozdíl od `mutedReviewers` **nesmí** přetéct mezi pull requesty: `file:line` z cizího
    /// PR je náhodná shoda, a „prošel jsi všechno“ se rozhoduje z toho, co je v tomhle diffu.
    /// Resetuje se proto při změně PR, viz `.task(id:)` níž.
    @State private var cursor = FindingCursor()

    /// Rozdělané odeslání review. Zakládá se tady, ale **drží ho `ContentView`** — detail
    /// zmizí, jakmile PR vypadne ze seznamu, a odeslané review `review-requested` ruší, takže
    /// se to na příštím tiku stane. Sheet by tím zmizel i s hláškou, kvůli které je otevřený.
    @Binding var submission: ReviewSubmission?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                controls
                // Záložky nesou vlastní linku po celé šířce, takže samostatný `Divider()` mezi
                // hlavičkou a obsahem by byl druhá čára pod sebou.
                tabs
            }
            // **Hlavička leží na `surface`, ne na pozadí okna** (#216). Návrh má
            // `.pr-head` i `.subtabs` na `--panel`; bez toho prosvítalo `background`
            // (skoro černá) a titulek s odznaky plaval v prázdnu nad plochou, na které
            // stojí obsah pod ním.
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .hiddenShortcuts { shortcuts }
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
        // Kurzor procházení patří k tomuhle diffu, ne k oknu — viz `cursor`.
        .task(id: pullRequest.id) { cursor = FindingCursor(onlyBlocking: cursor.onlyBlocking) }
        // Klíčem je celé shrnutí, ne jen identifikátor: nový commit změní `updatedAt`,
        // a to je přesně chvíle, kdy se má diff načíst znovu i bez přepnutí PR.
        .task(id: pullRequest) { await store.loadDiff(for: pullRequest) }
        // Konverzace stejnou cestou jako diff, ne pollingem: pro všech N PR by to byla
        // tatáž N+1 past, kvůli které se netahá ani detail.
        .task(id: pullRequest) { await store.loadConversation(for: pullRequest) }
        // A detail taky — z něj je `headSha`, proti kterému se píše rozdělané review a proti
        // kterému se pozná, že zastaralo.
        .task(id: pullRequest) { await store.loadDetail(for: pullRequest) }
        // Skok z palety (#184). Klíčem je **žádost i to, jak dopadl diff**: paleta umí skočit do
        // PR, jehož záložka se právě otevřela, takže diff v tu chvíli ještě není — a bez druhé
        // části klíče by se úloha po jeho dorazení už nespustila.
        .task(id: PaletteJumpAttempt(jump: store.paletteJump, isDiffSettled: isDiffSettled)) {
            consumePaletteJump()
        }
    }

    /// Žádost o skok a stav diffu jako jeden klíč `task(id:)`.
    private struct PaletteJumpAttempt: Hashable {
        let jump: CommandPalette.Jump?
        let isDiffSettled: Bool
    }

    /// Ví se už, jak diff dopadl? Načítání se od selhání musí lišit: po selhání se skok
    /// **nepovede nikdy**, takže se na něj nemá čekat.
    private var isDiffSettled: Bool {
        switch store.diffState(for: pullRequest.id) {
        case .loaded, .failed: true
        case .loading, nil: false
        }
    }

    /// Vyzvedne skok z palety a odscrolluje na něj.
    ///
    /// Dokud se diff načítá, **žádost se nechává ležet** — jinak by se zahodila zrovna
    /// v nejčastějším případě, kdy paleta otevřela novou záložku. Jakmile je jasno, žádost se
    /// vyzvedne v každém případě, i když z ní nic nebude: soubor, který v diffu není (přišel nový
    /// commit), ani nenačtený diff se druhým pokusem nespraví a nevyzvednutá žádost by tu zůstala
    /// viset jako stav, který nikdo nepřečte.
    private func consumePaletteJump() {
        guard let jump = store.paletteJump, jump.pullRequest == pullRequest.id else { return }
        guard isDiffSettled else { return }
        store.paletteJump = nil

        guard let anchor = anchor(inFile: jump.file, line: jump.line) else { return }
        // Rozbalí se a zvýrazní jen nález — u souboru by rámeček ukazoval na místo, kde žádný
        // nález není, a rozbalovat by nebylo co. Ve dvou krocích, protože `scroll(to:)`
        // zvýraznění **maže** (jedno místo pro všechny odskoky), takže se musí nastavit po něm —
        // kdežto bublina se rozbaluje před ním, ať kotva v líném seznamu vůbec je.
        if jump.kind == .finding { reveal(bubbleAt: jump.file, line: jump.line) }
        scroll(to: anchor)
        if jump.kind == .finding {
            highlighted = FindingHighlight(file: jump.file, line: jump.line)
        }
    }

    /// Tři řádky hlavičky, jak je má návrh (#218): titulek s číslem, souřadnice PR a pruh běhu.
    ///
    /// **Bez pravého sloupce.** Do #218 pod sebou stály `Spustit review` (fialové), `kopie
    /// připravená` (zelená) a `Návrh: request changes` (oranžová) — tři hlasité barvy, které
    /// z pravé strany hlavičky dělaly semafor a přebíjely titulek vlevo. Stav pracovní kopie se
    /// přestěhoval do stavového řádku (je to stav prostředí, ne údaj o PR), návrh verdiktu zmizel
    /// úplně (od #114 jím panel `Moje review` verdikt předvyplňuje, takže tady byl druhou kopií
    /// téhož) a zbylo jediné akcentové místo: `Spustit review`.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(pullRequest.title)
                    .font(.title3)
                    .lineLimit(2)
                // Číslo patří k titulku, ne dovnitř věty `owner/repo#4` (#218) — velké
                // a tlumené, jak ho má návrh. `verbatim`, jinak locale udělá z #21663
                // „#21 663“.
                Text(verbatim: "#\(pullRequest.number)")
                    .font(.title3)
                    .foregroundStyle(Palette.ink3)
                    .monospacedDigit()
                    .textSelection(.enabled)
                Spacer(minLength: 12)
                review
            }
            HStack(spacing: 10) {
                PullRequestHeaderView(
                    pullRequest: pullRequest,
                    detail: loadedDetail,
                    checks: store.checks[pullRequest.id] ?? []
                )
                draftChip
                Spacer(minLength: 8)
            }
            // Jen když se hlava rozešla se sha, proti které platí nálezy — jinak by to byl
            // řádek s údajem, který nikoho nezajímá.
            if let head = loadedDetail?.headSha,
               let findingsHead = store.reviewRecord(for: pullRequest.id)?.headSha,
               head != findingsHead {
                StaleHeadView(head: head, findingsHead: findingsHead, recheck: recheck)
            }
            // Proč kontrola nálezů (#150) neproběhla. **Vlastní řádek, ne nápověda u tlačítka:**
            // spadlá kontrola vypadá jinak než kontrola, která nic nenašla, a to druhé by se
            // čtlo jako „nálezy pořád platí“.
            if let failure = store.recheckFailures[pullRequest.id] {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Palette.crit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            reviewers
            // Selhání checkoutu se do lišty nevejde, a právě u něj je text od `gitu`
            // to jediné, z čeho se pozná, co dělat dál. **Zůstává v hlavičce**, i když se
            // ostatní stavy kopie stěhovaly do stavového řádku: porucha není stav prostředí.
            if case .failed(let detail) = store.checkoutState(for: pullRequest.repo) {
                checkoutFailure(detail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Záložky na úrovni PR. Sedí **pod hlavičkou**, ne nad ní: titulek, pruh běhu
    /// i spuštění review platí pro obojí, takže by se v každém tabu musely kreslit znovu.
    ///
    /// Odznak nese **každá** záložka (#218); co který počítá, je u `count(in:)`.
    private var tabs: some View {
        PullRequestTabBar(selection: tabSelection, badge: badge(in:))
            .diffCounts(loadedDiffCounts)
    }

    /// Odznak u záložky. `nil` = nedá se říct, takže se nekreslí nic — nula by tvrdila, že se
    /// spočítalo a vyšlo prázdno.
    ///
    /// **Každá záložka počítá něco jiného** (#218) a je to schválně: odznak odpovídá na otázku
    /// „kolik je toho tam“, a ta má v každém tabu jiný předmět.
    private func badge(in tab: PullRequestTab) -> PullRequestTabBadge? {
        switch tab {
        // Co přibylo od minule — tedy přesně to, čím `Přehled` začíná. Počet **všeho**, co
        // tab obsahuje, by byl konstanta (čtyři bloky) a neřekl by nic.
        case .overview: count(store.changesSinceLastVisit(for: pullRequest.id).count)
        // Soubory v diffu, ne řádky: `+X −Y` stojí o kus dál v téže liště.
        case .filesChanged: loadedDiff.flatMap { count($0.files.count) }
        // Jen to, co je **k přečtení** — události časové osy se nepočítají (#171), jinak by
        // na PR s dvaceti commity odznak ukazoval třicet a přestal by o diskuzi něco říkat.
        case .conversation: count(store.overview(for: pullRequest.id).count { $0.isReadable })
        // Počítá to **`Policy` z týchž nálezů**, jaké kreslí tabulka v tabu, karty v panelu
        // a bubliny v diffu (#242) — jeden zdroj, aby odznak nemohl tvrdit něco jiného, než
        // co je na obrazovce.
        case .findings: Policy.findingsBadge(of: findingsTally)
        // Puntík, ne počet: „běží“ je stav, ne množství — u dvou reviewerů by dvojka o průběhu
        // neřekla nic.
        case .progress: store.isReviewing(pullRequest.id) ? .live : nil
        }
    }

    /// Počet jako odznak. Nula se zahazuje **tady, na jednom místě** — jinak by se `> 0` psalo
    /// u každé záložky zvlášť a jednou by se zapomnělo.
    private func count(_ value: Int) -> PullRequestTabBadge? {
        value > 0 ? .count(value) : nil
    }

    /// Kolik je nálezů a kolik z nich blokuje. Bere se z **toho, co je vidět** (po filtru
    /// reviewerů), protože odznak má počítat obsah obrazovky, ne obsah souboru na disku.
    private var findingsTally: FindingsTally {
        Policy.tally(
            of: visibleFindings,
            dismissals: dismissals,
            categories: blockingCategories
        )
    }

    /// Načtený diff. `nil` u načítání i selhání — odznak ani rozsah změny si v obou případech
    /// prostě nekreslí, co ještě neví.
    private var loadedDiff: Diff? {
        guard case .loaded(let diff, _) = store.diffState(for: pullRequest.id) else { return nil }
        return diff
    }

    /// Rozsah změny pro záložky (#174). `nil`, dokud diff nedorazí — nuly by tvrdily,
    /// že PR nic nemění.
    private var loadedDiffCounts: (additions: Int, deletions: Int)? {
        loadedDiff.map { ($0.additions, $0.deletions) }
    }

    /// Načtený detail PR. `nil` u načítání i selhání — hlavička si v obou případech
    /// prostě nekreslí, co ještě neví.
    private var loadedDetail: PullRequest? {
        guard case .loaded(let detail, _) = store.detailState(for: pullRequest.id) else { return nil }
        return detail
    }

    /// Volba tabu žije ve store (per PR), takže si ji vlastní binding jen podává dál.
    private var tabSelection: Binding<PullRequestTab> {
        Binding(
            get: { store.detailTab(for: pullRequest.id) },
            set: { store.setDetailTab($0, for: pullRequest.id) }
        )
    }

    /// Složení panelu a jeho tab žijí **ve store** (#242), takže se sem jen podávají dál.
    ///
    /// Do #242 to byl `@State` detailu s odůvodněním, že je to předvolba pohledu. Pořád je —
    /// jen na obojím visí doručení poznámky do těla review, a to se musí dát otestovat.
    private var panelExpanded: Binding<Bool> {
        Binding(get: { store.isReviewPanelExpanded }, set: { store.isReviewPanelExpanded = $0 })
    }

    private var panelTab: Binding<ReviewPanelTab> {
        Binding(get: { store.reviewPanelTab }, set: { store.reviewPanelTab = $0 })
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
        // **Vedle sebe, ne pod sebou** (#182). Panel dole si bral výšku, které je v diffu
        // nejmíň; napravo bere šířku, které je v okně přes celou obrazovku dost.
        HStack(spacing: 0) {
            // **Plocha tabu je `surface` ve všech třech** (#216) — návrh má `.ovpane`,
            // `.diffpane` i `.convpane` na `--panel`. Bez toho prosvítalo `background`
            // (skoro černá) a obsah plaval v prázdnu. Panel vedle si maluje `chrome` sám,
            // takže se ho tohle netýká.
            // **Šířka se tady změří a pošle dolů** (#220). Je to ta hranice, za kterou obsah tabu
            // svou šířku **zná**, takže ji nemusí vyjednávat na každé vnořené úrovni — a právě to
            // vyjednávání zaseklo okno na velkém PR na 20 minut. Naměřeno: strom v hloubce 8 stál
            // 15 700 ms pružně a 2,2 ms s předanou šířkou. Podrobnosti u `AvailableWidth`.
            //
            // `GeometryReader` patří **sem**, ne dovnitř seznamů: tady je jeden na celý tab,
            // uvnitř osy nebo diffu by byl na každé položce.
            GeometryReader { proxy in
                Group {
                    switch store.detailTab(for: pullRequest.id) {
                    case .filesChanged: diff
                    case .overview: overview
                    case .conversation: conversation
                    case .findings: findings
                    case .progress: progress
                    }
                }
                .availableWidth(proxy.size.width)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface)
            // Panel je vidět i **v tabu `Nálezy`** (#242), a je to podmínka, ne pohodlí: smyčka
            // nález → `Převzít` → text v mém review je ta hlavní práce, takže se obojí musí stát
            // naráz. Tabulka přes celé okno by chtěla přepínání tam a zpátky za každý převzatý
            // nález.
            ReviewPanel(
                record: store.reviewRecord(for: pullRequest.id),
                isExpanded: panelExpanded,
                jump: jump,
                findings: visibleFindings,
                dismissals: dismissals,
                rechecks: recheck.statuses,
                findingActions: findingActions,
                blockingCategories: blockingCategories,
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
                current: cursor.current,
                tab: panelTab
            )
            // Panel si o místo říká **první**: má vlastní šířku (tu, kterou si uživatel
            // vytáhl), takže víc než ji si nevezme — a zbytek dostane diff, který se umí
            // stáhnout. Bez priority dělí `HStack` místo mezi dva pružné prvky rovnoměrně
            // a v úzkém okně vyjde panel na půlku.
            .layoutPriority(1)
        }
    }

    /// Pruh běhu: chipy reviewerů a vedle nich průběh běžícího review (#218). Ukazuje se,
    /// jakmile je co říct — u PR, na kterém review nikdy neběželo, by to byl jen řádek
    /// prázdných odznaků.
    @ViewBuilder private var reviewers: some View {
        let record = store.reviewRecord(for: pullRequest.id)
        if record != nil || store.isReviewing(pullRequest.id) {
            ReviewRunbarView(
                chips: Policy.chips(
                    for: record,
                    skills: store.reviewSkills(for: pullRequest.repo),
                    running: store.runningReviewers(for: pullRequest.id)
                ),
                muted: $mutedReviewers,
                // Opakování jednoho revieweera (#149). Ostatní běhy zůstávají uložené,
                // takže se za ně neplatí znovu.
                rerun: { store.startReview(for: pullRequest.id, skills: [$0]) },
                progress: store.reviewProgress(for: pullRequest.id)
            )
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

    /// Co o nálezech řekla kontrola z minula (#150).
    ///
    /// Skládá se **jednou** a jde do všech tří míst, která nálezy kreslí (bubliny, karty
    /// v panelu, tabulka): odznak u nálezu a věta v hlavičce mají mluvit o tomtéž. Prázdná mapa
    /// znamená, že kontrola neběžela nebo pro tuhle hlavu neplatí — a odznaky pak nejsou.
    private var recheck: Policy.RecheckReport {
        store.recheckReport(for: pullRequest.id)
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

    /// Rozbalení bublin nálezů v diffu (#185). Jde do diffu **zvlášť**, ne přes `FindingActions`:
    /// tu bere i tabulka nálezů, která rozbalení řídí sama, a sdílená hodnota by jí zavřela nález,
    /// který si v ní člověk otevřel.
    private var findingDisclosure: FindingDisclosureActions {
        let id = pullRequest.id
        return FindingDisclosureActions(
            state: { store.findingDisclosure(of: $0, in: id) },
            toggle: { store.toggleFinding($0, in: id) }
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
    ///
    /// Od #218 stojí **v řadě souřadnic**, ne v pravém sloupci, a je tlumený: akcentová barva
    /// v hlavičce zbyla jedné věci, a tou je `Spustit review`. Zastaralý draft je okrový
    /// (`Palette.stale`), ne oranžový — je to „platilo to, dneska už ne“, ne výstraha.
    @ViewBuilder private var draftChip: some View {
        if store.hasDraft(pullRequest.id) {
            let isStale = store.isDraftStale(for: pullRequest.id)
            Button {
                store.revealDraft()
            } label: {
                Label(
                    isStale ? "rozdělané review · starší commit" : "rozdělané review",
                    systemImage: "square.and.pencil"
                )
                .font(.callout)
                .foregroundStyle(isStale ? Palette.stale : Palette.ink2)
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
            // Kam text spadl, se musí poznat, a od #242 to řeší **store**: `appendDraftNote`
            // i `adoptFinding` si samy ukážou tab s rozdělaným review a rozloží složený panel.
            // Do té doby to bylo tady ve view a nešlo to otestovat.
            addNote: { path, line in
                store.appendDraftNote(text: "", path: path, line: line, for: id)
            },
            adopt: { store.adoptFinding($0, for: id) },
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
    ///
    /// **Zvýraznění se maže tady, na jednom místě** (nález si ho nastaví hned po skoku). Jinak by
    /// zůstalo svítit u nálezu, od kterého se odskočilo — na komentář (#110) nebo na soubor
    /// z palety (#184) — a ukazovalo by na kód, kde nikdo nic nehlásil. Nález Copilota na #184;
    /// u skoku na komentář to bylo rozbité od #110.
    private func scroll(to anchor: String) {
        store.setDetailTab(.filesChanged, for: pullRequest.id)
        highlighted = nil
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

    /// Nálezy seskupené po místech. Skládá se na jednom místě, protože z toho čte diff
    /// **i** procházení — dvě volání `Policy.groups` by se mohla rozejít v tom, co je jedno
    /// místo, a lišta by pak počítala něco jiného, než na co skáče.
    private var findingGroups: [FindingGroup] {
        Policy.groups(of: visibleFindings, dismissals: dismissals, rechecks: recheck.statuses)
    }

    /// Skok na další nebo předchozí nález (#187).
    ///
    /// Kurzor se posouvá **jen když se opravdu skočilo**: kdyby se posunul i při nezdaru
    /// (soubor v diffu není), lišta by tvrdila, že jsem na místě, které jsem nikdy neviděl —
    /// a „prošel jsi všechno“ by tím přestalo platit.
    private func step(_ direction: NavigationStep, onlyBlocking: Bool? = nil) {
        // `⌥⇧↓` skočí na další blokující, aniž by přepnul zúžení v liště: je to jednorázový
        // pohyb, ne změna režimu čtení.
        var cursor = cursor
        if let onlyBlocking { cursor.onlyBlocking = onlyBlocking }

        guard
            let place = Policy.step(
                direction,
                over: findingGroups,
                cursor: cursor,
                categories: blockingCategories
            ),
            let finding = findingGroups
                .first(where: { FindingPlace($0) == place })?
                .activeFindings.first
        else { return }

        jump(to: finding)
        // Zapisuje se do **vlastního** kurzoru, ne do té dočasné kopie výš, aby zúžení
        // z `⌥⇧↓` nepřežilo jeden skok.
        self.cursor = self.cursor.moved(to: place)
    }

    /// Zkratky bydlí **na detailu**, ne na tlačítkách, ke kterým patří: skočit na nález jde
    /// i z `Přehledu` (skok si tab přepne sám) a rozdělané review se píše v panelu, který je
    /// vidět v obou tabech — kdežto tlačítko, které v tu chvíli není v okně, by svou zkratku
    /// nemělo kde zaregistrovat.
    ///
    /// Jak se schovávají, ví `hiddenShortcuts` — je to jedno místo pro celou aplikaci.
    @ViewBuilder private var shortcuts: some View {
        // `⌥⇧↓` je pro SwiftUI **tatáž zkratka** jako `⌥↓`, proto jedno tlačítko a shift až
        // v akci — viz `isShiftDown`.
        Button("Další nález") { step(.forward, onlyBlocking: isShiftDown ? true : nil) }
            .keyboardShortcut(.downArrow, modifiers: .option)
        Button("Předchozí nález") { step(.backward) }
            .keyboardShortcut(.upArrow, modifiers: .option)
        // Panel jde složit i rozložit **stejnou zkratkou** (#182), jak to má návrh v liště
        // nad diffem. Zkratka bydlí tady, ne v `DiffView`: panel je vidět ve všech tabech PR,
        // kdežto lišta jen u diffu — a přepínač, který v půlce okna nefunguje, je horší
        // než žádný.
        Button("Panel s mým review") {
            withAnimation(.snappy(duration: 0.15)) {
                store.isReviewPanelExpanded.toggle()
            }
        }
        .keyboardShortcut("2", modifiers: .command)
        submitShortcut
    }

    /// Drží se zrovna shift? Z toho se pozná `⌥⇧↓` (další **blokující** nález) od `⌥↓`.
    ///
    /// **Zkratkou se to rozlišit nedá** — změřeno na běžící aplikaci u #151: SwiftUI u šipek
    /// `.shift` při párování ignoruje, takže dvě tlačítka lišící se jen jím jsou jedna zkratka
    /// a vyhraje to zaregistrované později. Do #151 tedy `⌥↓` dělalo „další blokující“, a protože
    /// blokující nález bývá jeden, druhé zmáčknutí nikam neskočilo — vypadalo to, že zkratka
    /// nefunguje. Ověřeno oběma směry: po odebrání varianty se shiftem začalo `⌥↓` procházet
    /// nálezy **a** `⌥⇧↓` skákalo po tom samém.
    ///
    /// Ptá se **události, která akci spustila** (`NSApp.currentEvent`), ne stavu klávesnice
    /// (`NSEvent.modifierFlags`). Je to přesnější otázka — „čím se to zmáčklo“ — a hlavně to
    /// jediné funguje i pro zkoušení přes `System Events`, kde synthetická klávesa stav
    /// klávesnice nemění: se `modifierFlags` vycházelo `⌥⇧↓` jako obyčejné `⌥↓`.
    ///
    /// Bez události se bere **`false`, tedy obyčejný skok**, a není to spolknutá chyba: zúžení
    /// na blokující je zkratka navíc, takže se z ní v nejhorším stane ta základní. Opačný default
    /// by přeskakoval nálezy, aniž by o to kdo řekl.
    private var isShiftDown: Bool {
        NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
    }

    /// `⌘⏎` otevře **potvrzení odeslání**, nic neodesílá (#151).
    ///
    /// Tvrdá podmínka č. 1: review odchází dvěma kliknutími na dvou různých tlačítkách (#68)
    /// a zkratka je obejít nesmí. Volá proto tutéž akci jako tlačítko v panelu — tu, která jen
    /// složí snímek draftu a otevře sheet. V samotném sheetu zkratka na odeslání **není a nesmí
    /// být**; kdyby byla, stačil by na approve jeden hmat.
    ///
    /// Zakázaná je ze stejného důvodu jako to tlačítko (`Policy.canOpenSubmission`) — a navíc
    /// nad otevřeným sheetem: druhé stisknutí by složilo nový snímek a zahodilo stav rozdělaného
    /// odesílání, tedy i hlášku, kvůli které je okno otevřené.
    ///
    /// Platí **v celém detailu**, tedy i když se zrovna píše do composeru komentáře nebo do
    /// odpovědi ve vlákně — ty vlastní `⌘⏎` nemají (odesílají se pojmenovaným tlačítkem, viz
    /// tvrdá podmínka č. 1), takže se nic nepřebíjí; jen se nad rozdělaným review otevře
    /// potvrzení, které jde zavřít Escem.
    /// **Nad otevřenou paletou je zakázaná** (#184): tam `⌘↵` otevírá vybraný výsledek na
    /// GitHubu. Dvě tlačítka se stejnou zkratkou v jednom okně znamenají, že vyhraje to
    /// zaregistrované později — a spletená zkratka nad rozdělaným review by otevřela potvrzení
    /// odeslání, tedy zrovna to okno, které se omylem otevřít nemá. Zakázané tlačítko klávesu
    /// nebere, takže propadne paletě.
    private var submitShortcut: some View {
        Button("Otevřít potvrzení odeslání") { draftActions.send() }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(submission != nil || !canOpenSubmission || store.isPaletteOpen)
    }

    /// Dá se potvrzení vůbec otevřít? Rozhoduje `Policy`, ne tohle view — na totéž se ptá
    /// tlačítko v panelu.
    private var canOpenSubmission: Bool {
        Policy.canOpenSubmission(
            block: store.draftSendBlock(for: pullRequest.id),
            canTransfer: store.canTransferDraft(for: pullRequest.id)
        )
    }

    /// Nález ukazuje na `file:line`; kde to je v diffu, ví `DiffRow`. Když se místo najít
    /// nedá (soubor v diffu není), nestane se nic — skákat naslepo je horší než nehnout se.
    private func jump(to finding: Finding) {
        guard let path = finding.file, let anchor = anchor(inFile: path, line: finding.line) else {
            return
        }
        reveal(bubbleOf: finding)
        scroll(to: anchor)
        // Zvýraznění se porovnává s tím, co nahlásil reviewer, ne s cestou v diffu — bublina
        // nese jeho `file`, ne `displayPath`.
        highlighted = FindingHighlight(file: path, line: finding.line)
    }

    /// Kotva na místo v diffu — a **rozbalený soubor**, protože ve sbaleném by skok skončil
    /// nikde: jeho řádky v líném seznamu vůbec nejsou. Rozbalit se musí **předtím**, než se
    /// nastaví cíl, jinak `scrollTo` míří na id, které v seznamu ještě není.
    ///
    /// `nil` = takové místo v diffu není. Jedno místo pro skok z nálezu i pro skok z palety
    /// (#184); dvě kopie by se rozešly zrovna v tom, na čem tenhle skok stojí.
    private func anchor(inFile path: String, line: Int?) -> String? {
        guard case .loaded(let diff, _) = store.diffState(for: pullRequest.id),
              // Rozbalený kontext je uložený pod **novou** cestou souboru, kdežto nález umí
              // přijít pod starou. Bez překladu by kotva u přejmenovaného souboru rozbalený
              // kontext neviděla a skok by spadl na hlavičku.
              let file = diff.file(at: path),
              let anchor = DiffRow.anchor(
                  in: diff,
                  file: path,
                  line: line,
                  revealed: store.expansion(of: file.displayPath, in: pullRequest.id).revealed
              )
        else { return nil }
        store.unfold(file.displayPath, in: pullRequest.id)
        return anchor
    }

    /// Rozbalí **sbalenou bublinu**, na kterou se skáče (#185), ze stejného důvodu jako se
    /// rozbaluje sbalený soubor: skok na značku ukáže pruh, ne nález, na který se kliklo.
    ///
    /// Dvě přetížení, protože skok z lišty a z tabulky nese **nález** — ten je jednoznačný i u
    /// nálezu bez řádku, kterých může být v jednom souboru víc — kdežto žádost z palety (#184)
    /// nese `file:line`. Bez řádku se z palety nerozbaluje nic a nemusí: kotva pak míří na
    /// hlavičku souboru, takže na značce se skok nezastaví.
    private func reveal(bubbleOf finding: Finding) {
        guard let group = findingGroups.first(where: { $0.findings.contains(finding) }) else { return }
        store.revealFinding(group, in: pullRequest.id)
    }

    private func reveal(bubbleAt file: String, line: Int?) {
        guard let line, let group = findingGroups.first(where: { $0.file == file && $0.line == line })
        else { return }
        store.revealFinding(group, in: pullRequest.id)
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
            facts: facts,
            checks: store.checks[pullRequest.id] ?? [],
            changes: store.changesSinceLastVisit(for: pullRequest.id),
            lastVisit: store.visitSnapshots[pullRequest.id],
            // Obojí je „to, co mám na obrazovce, už neplatí“, takže se do banneru slévá do
            // jedné věty — rozdíl mezi zastaralými nálezy a zastaralým draftem se řeší
            // v panelu, kde se s nimi něco dělá.
            isStale: store.reviewRecord(for: pullRequest.id)?.isStale == true
                || store.isDraftStale(for: pullRequest.id),
            movedHead: store.movedHead(for: pullRequest.id),
            rerun: { store.startReview(for: pullRequest.id) },
            dismissChanges: { store.markChangesAsSeen(for: pullRequest.id) },
            pullRequest: pullRequest
        )
    }

    /// Tab `Nálezy` (#242) — tabulka přes celou šířku.
    ///
    /// Bere **tytéž** nálezy jako panel a jako bubliny v diffu (`visibleFindings`), takže se ta tři
    /// místa nemají čím rozejít. `clear` je `nil`, když není co zahodit; rozhoduje uložený záznam,
    /// ne to, co zbylo po filtru reviewerů — filtr je pohled, ne obsah.
    private var findings: some View {
        let record = store.reviewRecord(for: pullRequest.id)
        return FindingsTabView(
            record: record,
            pullRequest: pullRequest.id,
            findings: visibleFindings,
            dismissals: dismissals,
            rechecks: recheck.statuses,
            blockingCategories: blockingCategories,
            isRunning: store.isReviewing(pullRequest.id),
            clear: record == nil ? nil : { try await store.clearFindings(for: pullRequest.id) },
            findingActions: findingActions,
            // Komentáře k řádkům se z tabulky nezakládají — ty patří k diffu. Zbývá převzetí,
            // které je ta hlavní smyčka, a to `FileDraftActions` unese i bez souboru.
            draft: FileDraftActions(
                canCompose: draftActions.canCompose,
                adopt: draftActions.adopt,
                isAdopted: draftActions.isAdopted,
                target: draftActions.target
            ),
            current: cursor.current,
            jump: jump
        )
    }

    /// Tab `Průběh` (#242) — dráha na revieweera.
    ///
    /// `rerun` je `nil`, dokud něco běží: druhý běh téhož revieweera vedle prvního by se v ose
    /// míchal s tím, co zrovna dobíhá.
    private var progress: some View {
        // Osy se berou **jednou** a použijí se na dráhy i na skládání příkazu: `timelines(for:)`
        // je odvozený getter, takže druhé volání za každou dráhu je práce navíc při každém
        // překreslení.
        let timelines = store.timelines(for: pullRequest.id)
        return ReviewProgressView(
            lanes: Policy.lanes(
                of: timelines,
                // **Tatáž sada, ze které se review pouští** (`AppStore.reviewSkills(for:)`, přes
                // kterou jde `runSkills`) — dvě různá místa by znamenala, že tab slibuje jinou
                // sadu, než jaká se spustí. Bere ji i pruh běhu na chipy.
                skills: store.reviewSkills(for: pullRequest.repo),
                // Bez záznamu by běh, jehož osa se neuložila (soubory před #203), vypadal jako
                // nespuštěný — a chip nad tabem by nad ním tvrdil `doběhlo`.
                record: store.reviewRecord(for: pullRequest.id),
                running: store.runningReviewers(for: pullRequest.id)
            ),
            rerun: store.isReviewing(pullRequest.id)
                ? nil
                : { store.startReview(for: pullRequest.id, skills: [$0]) },
            copyCommand: copyCommand(in: timelines)
        )
    }

    /// Zkopíruje příkaz, jakým by se reviewer spustil teď — `Zkopírovat příkaz` u spadlé session
    /// (#242).
    ///
    /// `nil`, dokud nevíme, proti čemu se diffuje: příkaz bez `baseSha` by nebyl spustitelný, a
    /// tlačítko, které zkopíruje něco nefunkčního, je horší než žádné. Příkaz se skládá **až při
    /// kliknutí** — nese celý prompt, takže by se jinak stavěl při každém překreslení tabu.
    private func copyCommand(in timelines: [ReviewerTimeline]) -> ((String) -> Void)? {
        guard let baseSha = loadedDetail?.baseSha else { return nil }
        let model = store.configuration.global.model
        return { skill in
            Clipboard.copy(ClaudeCommand.shellCommand(
                skillID: skill,
                baseSha: baseSha,
                model: model,
                worktree: timelines.first { $0.skill == skill }?.worktree
            ))
        }
    }

    /// Tab `Konverzace` (#183) — časová osa. Bere **tytéž položky** jako `Přehled` bral do #183;
    /// jediný domov konverzace se nedělí, jen stěhoval.
    private var conversation: some View {
        ConversationView(
            entries: store.overview(for: pullRequest.id),
            state: store.conversationState(for: pullRequest.id),
            viewer: store.conversation(for: pullRequest.id)?.viewer ?? "",
            missing: store.conversation(for: pullRequest.id).map(ConversationShortfall.init)
                ?? ConversationShortfall(),
            threadActions: threadActions,
            refresh: { Task { await store.refreshConversation(for: pullRequest) } },
            lastVisit: store.visitSnapshots[pullRequest.id],
            isStale: store.reviewRecord(for: pullRequest.id)?.isStale == true
                || store.isDraftStale(for: pullRequest.id),
            rerun: { store.startReview(for: pullRequest.id) },
            composer: composer
        )
    }

    /// Psaní do diskuze pod PR (#216). `nil` bez `gh` — bez něj nevede z aplikace ven žádná
    /// cesta, takže by composer sliboval odeslání, které nikdy nepůjde. Zakázané odesílání
    /// (repo mimo `PublishScope`) je něco jiného: to se dá zapnout v nastavení, takže pole
    /// zůstává a tlačítko je zakázané s důvodem.
    private var composer: ConversationComposer? {
        guard store.gh != nil else { return nil }
        return ConversationComposer(
            text: store.pullRequestComment(for: pullRequest.id),
            setText: { store.setPullRequestComment($0, for: pullRequest.id) },
            send: { Task { await store.sendPullRequestComment(for: pullRequest) } },
            state: store.pullRequestCommentState(for: pullRequest.id),
            block: store.canPublishToThreads(in: pullRequest.repo)
                ? nil
                : PublishError.publishingNotAllowed(pullRequest.repo).userDescription
        )
    }

    /// Čísla do dlaždic (#198). Skládají se z toho, co v okně **už je** — diff, časová osa,
    /// hlava PR a sha nálezů; nic se pro ně nedotahuje.
    private var facts: PullRequestFacts {
        let diff = loadedDiff
        let markers = diff.map { _ in
            Policy.fileMarkers(
                of: store.reviewRecord(for: pullRequest.id)?.activeFindings ?? [],
                categories: blockingCategories
            )
        } ?? [:]
        let events = store.conversation(for: pullRequest.id)?.events
        let changes = store.changesSinceLastVisit(for: pullRequest.id)
        return Policy.facts(
            commits: events?.items.count { if case .commit = $0.kind { true } else { false } } ?? 0,
            newCommits: changes.commits.count,
            files: diff?.files.count ?? 0,
            // Nálezy patří k souborům diffu, ne k cestám ze záznamu: nález na souboru, který
            // v dnešním diffu není, by dlaždici nafoukl o číslo, které nemá kde být vidět.
            filesWithFindings: diff?.files.count { markers[$0.displayPath] != nil } ?? 0,
            // Utnutá stránka událostí = počet commitů neznáme přesně.
            areCommitsExact: events.map { !$0.hasNextPage } ?? false,
            headSha: loadedDetail?.headSha,
            findingsHeadSha: store.reviewRecord(for: pullRequest.id)?.headSha
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
                findings: findingGroups,
                findingActions: findingActions,
                findingDisclosure: findingDisclosure,
                blockingCategories: blockingCategories,
                highlighted: highlighted,
                threads: store.anchoredThreads(for: pullRequest.id),
                missingThreads: store.conversation(for: pullRequest.id)?.threads.missing ?? 0,
                viewer: store.conversation(for: pullRequest.id)?.viewer ?? "",
                threadActions: threadActions,
                comments: store.draftComments(for: pullRequest.id),
                draft: draftActions,
                layout: diffLayout,
                navigation: Policy.navigation(
                    over: findingGroups,
                    cursor: cursor,
                    categories: blockingCategories
                ),
                onlyBlocking: $cursor.onlyBlocking,
                // Tlačítko `Nálezy` v liště nad diffem (#197). Stav drží detail, protože
                // panel je vidět i v tabu `Přehled`, kde lišta není.
                panelExpanded: panelExpanded,
                stepFinding: { step($0) }
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

    /// Spuštění a zrušení běhů. Tlačítka jsou tady, ne v toolbaru: patří k vybranému PR
    /// a v toolbaru by nebylo vidět, ke kterému.
    ///
    /// **Kontrola nálezů stojí vlevo od `Spustit review`** (#150) a je tlumená, ne akcentová:
    /// akcentová barva v hlavičce zbyla jedné věci (#218) a dvě fialová tlačítka vedle sebe by
    /// z ní udělala dvě.
    private var review: some View {
        HStack(spacing: 12) {
            recheckControl
            reviewControl
            if case .failed(let detail) = store.reviewPhases[pullRequest.id] {
                Label(detail, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Palette.crit)
            }
        }
    }

    /// Za běhu review zbývá **jen `Zrušit`** (#218): kdo běží a kolik je hotovo, říká pruh pod
    /// souřadnicemi PR, a dvě věty o tomtéž vedle sebe se přestanou číst obě.
    @ViewBuilder private var reviewControl: some View {
        if store.isReviewing(pullRequest.id) {
            Button("Zrušit", systemImage: "stop.circle") {
                store.cancelReview(for: pullRequest.id)
            }
        } else {
            Button("Spustit review", systemImage: "play.circle") {
                store.startReview(for: pullRequest.id)
            }
        }
    }

    /// Kontrola nálezů z minula (#150).
    ///
    /// **Nenabízí se, dokud není co kontrolovat** — bez uloženého záznamu proti staršímu commitu
    /// by se z chybějícího vstupu stala session, která hádá. Rozhoduje o tom store
    /// (`recheckMaterial(for:)`), ne tenhle soubor: je to podmínka o datech, ne o kreslení.
    ///
    /// Za běhu se z tlačítka stane `Zrušit kontrolu` s hodinami. Bez nich je patnáctiminutová
    /// session k nerozeznání od zaseknutého okna — a vlastní pruh průběhu kontrola nemá, protože
    /// nepouští žádného revieweera (pruh mluví o chipech).
    @ViewBuilder private var recheckControl: some View {
        if store.isRechecking(pullRequest.id) {
            HStack(spacing: 6) {
                Button("Zrušit kontrolu", systemImage: "stop.circle") {
                    store.cancelRecheck(for: pullRequest.id)
                }
                if let startedAt = store.recheckStartedAt(for: pullRequest.id) {
                    // Hodiny tikají v `TimelineView`, ne z časovače ve store: překresluje se
                    // jeden popisek, ne celé okno. Tatáž úvaha jako u pruhu běhu (#218).
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(verbatim: RunUsageText.elapsed(
                            .seconds(context.date.timeIntervalSince(startedAt))
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Palette.ink2)
                    }
                }
            }
        } else if let material = store.recheckMaterial(for: pullRequest.id) {
            Button("Zkontrolovat nálezy", systemImage: "checkmark.circle.badge.questionmark") {
                store.startRecheck(for: pullRequest.id)
            }
            .help(Self.recheckHint(for: material))
        }
    }

    /// Co tlačítko udělá — a hlavně **kolik to je nálezů a proti čemu**, protože je to session
    /// za peníze. Skládá se z hotových čísel, takže `nonisolated static`: dá se vyčerpat testem.
    nonisolated static func recheckHint(for material: RecheckMaterial) -> String {
        let findings = Plural.czech(
            material.findings.count,
            one: "nález",
            few: "nálezy",
            many: "nálezů"
        )
        return "Pustí session, která projde \(findings) z commitu "
            + "\(material.headSha.prefix(7)) a řekne, co nové commity spravily. "
            + "Nálezy tím nemizí — sundá je jedině tvoje odmítnutí."
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
