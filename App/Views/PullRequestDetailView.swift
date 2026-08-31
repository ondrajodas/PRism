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

    /// Celý log jobu v sheetu (#214). `@State` detailu, protože se **neukládá a nemá přežít**.
    ///
    /// **Nuluje se při přepnutí checku i při přepnutí PR** (nález Copilota na #214, včetně toho
    /// v `Suppressed comments`). Drží celý text, takže bez toho by pravidlo „log nepřežije sbalení
    /// checku“ platilo jen ve store: sbalení zahodí `checkDetail`, ale otevřený sheet by dál držel
    /// megabajty — a po přepnutí PR by nad novým ukazoval log z předchozího.
    @State private var logSheet: CodeText?

    /// Přepis surové session v sheetu (#327). `@State` detailu drží jen **kterou** session ukazuje;
    /// snímek samotný (megabajty) drží store, aby ho zavření sheetu zahodilo na jednom místě.
    ///
    /// Nuluje se při přepnutí PR ze stejného důvodu jako `logSheet`: transcript patří jedné session
    /// jednoho PR, takže by nad novým ukazoval přepis z předchozího.
    @State private var rawSession: RawSessionTarget?

    /// Zadání pro agenta v sheetu (#333). `@State` detailu ze stejného důvodu jako `logSheet`:
    /// je to **snímek k přečtení**, nic se z něj neodesílá a nemá co přežít.
    ///
    /// **Nuluje se při přepnutí PR** (viz `.task(id:)` níž) — jinak by nad novým PR zůstal
    /// otevřený sheet se zadáním z předchozího, tedy text, který se dá zkopírovat a nesouhlasí
    /// s tím, co je za ním v okně. Tatáž past jako u logu checku.
    ///
    /// Od #377 je to **zadání i seznam položek**, ze kterého vzniklo (`AgentPromptSelection`):
    /// sheet z něj kreslí zaškrtávátka a přeskládává text, takže by dva dotazy znamenaly dvě různá
    /// čísla nad jedním textem.
    @State private var promptSheet: AgentPromptSelection?

    /// Rozdělané odeslání review. Zakládá se tady, ale **drží ho `ContentView`** — detail
    /// zmizí, jakmile PR vypadne ze seznamu, a odeslané review `review-requested` ruší, takže
    /// se to na příštím tiku stane. Sheet by tím zmizel i s hláškou, kvůli které je otevřený.
    @Binding var submission: ReviewSubmission?

    /// Rozdělaný merge (#465). Zakládá se tady, ale **drží ho `ContentView`** — a je to tatáž
    /// past jako u odeslání review, jen o stupeň horší: mergnutý PR ze zdroje `author:@me`
    /// na příštím tiku **vypadne**, takže by sheet zavěšený na detailu zmizel zrovna s tou
    /// hláškou, kvůli které je otevřený.
    @Binding var merge: MergeSubmission?

    /// Rozdělané přetlačení větve (#466). Zakládá se tady, ale **drží ho `ContentView`** — tatáž
    /// past jako u merge: sheet zavěšený na detailu zmizí, jakmile se pod ním záložka přestane
    /// kreslit, a to je zrovna ta chvíle, kdy je v něm vidět, jak to dopadlo.
    @Binding var branchPush: BranchPushSubmission?

    /// Výška celého detailu — z ní je strop zásuvky s terminálem (#459).
    ///
    /// Měří se `onGeometryChange`, protože **akce se při nezměněné hodnotě nespustí** (změřeno
    /// u #361), takže to není bezpodmínečný zápis z každého snímku, kterému se vyhýbá #358.
    /// Nula znamená „ještě se neměřilo“ a zásuvka se pak otevře na ideál, ne na podlahu.
    @State private var detailHeight: CGFloat = 0

    var body: some View {
        let _ = RenderDiagnostics.pass(Self.self)
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
            terminalDrawer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailHeight = $0 }
        // Celý log jobu (#214) — tentýž sheet, jakým se kopíruje hunk z diffu (#157): jeden
        // read-only `NSTextView`, tedy přesně na tohle.
        .sheet(item: $logSheet) { CodeTextSheet(content: $0) }
        // Surová session (#327) — `item:` ze stejného důvodu jako u zadání: sheet nemá co ukazovat
        // bez cíle, a stav se čte ze storu, takže se sem nekopíruje.
        .sheet(item: $rawSession) { target in
            RawSessionSheet(
                target: target,
                state: store.rawSessionState(of: target),
                growth: store.rawSessionGrowth(),
                path: store.rawSessionPath(of: target),
                reload: { Task { await store.reloadRawSession() } },
                refreshSize: { await store.refreshRawSessionSize() }
            )
            // Zavřením se snímek **zahodí**: je to to největší, co okno kvůli téhle obrazovce drží,
            // a mimo otevřený sheet ho nikdo nečte.
            .onDisappear { store.closeRawSession() }
        }
        // Zadání pro agenta (#333). `item:`, ne `isPresented:`: sheet nemá co ukazovat bez textu,
        // a ten se skládá ve chvíli kliknutí — co je vidět, to se zkopíruje.
        // Razítko předání (#334) se zapisuje **až když si text někdo vezme** — zkopírováním nebo
        // uložením do souboru, ne otevřením sheetu. Zapisuje ho store, sheet o tom jen řekne.
        .sheet(item: $promptSheet) { selection in
            AgentPromptSheet(
                selection: selection,
                // Přeskládání jde **tou samou cestou**, jakou se sheet otevřel — i se zúžením
                // (#334), jinak by se zadání „jen nové vlákno“ po prvním odškrtnutí rozrostlo
                // na celé.
                rebuild: {
                    store.agentPromptSelection(for: pullRequest.id, only: selection.only, toggled: $0)
                },
                handoff: { store.noteHandoff(of: $0) }
            )
        }
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
        // Log jobu patří k jednomu checku jednoho PR (#214), takže při přepnutí PR **nesmí**
        // přetéct — ani obsahem, ani tou pamětí, kterou drží.
        .task(id: pullRequest.id) { logSheet = nil }
        // Přepis patří jedné session jednoho PR (#327) a drží megabajty, takže při přepnutí PR
        // **nesmí** přetéct — ani obsahem, ani tou pamětí. Zahazuje se obojí: cíl ve view i snímek
        // ve storu.
        .task(id: pullRequest.id) {
            rawSession = nil
            store.closeRawSession()
        }
        // Zadání patří k jednomu PR (#333) a je k rozkopírování, takže při přepnutí **nesmí**
        // přetéct: zkopírovat prompt psaný o jiném PR se nedá vzít zpátky.
        .task(id: pullRequest.id) { promptSheet = nil }
        // Adresář zásuvky (#459) se hledá i při přepnutí PR s vytaženou zásuvkou — jinak by nad
        // novým pull requestem zůstala cesta do checkoutu toho předchozího. Shell, který už běží,
        // to nepřestěhuje: ten si drží ten svůj adresář, ve kterém startoval.
        .task(id: pullRequest.id) {
            guard store.isTerminalOpen else { return }
            await store.prepareTerminalDrawer(for: pullRequest.id)
        }
        // Klíčem je celé shrnutí, ne jen identifikátor: nový commit změní `updatedAt`,
        // a to je přesně chvíle, kdy se má diff načíst znovu i bez přepnutí PR.
        .task(id: pullRequest) { await store.loadDiff(for: pullRequest) }
        // Konverzace stejnou cestou jako diff, ne pollingem: pro všech N PR by to byla
        // tatáž N+1 past, kvůli které se netahá ani detail.
        .task(id: pullRequest) { await store.loadConversation(for: pullRequest) }
        // A detail taky — z něj je `headSha`, proti kterému se píše rozdělané review a proti
        // kterému se pozná, že zastaralo.
        .task(id: pullRequest) { await store.loadDetail(for: pullRequest) }
        // Rozhovor (#452) se čte z disku **při otevření PR**, ne při startu aplikace: v seznamu
        // nic nemá, takže by se jinak dekódovalo všechno, co si kdo kdy vyzkoušel, kvůli
        // obrazovce, na kterou se ten den nemusí přijít podívat. Klíčem je identifikátor, ne
        // celé shrnutí — nový commit rozhovor **nezneplatní** (ukládá se k PR, ne k `headSha`).
        .task(id: pullRequest.id) { await store.loadAskConversation(for: pullRequest.id) }
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
                    checks: store.checks[pullRequest.id] ?? [],
                    // Pilulka `moje PR` (#334) — čte se ze stejného místa jako to, který segment
                    // kreslí panel, takže se hlavička a panel nemají čím rozejít.
                    ownership: ownership
                )
                draftChip
                Spacer(minLength: 8)
            }
            // Jen když se hlava rozešla se sha, proti které platí nálezy — jinak by to byl
            // řádek s údajem, který nikoho nezajímá. **Rozchod počítá store** (#284), protože
            // o témže stavu mluví i odznak v pruhu „od tvé poslední návštěvy“.
            if let stale = store.staleFindings(for: pullRequest.id) {
                StaleHeadView(head: stale.head, findingsHead: stale.findingsHead, recheck: recheck)
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
            // Věta o selhaném načtení kontrol tady **není** (#306, mění #215). Do #306 sem patřila
            // proto, že tab `Kontroly` u nenačtených checků mizel — a „bez ní je zmizelý tab
            // k nerozeznání od PR bez CI“ byl celý její důvod. Tab je od #306 v pruhu vždycky
            // a poruchu hlásí sám (`Policy.checksTab`), takže věta v hlavičce by byla druhé místo
            // o téže věci. Je to tentýž vzor jako u diffu a konverzace: co se nepovedlo načíst,
            // řekne ten tab, ve kterém to mělo být vidět.
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
    /// **Kolik jich je, se nepředává** (#306): pruh kreslí všech šest vždycky, takže se počet
    /// záložek nemá čím měnit podle toho, co zrovna dorazilo ze sítě.
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
        case .filesChanged: shownDiff.flatMap { count($0.files.count) }
        // Prostý počet commitů, ze **stavu tabu** (#316) — nad nenačteným ani spadlým seznamem
        // nic, ať odznak nemluví o něčem jiném než plocha pod ním. Tichá kapsle: kolik je commitů,
        // je údaj o množství, ne důvod někam jít.
        case .commits: Policy.commitsBadge(of: store.commitsTabState(for: pullRequest.id))
        // Jen to, co je **k přečtení** — události časové osy se nepočítají (#171), jinak by
        // na PR s dvaceti commity odznak ukazoval třicet a přestal by o diskuzi něco říkat.
        case .conversation: count(store.overview(for: pullRequest.id).count { $0.isReadable })
        // **Podle nejhoršího stavu, ne podle většiny** (#215) — tatáž úvaha jako u chipu
        // v hlavičce. Anotace z CI (#214) se do něj **nepočítají**: odznak mluví o checkech,
        // ne o tom, kolik jich mělo co říct. Ze **stavu tabu** (#306), ať se nedá nakreslit nula
        // nad tabem, ve kterém se zrovna čeká na odpověď — a ať odznak mluví o tom, co je pod ním.
        case .checks: Policy.checksBadge(of: store.checksTabState(for: pullRequest.id))
        // Počítá to **`Policy` z týchž nálezů**, jaké kreslí tabulka v tabu, karty v panelu
        // a bubliny v diffu (#242) — jeden zdroj, aby odznak nemohl tvrdit něco jiného, než
        // co je na obrazovce.
        case .findings: Policy.findingsBadge(of: findingsTally)
        // Puntík, ne počet: „běží“ je stav, ne množství — u dvou reviewerů by dvojka o průběhu
        // neřekla nic.
        case .progress: store.isReviewing(pullRequest.id) ? .live : nil
        // **Puntík, ne počet zpráv** (#452): číslo v rozhovoru je počet mých otázek, což o tabu
        // neříká nic — a tichá kapsle „4“ vedle `Zeptat se` by vypadala jako čtyři nepřečtené
        // věci. Odznak dostane jedině běžící odpověď, tedy tentýž stav jako u `Průběhu`.
        case .ask: store.isAnswering(pullRequest.id) ? .live : nil
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

    /// Diff, který je v tabu **vidět** — celý, nebo rozsah „co přibylo“ (#284).
    ///
    /// Odznak u záložky a `+X −Y` v pruhu stojí kousek nad tím diffem, takže musí počítat to,
    /// co je pod nimi. Kdyby držely čísla celého PR i nad rozsahem, pruh by tvrdil sedm souborů
    /// nad dvěma — a to je přesně ten druh čísla, které se pak nedá s ničím srovnat.
    ///
    /// Dlaždice v `Přehledu` z toho **nečtou**: „Soubory: 7“ je fakt o PR a `Přehled` navíc rozsah
    /// nikdy nekreslí.
    private var shownDiff: Diff? {
        // **Ne `?? loadedDiff` nad rozsahem**: dokud se rozsah načítá nebo selhal, je odpověď
        // „nevím“, ne „tak tedy celý diff“ — jinak by odznak u záložky na okamžik ukázal počet
        // souborů celého PR nad prázdným tabem.
        guard let incremental = store.incrementalDiff(for: pullRequest.id) else { return loadedDiff }
        return incremental.loaded
    }

    /// Rozsah změny pro záložky (#174). `nil`, dokud diff nedorazí — nuly by tvrdily,
    /// že PR nic nemění.
    private var loadedDiffCounts: (additions: Int, deletions: Int)? {
        shownDiff.map { ($0.additions, $0.deletions) }
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

    /// Obsah vybraného tabu a vedle něj panel s nálezy a mým review.
    ///
    /// Panel je vidět, i když na PR review nikdy neběželo (**změna proti #20**): od #66 v něm
    /// bydlí i rozdělané review, a to se zakládá od nuly. Kdyby se panel ukazoval až s prvním
    /// nálezem, nebylo by kde vybrat verdikt ani napsat tělo.
    ///
    /// **Ve kterých tabech je, rozhoduje `PullRequestTab.showsReviewPanel`** (#294) — tam je i
    /// napsané proč. V `Kontrolách`, `Nálezech` a `Průběhu` se schová **celý**, tedy i složený
    /// proužek: ten je úzký, ale bere šířku, a v těch třech tabech je vedle něj buď duplikát
    /// týchž dat, nebo obsah, který šířku potřebuje.
    ///
    /// **Šířku si tab nepočítá, dostane ji změřenou.** `GeometryReader` níž měří to, co po panelu
    /// zbylo, takže se zmizením panelu roztáhne sám a není tu žádné odečítání, které by se dalo
    /// splést — právě na takovém odečítání se rozbila #291.
    @ViewBuilder private var content: some View {
        let tab = store.detailTab(for: pullRequest.id)
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
                    switch tab {
                    case .filesChanged: diff
                    case .overview: overview
                    case .commits: commits
                    case .conversation: conversation
                    case .checks: checks
                    case .findings: findings
                    case .progress: progress
                    case .ask: ask
                    }
                }
                .availableWidth(proxy.size.width)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface)
            if tab.showsReviewPanel { panel }
        }
    }

    /// Zásuvka s terminálem (#459) — **jen v záložce pull requestu**, protože jinde není checkout,
    /// ve kterém by měl shell startovat.
    ///
    /// Zavřená se do hierarchie **vůbec nedostane**, a to je podmínka, ne úspora: plocha emulátoru
    /// si při rozvržení počítá řádky a sloupce a posílá je do pty jako `TIOCSWINSZ`, takže schovaná
    /// zásuvka nulové výšky by běžícímu TUI ohlásila `0×0`.
    @ViewBuilder private var terminalDrawer: some View {
        if store.isTerminalOpen {
            let active = store.activeTerminalSlot(for: pullRequest.id)
            TerminalDrawerView(
                rows: store.terminalRows(for: pullRequest.id),
                activeSlot: active,
                directory: active.flatMap { store.terminalDirectory(of: $0) },
                host: store.terminals,
                available: detailHeight,
                select: { store.selectTerminalSlot($0) },
                close: { Task { await store.toggleTerminal() } }
            )
        }
    }

    /// Panel vpravo. Vlastní vlastnost, ne blok uvnitř `content`: kreslí se podmíněně (#294)
    /// a `if` s dvacetiřádkovým tělem uvnitř by z místa, kde se rozhoduje, udělal místo, kde se
    /// skládají parametry.
    private var panel: some View {
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
            ownership: ownership,
            // Skládá se jen na vlastním PR (#333): na cizím by to byl text, který nikdo neotevře,
            // a přesto by se přeskládal při každém překreslení panelu.
            agentPrompt: ownership == .mine ? store.agentPrompt(for: pullRequest.id) : nil,
            agentPromptActions: agentPromptActions,
            // Razítko předání (#334) — jen na vlastním PR, ze stejného důvodu jako zadání samo.
            handoff: ownership == .mine ? store.handoffReport(for: pullRequest.id) : .never,
            conversation: store.conversationState(for: pullRequest.id),
            draftUnavailable: draftUnavailable,
            draftActions: draftActions,
            jumpToComment: jumpToComment,
            // Labely a reviewery (#392) — dvě sekce nad segmenty, které platí pro celý PR.
            metadata: store.metadataState(for: pullRequest.id),
            metadataEditing: store.metadataEditing(for: pullRequest.id),
            knownLabels: store.knownLabels(in: pullRequest.repo),
            reviewerCandidates: store.reviewerCandidates(for: pullRequest.id),
            labelPickerFailure: store.labelPickerFailure(in: pullRequest.repo),
            reviewerPickerFailure: store.reviewerPickerFailure(in: pullRequest.repo),
            hasLoadedLabels: store.hasLoadedLabels(in: pullRequest.repo),
            hasLoadedCandidates: store.hasLoadedAssignableUsers(in: pullRequest.repo),
            metadataActionState: store.metadataActionState(for: pullRequest.id),
            metadataActions: metadataActions,
            // Sekce `Větev` (#465) — skládá ji `Policy`, panel z ní jen sází. Na cizím PR vyjde
            // `nil` a nekreslí se ani nadpis.
            branch: store.branchSection(for: pullRequest.id),
            branchActions: branchActions,
            branchSync: store.branchSyncState(for: pullRequest.id),
            // Proti kterému kódu nálezy platí (#392). Rozhoduje `Policy` — panel z toho jen sází
            // větu, takže se okno neptá dvakrát jinak.
            headNotice: headNotice,
            current: cursor.current,
            tab: panelTab
        )
        // Panel si o místo říká **první**: má vlastní šířku (tu, kterou si uživatel
        // vytáhl), takže víc než ji si nevezme — a zbytek dostane diff, který se umí
        // stáhnout. Bez priority dělí `HStack` místo mezi dva pružné prvky rovnoměrně
        // a v úzkém okně vyjde panel na půlku.
        .layoutPriority(1)
    }

    /// Akce nad labely a reviewery (#392). Skládá se tady, jako `findingActions` — panel dostane
    /// hodnotu a `AppStore` nezná.
    private var metadataActions: MetadataActions {
        let summary = pullRequest
        let id = summary.id
        return MetadataActions(
            toggle: { label in Task { await store.toggleLabel(label, on: summary) } },
            create: { label in Task { await store.createLabel(label, on: summary) } },
            request: { candidate in Task { await store.requestReview(from: candidate, on: summary) } },
            loadLabels: { await store.loadRepositoryLabels(for: id.repo) },
            loadCandidates: { await store.loadAssignableUsers(for: id.repo) },
            clearFailure: { store.clearMetadataFailure(for: id) }
        )
    }

    /// Akce sekce `Větev` (#465). Skládá se tady, jako `metadataActions` — panel dostane hodnotu
    /// a `AppStore` nezná.
    ///
    /// `Mergnout…` **jen otevře potvrzení**: `mergeSubmission(for:)` vrátí `nil`, když mergnout
    /// nejde, takže se sheet nad neproveditelným mergem neotevře ani tehdy, kdyby se na zakázané
    /// tlačítko nějak kliknout dalo.
    /// `Srovnat s main` (#466) je **dvoukrokové**: první tlačítko spustí rebase v kopii repa
    /// rovnou (lokální práce, dá se vzít zpět), druhé (`Přetlačit…`) jen **otevře potvrzení** —
    /// `branchPushSubmission(for:)` vrátí `nil`, když v cache nic nečeká, takže se sheet nad
    /// ničím neotevře. Stav mezi krokem jedna a dva si drží store, takže překliknutí tabu ani
    /// zavření panelu ho neztratí.
    private var branchActions: BranchActions {
        let summary = pullRequest
        let id = summary.id
        return BranchActions(
            merge: { merge = store.mergeSubmission(for: summary) },
            sync: { Task { await store.syncBranch(summary) } },
            push: { branchPush = store.branchPushSubmission(for: summary) },
            discardSync: { Task { await store.discardSync(for: id) } },
            clearSync: { store.clearBranchSync(for: id) }
        )
    }

    /// Věta o tom, proti které hlavě nálezy platí (#392).
    ///
    /// Hlava se bere z **uloženého záznamu**, ne z detailu PR: nálezy jsou klíčované `headSha`, na
    /// kterém vznikly, takže hlava z detailu by mluvila o commitu, se kterým nemají nic společného.
    private var headNotice: Policy.FindingsHeadNotice {
        Policy.findingsHeadNotice(
            tab: store.detailTab(for: pullRequest.id),
            findingsHead: store.reviewRecord(for: pullRequest.id)?.headSha,
            openCommit: store.openedCommit(in: pullRequest.id),
            hasFindings: !visibleFindings.isEmpty
        )
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

    /// Tělo zprávy v hlavičce rozkliknutého commitu (#317). Taky ve store a taky globálně, ze
    /// stejného důvodu jako pohled na diff a rozložený panel — a hlavně proto, že `@State` v tomhle
    /// view přetéká mezi pull requesty.
    private var commitMessageExpanded: Binding<Bool> {
        Binding(get: { store.isCommitMessageExpanded }, set: { store.isCommitMessageExpanded = $0 })
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
                store.revealDraft(in: pullRequest.id)
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
    ///
    /// **Na vlastním PR se neptá** (#333): tab `Moje review` tam v panelu není, takže věta o tom,
    /// proč se do něj nedá psát, by mluvila o obrazovce, která se nekreslí — a hlavně by tvrdila,
    /// že se čeká na commit, kdežto skutečný důvod je, že review na vlastní PR neodejde.
    private var draftUnavailable: String? {
        guard ownership != .mine, !store.canComposeDraft(for: pullRequest.id) else { return nil }
        if case .failed(let detail) = store.detailState(for: pullRequest.id) {
            return "Nevím, na kterém commitu PR stojí, takže se review nemá k čemu psát. \(detail)"
        }
        return "Zjišťuji, na kterém commitu PR stojí…"
    }

    /// Čí je tenhle PR (#330). Čte se z toho, který segment panelu se kreslí a jestli se smí
    /// zakládat draft — proto to je jedno místo, ne dotaz u každého volajícího.
    private var ownership: PullRequestOwnership {
        store.ownership(of: pullRequest.id)
    }

    // MARK: - Zadání pro agenta

    private var agentPromptActions: AgentPromptActions {
        AgentPromptActions(
            toggle: { store.toggleAgentPromptOption($0) },
            isEnabled: { store.agentPromptOptions.includes($0) },
            // Otevře sheet, **nic neodesílá** — do schránky a do souboru se sahá až tam.
            compose: { promptSheet = store.agentPromptSelection(for: pullRequest.id) },
            // Zúžené zadání po pushi (#334). `nil` znamená „není co předat“, a to tlačítko hlídá
            // samo (`disabled`) — sheet bez položek by vypadal jako rozbitá aplikace.
            composeFresh: { promptSheet = store.freshAgentPromptSelection(for: pullRequest.id) },
            // Review se po pushi **nepustí samo** (#332, #334), takže tohle je jediná cesta —
            // tatáž, jakou má tlačítko v hlavičce.
            runReview: { store.startReview(for: pullRequest.id) }
        )
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
        WindowShortcutButtons(action: .nextFinding) {
            step(.forward, onlyBlocking: isShiftDown ? true : nil)
        }
        WindowShortcutButtons(action: .previousFinding) { step(.backward) }
        // Panel jde složit i rozložit **stejnou zkratkou** (#182), jak to má návrh v liště
        // nad diffem. Zkratka bydlí tady, ne v `DiffView`: panel je vidět ve víc tabech,
        // kdežto lišta jen u diffu — a přepínač, který v půlce okna nefunguje, je horší
        // než žádný.
        //
        // **V tabech bez panelu je zakázaná** (#294), a je to tatáž úvaha: složit něco, co v okně
        // není, se nedá poznat od rozbité zkratky — a hlavně by to potichu přestavělo tab, do
        // kterého se člověk vrátí. Zakázané tlačítko klávesu nebere, takže propadne dál.
        WindowShortcutButtons(
            action: .reviewPanel,
            isEnabled: store.detailTab(for: pullRequest.id).showsReviewPanel
        ) {
            withAnimation(.snappy(duration: 0.15)) {
                store.isReviewPanelExpanded.toggle()
            }
        }
        backFromCommitShortcut
        submitShortcut
        agentPromptShortcut
        cancelReviewShortcut
    }

    /// `⌘.` zastaví běžící review na PR, který je v okně (#441).
    ///
    /// **Zakázaná, dokud nic neběží.** Zastavit něco, co neběží, je akce bez následku — a taková
    /// se od rozbité klávesy nedá odlišit. Zakázané tlačítko klávesu nebere, takže propadne dál.
    ///
    /// Kontrola nálezů (#150) vlastní zkratku **nemá**: běží ve stejném okně, ale je to druhá
    /// session s vlastním tlačítkem, a jedna klávesa, která by podle stavu zastavila jednou tohle
    /// a jindy tamto, by nikdy neřekla, co udělá.
    private var cancelReviewShortcut: some View {
        WindowShortcutButtons(
            action: .cancelReview,
            isEnabled: store.isReviewing(pullRequest.id)
        ) {
            store.cancelReview(for: pullRequest.id)
        }
    }

    /// `⌘⇧P` — sestavit zadání pro agenta (#333), jak to má návrh v hlavičce panelu.
    ///
    /// **Jen na vlastním PR a jen když je co předat.** Zkratka, po které se nestane nic, je
    /// k nerozeznání od rozbité aplikace; zakázané tlačítko klávesu nebere, takže propadne dál.
    /// Panel se u toho **rozloží sám** — sheet nad složeným panelem by po zavření nechal člověka
    /// u proužku na hraně okna, tedy tam, kde volby nejsou.
    /// **Text se tady neskládá** (pravidlo #224): zkratka se vyhodnocuje při každém překreslení,
    /// takže se ptá jen na to, jestli je co předat — markdown vzniká teprve kliknutím.
    ///
    /// **Po pushi dává celé zadání, ne to zúžené** (#334), a je to schválně: panel v tom stavu
    /// nabízí `Pustit review znovu` a `Sestavit i tak (jen nové vlákno)`, kdežto zkratka je poslední
    /// cesta pro rozhodnutí „předám to i tak celé“ — a to rozhodnutí patří člověku (#113: nález
    /// sundá jedině odmítnutí). Zakázat ji nad zastaralým zadáním by znamenalo, že se zastaralé
    /// nálezy předat **nedají vůbec**, což tvrdá podmínka č. 5 nežádá: nemají se tvářit jako
    /// platné, ne zmizet.
    private var agentPromptShortcut: some View {
        WindowShortcutButtons(
            action: .agentPrompt,
            isEnabled: canComposeAgentPrompt && promptSheet == nil && !store.isPaletteOpen
        ) {
            store.revealAgentPrompt(in: pullRequest.id)
            promptSheet = store.agentPromptSelection(for: pullRequest.id)
        }
    }

    private var canComposeAgentPrompt: Bool {
        ownership == .mine && store.hasAgentPromptItems(for: pullRequest.id)
    }

    /// `⎋` zavře diff commitu a vrátí seznam (#317) — druhá cesta zpět vedle tlačítka v hlavičce.
    ///
    /// **`.cancelAction`, ne `.escape` s prázdnými modifikátory**: je to táž klávesa, ale v tomhle
    /// okně je zavedená ta první — bere ji paleta (#184) i sheety —, a míchat dva zápisy téhož
    /// znamená hádat, který z nich AppKit spáruje dřív.
    ///
    /// **Zakázaná, kdykoli Esc patří něčemu jinému**: mimo tab `Commity`, nad seznamem (není co
    /// zavírat), nad otevřenou paletou a nad potvrzením odeslání. Zakázané tlačítko klávesu nebere,
    /// takže propadne dál — tentýž vzorec jako u `⌘⏎` a `⌘2`. Sheety se tady nevyjmenovávají,
    /// protože jsou to vlastní okna a klávesu si berou samy; hlídají se jen stavy z tohohle okna.
    private var backFromCommitShortcut: some View {
        WindowShortcutButtons(action: .backFromCommit, isEnabled: canCloseCommit) {
            store.closeCommit(in: pullRequest.id)
        }
    }

    private var canCloseCommit: Bool {
        store.detailTab(for: pullRequest.id) == .commits
            && store.openedCommit(in: pullRequest.id) != nil
            && submission == nil
            && !store.isPaletteOpen
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

    /// `⌘⏎` — a od #441 i `⌃⏎` — otevře **potvrzení odeslání**, nic neodesílá (#151).
    ///
    /// **`⌃⏎` je druhá klávesa, ne náhrada.** Přibyla proto, že `⌘⏎` si v tomhle okně bere i paleta
    /// ⌘K (otevřít výsledek na GitHubu), takže nad otevřenou paletou je tahle zkratka zakázaná —
    /// `⌃⏎` se s ní nepotká vůbec. Zakázané jsou přitom **obě naráz a za týchž podmínek**: jsou to
    /// dvě tlačítka s jednou akcí, ne dvě akce.
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
        WindowShortcutButtons(
            action: .openSubmission,
            isEnabled: submission == nil && canOpenSubmission && !store.isPaletteOpen
        ) {
            draftActions.send()
        }
    }

    /// Dá se potvrzení vůbec otevřít? Rozhoduje `Policy`, ne tohle view — na totéž se ptá
    /// tlačítko v panelu.
    ///
    /// **V tabu `Zeptat se` je zakázané** (#452): composer tam odesílá otázku `⌘⏎` a dvě tlačítka
    /// s toutéž kombinací v jednom okně znamenají, že vyhraje to zaregistrované později (#151,
    /// #184). Zakázané tlačítko klávesu nebere, takže propadne composeru — tentýž vzorec jako
    /// nad otevřenou paletou o řádek níž. Rozhoduje o tom `Policy`, ne `if` nad tabem tady.
    private var canOpenSubmission: Bool {
        guard !Policy.claimsReturnShortcut(store.detailTab(for: pullRequest.id)) else { return false }
        return Policy.canOpenSubmission(
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
            changes: store.changesSinceLastVisit(for: pullRequest.id),
            lastVisit: store.visitSnapshots[pullRequest.id],
            // Obojí je „to, co mám na obrazovce, už neplatí“, takže se z toho stává **jedna
            // nabídka**: pustit review znovu. Rozdíl mezi zastaralými nálezy a zastaralým draftem
            // se řeší v panelu, kde se s nimi něco dělá.
            isStale: store.reviewRecord(for: pullRequest.id)?.isStale == true
                || store.isDraftStale(for: pullRequest.id),
            // Odznak `nálezy zastaraly` naopak mluví **jen o nálezech**, a bere je z téhož místa
            // jako hlavička nad taby (#284) — jinak by o témže stavu tvrdily každá něco jiného.
            hasStaleFindings: store.staleFindings(for: pullRequest.id)?.hasFindings == true,
            movedHead: store.movedHead(for: pullRequest.id),
            rerun: { store.startReview(for: pullRequest.id) },
            showAdded: showAdded,
            dismissChanges: { store.markChangesAsSeen(for: pullRequest.id) },
            pullRequest: pullRequest
        )
    }

    /// `Ukázat, co přibylo` (#284) — `nil`, když se nová hlava nemá s čím porovnat.
    ///
    /// Přepnutí tabu patří **sem**, ne do store: který tab je vidět, je věc okna, kdežto store
    /// jen drží rozsah a jeho načtení. Načítá se `Task`em, tab se přepne hned — jinak by kliknutí
    /// na sekundu nic neudělalo a vypadalo by to jako zaseklé tlačítko.
    private var showAdded: (() -> Void)? {
        guard store.incrementalDiffRange(for: pullRequest.id) != nil else { return nil }
        return {
            store.setDetailTab(.filesChanged, for: pullRequest.id)
            Task { await store.showIncrementalDiff(for: pullRequest) }
        }
    }

    /// Tab `Kontroly` (#215) — a od #306 ve **všech čtyřech stavech**, protože se kreslí i u PR
    /// bez CI a musí mít odpověď na každý stav dat (`Policy.checksTab`). Podob je z toho **pět**:
    /// `list` kreslí seznam se zastaralostí i bez ní.
    ///
    /// Rozdíl mezi „ještě nedorazily“ a „žádné nejsou“ je ten podstatný: dokud se čeká na odpověď,
    /// **nesmí v tabu stát, že PR CI nemá**. Je to tentýž vzor jako `čisté` proti `failed`
    /// u review.
    ///
    /// Switch je tady, ne v `ChecksView`: je to tatáž stavba jako u `diffu` (načítám / nepovedlo se
    /// / obsah), takže se prázdné stavy hledají v obou tabech na jednom místě — a `ChecksView`
    /// zůstává tím, co kreslí **seznam**, tedy i tím, co se dá měřit bez obcházení stavů (#294).
    @ViewBuilder private var checks: some View {
        switch store.checksTabState(for: pullRequest.id) {
        case .loading:
            // Tatáž hláška jako u diffu, a schválně bez zmínky o CI: „nedorazily“ o kontrolách
            // netvrdí nic, což je přesně to, co se v tuhle chvíli ví.
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Načítám kontroly…")
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .empty:
            EmptyStateView(
                nature: .calm,
                symbol: "checklist",
                title: "Tenhle PR nemá kontroly",
                // **Klidná povaha a věta o tom, že to není porucha** — právě na tom stojí obrat
                // proti #215, kde prázdný tab s nadpisem tvrdil, že se něco nepovedlo.
                message: "Na GitHubu se k němu neváže žádný check. "
                    + "Není to porucha — repo CI nemá, nebo se na tuhle větev nepouští."
            )
        case .failed(let reason):
            EmptyStateView(
                nature: .failure,
                symbol: "exclamationmark.triangle",
                title: "Kontroly se nepodařilo načíst",
                message: "Bez nich není poznat, jestli PR žádné nemá, nebo se jen nenačetly.",
                // Text od `gh` zůstává, jak přišel: je to jediné, z čeho se pozná, co dělat dál.
                detail: reason,
                primary: .init(title: "Zkusit znovu", run: reloadChecks)
            )
        case .list(let list, let failure):
            VStack(spacing: 0) {
                if let failure { staleChecksNotice(failure) }
                checksList(list)
            }
        }
    }

    /// Poslední pokus o načtení selhal, ale stará sada zůstala (#215) — takže je vidět **poslední
    /// známý stav**, ne dnešní. Sazbu drží `StaleNoticeView`, protože totéž potřebují i `Commity`
    /// (#316) a dvě kopie téže věty se rozejdou při první úpravě.
    private func staleChecksNotice(_ reason: String) -> some View {
        StaleNoticeView(
            text: "Kontroly se nepodařilo načíst znovu, tohle je poslední známý stav. \(reason)",
            retry: reloadChecks
        )
    }

    /// Zopakuje načtení kontrol (#306).
    ///
    /// Vlastní cesta k `loadChecks`, ne přes `loadDetail`: ten má cache podle `updatedAt`, takže
    /// po chybě sítě už znovu nic nedotáhne a tab by v poruše zůstal až do dalšího commitu.
    private func reloadChecks() {
        Task { await store.loadChecks(for: pullRequest.id) }
    }

    /// Seznam checků z GitHub Actions a detail spadlého (#214).
    ///
    /// Detail se tahá **až na kliknutí a jen na ten jeden check**; podrobnosti u `AppStore+Checks`.
    private func checksList(_ list: [PullRequestCheck]) -> some View {
        let open = store.expandedCheck(in: pullRequest.id)
        return ChecksView(
            checks: list,
            expanded: open,
            detail: open.flatMap { store.checkDetail(of: $0, in: pullRequest.id) },
            toggle: { check in
                // Sbalení i rozbalení **zavře sheet a text z něj pustí** — jinak by ho okno drželo
                // dál, i když ho store zahodil.
                logSheet = nil
                store.toggleCheck(check, in: pullRequest.id)
            },
            // Anotace ukazují na `soubor:řádek`, což je tentýž tvar, jaký okno umí kreslit — takže
            // se skáče **tou samou cestou** jako z nálezu a z palety (#184).
            jump: { path, line in
                guard let anchor = anchor(inFile: path, line: line) else { return }
                scroll(to: anchor)
            },
            showFullLog: { check, full in
                logSheet = CodeText(
                    kind: .log,
                    id: "log:\(check.name)",
                    title: CodeSheetText.logTitle(check: check.name),
                    slug: CodeSheetText.logSlug(full, subject: "\(pullRequest.repo)#\(pullRequest.number)"),
                    // **Snímek se přiznává jen u běžícího jobu** (#417): u doběhlého by slovo
                    // „snímek“ varovalo před něčím, co se nemůže stát. A okamžik je u snímku ten,
                    // kdy se log **stáhl** (`JobLog.fetchedAt`), ne kdy se kliklo — text leží
                    // v paměti od rozbalení checku a od té doby na GitHubu narostl.
                    note: CodeSheetText.logNote(
                        outcome: check.outcome,
                        duration: check.duration,
                        at: check.outcome == .running ? full.fetchedAt : check.completedAt
                    ),
                    // **`nil`, ne jméno checku** — u logu se nemá co obarvovat, viz `CodeText.path`.
                    path: nil,
                    code: full.text,
                    // Odkaz na běh na GitHubu je cesta k novějšímu textu; `nil` u checku, který
                    // odkaz nemá (bors odkazuje mimo GitHub, viz `PullRequestCheck.jobID`).
                    link: check.link
                )
            }
        )
    }

    /// Tab `Commity` (#316) — seznam commitů PR, **od nejnovějšího** (`Policy.commitsNewestFirst`).
    ///
    /// **Tři stavy, a prázdný mezi nimi není**: pull request bez commitů neexistuje, takže by
    /// klidná hláška o prázdnu tvrdila něco, co platit nemůže — prázdná odpověď je proto porucha
    /// (`Policy.commitsTab`). Panel s nálezy se v tomhle tabu od #392 **kreslí** a je to zapsané
    /// u `PullRequestTab.showsReviewPanel` — i s tím, jak se u rozkliknutého staršího commitu pozná,
    /// že nálezy o kódu na obrazovce nemluví.
    @ViewBuilder private var commits: some View {
        switch store.commitsTabState(for: pullRequest.id) {
        case .loading:
            // Tatáž hláška jako u diffu a kontrol, a schválně bez počtu: dokud odpověď nedorazila,
            // o commitech nevíme nic.
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Načítám commity…")
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .failed(let reason):
            EmptyStateView(
                nature: .failure,
                symbol: "exclamationmark.triangle",
                title: "Commity se nepodařilo načíst",
                message: "Seznam je jediné místo, ze kterého je vidět, v jakém kroku se co stalo.",
                // Text od `gh` zůstává, jak přišel: je to jediné, z čeho se pozná, co dělat dál.
                detail: reason,
                primary: .init(title: "Zkusit znovu", run: reloadCommits)
            )
        case .list(let list, let failure):
            // **Rozkliknutý commit přebíjí seznam, ne poruchu nad ním** (#317): okrová věta
            // o zastaralém seznamu patří k seznamu, a v diffu commitu by mluvila o něčem, co
            // zrovna není vidět.
            if let open = Policy.openCommit(store.openedCommit(in: pullRequest.id), in: list) {
                commitDiff(of: open, in: list)
            } else {
                VStack(spacing: 0) {
                    if let failure { staleCommitsNotice(failure) }
                    CommitListView(
                        commits: list,
                        head: store.head(of: pullRequest.id),
                        opened: store.lastOpenedCommit(in: pullRequest.id),
                        open: { store.openCommit($0.sha, in: pullRequest.id) }
                    )
                }
            }
        }
    }

    /// Diff jednoho commitu (#317) — obsah tabu po rozkliknutí řádku.
    ///
    /// Skládá se tady, protože klíč rozbalování a sbalování zná store: obojí se v tomhle tabu
    /// klíčuje **i sha commitu**, aby se kontext nebral z hlavy PR a sbalení souboru nepřeteklo
    /// do `Změněných souborů`.
    private func commitDiff(of commit: PullRequestCommit, in list: [PullRequestCommit]) -> some View {
        CommitDiffView(
            commit: commit,
            state: store.commitDiffState(of: commit, in: pullRequest.id),
            position: Policy.commitPosition(of: commit.sha, in: list),
            url: Policy.commitURL(of: commit.sha, in: pullRequest.repo),
            isMessageExpanded: commitMessageExpanded,
            expansion: commitExpansion(of: commit.sha),
            folding: commitFolding(of: commit.sha),
            layout: diffLayout,
            back: { store.closeCommit(in: pullRequest.id) },
            showFiles: { store.setDetailTab(.filesChanged, for: pullRequest.id) },
            // Zopakování jde **touž cestou jako první otevření** (`openCommit`), ne přímo na
            // `loadCommitDiff`: jinak by tlačítko stáhlo diff, ale nechalo v okně starou chybu,
            // protože stav by se nikdy nevrátil na `loading`.
            retry: { store.openCommit(commit.sha, in: pullRequest.id) }
        )
    }

    /// Rozbalování kontextu v diffu commitu — obsah souborů **z toho commitu**.
    private func commitExpansion(of sha: String) -> DiffExpansionActions {
        let id = pullRequest.id
        return DiffExpansionActions(
            state: { store.expansion(of: $0.displayPath, in: id, commit: sha) },
            reveal: { store.reveal($1, of: $0.displayPath, in: id, commit: sha) },
            collapse: store.hasRevealedLines(in: id, commit: sha)
                ? { store.collapseRevealedLines(in: id, commit: sha) }
                : nil
        )
    }

    /// Sbalování souborů v diffu commitu. Vlastní klíč, takže se sbalení nesdílí se
    /// `Změněnými soubory` — proč, je u `AppStore.isFolded(_:in:commit:)`.
    private func commitFolding(of sha: String) -> DiffFoldingActions {
        let id = pullRequest.id
        return DiffFoldingActions(
            isFolded: { store.isFolded($0.displayPath, in: id, commit: sha) },
            toggle: { store.toggleFolded($0.displayPath, in: id, commit: sha) },
            foldAll: { store.foldAll($0.map(\.displayPath), in: id, commit: sha) },
            unfoldAll: { store.unfoldAll(in: id, commit: sha) }
        )
    }

    /// Poslední pokus o načtení commitů selhal, ale stará sada zůstala (#316) — takže je vidět
    /// **poslední známý stav**, ne dnešní. Tentýž `StaleNoticeView` jako u kontrol.
    private func staleCommitsNotice(_ reason: String) -> some View {
        StaleNoticeView(
            text: "Commity se nepodařilo načíst znovu, tohle je poslední známý stav. \(reason)",
            retry: reloadCommits
        )
    }

    /// Zopakuje načtení commitů (#316). Vlastní cesta k `loadCommits`, ne přes `loadDetail`: ten má
    /// cache podle `updatedAt`, takže by po chybě sítě už znovu nic nedotáhl a tab by v poruše
    /// zůstal až do dalšího commitu.
    private func reloadCommits() {
        Task { await store.loadCommits(for: pullRequest.id) }
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
            copyCommand: copyCommand(in: timelines),
            showRawSession: { target in
                rawSession = target
                Task { await store.openRawSession(target) }
            },
            // Terminál (#453, od #460 **zásuvka místo `Terminal.app`**). Stav ani sheet sem
            // nepatří: co se povede, je vidět v zásuvce, která se otevřela, a co ne, ohlásí
            // stavový řádek. `nil` = v tomhle okně zásuvka není, takže se `▶` **nekreslí** —
            // tichý pád zpátky do `Terminal.app` by byla dvě chování pod jednou ikonou.
            resumeInDrawer: store.hasTerminalDrawer
                ? { session in Task { await store.resumeInDrawer(session, for: pullRequest.id) } }
                : nil,
            slug: "\(pullRequest.repo)#\(pullRequest.number)"
        )
    }

    /// Tab `Zeptat se` (#452) — rozhovor nad tímhle PR.
    ///
    /// Skládá se tady, ne ve view: `Policy` rozhoduje výčtem, co je na obrazovce (prázdno s třemi
    /// otázkami k odpíchnutí, nebo rozhovor s prstýnkem), a `AppStore` drží stav i cestu ven do
    /// session. View z toho jen kreslí.
    private var ask: some View {
        // **Jedno pole chipů pro pruh i pro nabídku otázek** (#452): kdyby se počítalo dvakrát,
        // mohl by pruh hlásit `3 nálezy` a otázka se ptát na jiné číslo — a přesně tahle třída
        // chyby už jednou u tohohle tabu byla (materiál se skládal jinde než pruh).
        let chips = store.askContextChips(for: pullRequest.id)
        return AskView(
            content: Policy.askTab(
                conversation: store.askConversation(for: pullRequest.id),
                isAnswering: store.isAnswering(pullRequest.id),
                context: chips
            ),
            chips: chips,
            activity: store.askActivityLine(for: pullRequest.id),
            draft: store.askDraft(for: pullRequest.id),
            block: store.askBlock(for: pullRequest.id),
            persistDraft: { store.setAskDraft($0, for: pullRequest.id) },
            send: { store.askQuestion($0, about: pullRequest.id) },
            cancel: { store.cancelAsk(for: pullRequest.id) },
            reset: { store.resetAskConversation(for: pullRequest.id) },
            jump: { jumpToCode(file: $0.file, line: $0.line) }
        )
        // **Vlastní identita podle PR**, a je to podmínka správnosti: detail se mezi pull requesty
        // **znovupoužívá** (proto ty `.task(id: pullRequest.id)` výš), takže bez tohohle by si
        // composer nechal rozepsanou otázku z předchozího PR a při zmizení ji uložil do jeho
        // zálohy. `onDisappear` starého `AskView` přitom doběhne s uzávěry starého PR, takže se
        // rozepsaná otázka uloží tam, kam patří.
        .id(pullRequest.id)
    }

    /// Skok z odpovědi na místo v kódu (#452).
    ///
    /// Jde **toutéž cestou jako skok z nálezu** (`anchor(inFile:line:)` + `scroll(to:)`), takže se
    /// nemá čím rozejít v tom, co je „to místo“ — a když soubor v diffu není, **nestane se nic**:
    /// skákat naslepo je horší než nehnout se. Rozbalit sbalený soubor umí ta kotva sama.
    private func jumpToCode(file: String, line: Int) {
        guard let anchor = anchor(inFile: file, line: line) else { return }
        scroll(to: anchor)
    }

    /// Zkopíruje příkaz, jakým by se reviewer spustil teď — `Zkopírovat příkaz` u spadlé session
    /// (#242).
    ///
    /// `nil`, dokud nevíme, proti čemu se diffuje: příkaz bez `baseSha` by nebyl spustitelný, a
    /// tlačítko, které zkopíruje něco nefunkčního, je horší než žádné. Příkaz se skládá **až při
    /// kliknutí** — nese celý prompt, takže by se jinak stavěl při každém překreslení tabu.
    private func copyCommand(in timelines: [ReviewerTimeline]) -> ((String) -> Void)? {
        guard let detail = loadedDetail else { return nil }
        let model = store.configuration.global.model
        // Tatáž šablona, jakou dostane skutečný běh (#281), a poskládá se toutéž funkcí —
        // dvě místa s vlastním textem by se rozešla první úpravou věty.
        let promptTemplate = store.configuration.global.reviewPrompt
        return { skill in
            Clipboard.copy(ClaudeCommand.shellCommand(
                promptTemplate: promptTemplate,
                skillID: skill,
                baseSha: detail.baseSha,
                model: model,
                worktree: timelines.first { $0.skill == skill }?.worktree,
                // Ptá se **disku**, ne záznamu (#120): tlačítko skládá příkaz, jakým by se
                // reviewer spustil *teď*, takže věta o zadání do něj patří právě tehdy, když by
                // ten soubor dostal i skutečný běh. Zeptat se je levné — příkaz se skládá až při
                // kliknutí, ne při každém překreslení tabu.
                intentFile: store.intents?.existingFile(for: detail.id, at: detail.headSha)
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

    /// Tab `Změněné soubory` — celý diff PR, nebo **jen to, co od minule přibylo** (#284).
    ///
    /// Rozsah nedostal vlastní tab a ve store nenahrazuje celý diff: je to **pohled** na tentýž
    /// tab, ze kterého se vyskočí jedním tlačítkem v liště. Review se pořád píše proti celému
    /// diffu, takže co se v rozsahu napíše, sedí na tomtéž místě jako všude jinde — čísla řádků
    /// jsou v obou případech čísla na dnešní hlavě.
    @ViewBuilder private var diff: some View {
        if let incremental = store.incrementalDiff(for: pullRequest.id) {
            VStack(alignment: .leading, spacing: 0) {
                IncrementalDiffBar(
                    range: incremental.range,
                    showAll: { store.hideIncrementalDiff(for: pullRequest.id) }
                )
                incrementalDiff(incremental)
            }
            // **Šířku předat, ne vyjednávat** (#220): pod tímhle uzlem visí celý diff, takže
            // `maxWidth: .infinity` by nad ním přidalo úroveň vyjednávání navíc. Výška pružná
            // zůstává — o tu se nikdo nepře.
            .filling(alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        } else {
            fullDiff
        }
    }

    @ViewBuilder private var fullDiff: some View {
        switch store.diffState(for: pullRequest.id) {
        case .loaded(let diff, _) where diff.isEmpty:
            placeholder("Diff je prázdný — tenhle pull request nic nemění.")
        case .loaded(let diff, _):
            diffView(of: diff)
        case .failed(let detail):
            diffFailure(detail)
        case .loading, nil:
            loading("Načítám diff…")
        }
    }

    /// Rozsah „co přibylo“. Prázdný výsledek je **vlastní hláška**, ne ta od celého diffu:
    /// „tenhle pull request nic nemění“ by nad rozsahem bylo tvrzení o něčem jiném.
    @ViewBuilder private func incrementalDiff(_ incremental: IncrementalDiff) -> some View {
        switch incremental.content {
        case .loaded(let diff) where diff.isEmpty:
            placeholder("Od tvé poslední návštěvy se v souborech nic nezměnilo.")
        case .loaded(let diff):
            diffView(of: diff)
        case .failed(let detail):
            incrementalDiffFailure(detail)
        case .loading:
            loading("Načítám, co přibylo…")
        }
    }

    /// Jeden diff se všemi bublinami. Bere ho **celý diff i rozsah** — nálezy, vlákna
    /// i rozdělané komentáře se kotví na `soubor:řádek` dnešní hlavy, takže se v obou pohledech
    /// pověsí na totéž místo; co v rozsahu není vidět, se chová stejně jako soubor mimo diff.
    private func diffView(of diff: Diff) -> some View {
        DiffView(
            diff: diff,
            subject: pullRequest.id.description,
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
    }

    private func loading(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(verbatim: text)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Rozsah se **nezkouší znovu sám** — pouští ho člověk, takže i opakování je jeho rozhodnutí.
    /// Vedle je cesta zpátky na celý diff: ten je načtený a je to to, co se v tabu čeká.
    private func incrementalDiffFailure(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Nepodařilo se zjistit, co přibylo", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Palette.find)
            Text(verbatim: detail)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Zkusit znovu", systemImage: "arrow.clockwise") {
                    Task { await store.showIncrementalDiff(for: pullRequest) }
                }
                Button("Ukázat celý diff") { store.hideIncrementalDiff(for: pullRequest.id) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func diffFailure(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Diff se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Palette.find)
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
            // Zkratka `⌘.` (#441) je jinak vidět jedině v paletě ⌘K — a k běžícímu review se
            // chodí sem, ne tam.
            .help(Policy.shortcutHelp("Zastavit běžící review", .cancelReview))
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
                .foregroundStyle(Palette.crit)
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
        .background(Palette.crit.opacity(0.08), in: .rect(cornerRadius: 8))
    }

    private func prepare() {
        Task { await store.prepareCheckout(for: pullRequest.id) }
    }
}
