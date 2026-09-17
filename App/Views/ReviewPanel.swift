import SwiftUI

/// Panel napravo od diffu: nálezy u kódu a rozdělané review.
///
/// Je to **jediné místo pro nálezy bez `file:line`** u kódu — chybějící testy, poznámky
/// k architektuře. Právě kvůli nim nestačí bubliny.
///
/// **Napravo, ne dole** (#182). Do té doby si bral výšku, které je v diffu nejmíň: kód je
/// dlouhý a úzký, takže dole se pere o to jediné, čeho je málo. Napravo bere šířku, které je
/// v okně přes celou obrazovku dost — spočítané v zadání #182: v pohledu pod sebou se i na 14"
/// vejde 126 znaků na stranu, tedy slib „PHP na 120 znaků se vejde“ drží. V pohledu vedle sebe
/// ho neunese žádný displej pod 27"; složení sloupců v tom režimu řeší #188.
///
/// **Dva taby, ne tři** (#242, do té doby `FindingsPanel`). `Průběh` se odstěhoval do vlastní
/// záložky PR: je to záznam běhu, který se u kódu nečte, a u spadlé session se do 300 bodů nevešel
/// ani důvod, ani konec logu. Nálezy naopak **zůstávají** — tab `Nálezy` je druhý pohled na tu samou
/// věc, ne přesun.
///
/// Složený je **proužek na hraně** s počtem nálezů a značkou rozdělaného review, ne zmizelý panel:
/// schovaná práce je práce, o které nikdo neví.
struct ReviewPanel: View {
    /// `nil` = žádný uložený záznam. Rozhoduje o tom, proč je seznam nálezů prázdný.
    let record: ReviewRecord?
    @Binding var isExpanded: Bool
    /// Odskok do diffu na místo nálezu.
    let jump: (Finding) -> Void
    /// Nálezy k zobrazení — po filtru chipů, takže ne nutně všechny ze záznamu.
    var findings: [Finding] = []
    /// Jak jsem nálezy posoudil (#113). Celá mapa ze záznamu — karta si z ní vezme to své.
    var dismissals: [FindingKey: FindingDismissal] = [:]
    /// Co o nálezech řekla kontrola z minula (#150). Prázdné = neběžela, nebo pro hlavu PR
    /// neplatí; karta pak žádný odznak nekreslí.
    var rechecks: [FindingKey: RecheckStatus] = [:]
    /// Odmítnutí a vrácení nálezu. Kontextové menu se bez toho nekreslí.
    var findingActions: FindingActions?
    /// Otevření místa nálezu v editoru (#530). `nil` = **není zvolený editor**, takže se tlačítko
    /// na kartách nekreslí vůbec — ne zašedle.
    var editor: EditorActions?
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    var isRunning = false
    /// Ke kterému PR panel patří. Potřebuje to tab s rozdělaným review — na identitě PR
    /// visí, kam se doručí rozepsaný text při přepnutí.
    let pullRequest: PRIdentifier
    /// Rozdělané review. `nil` = ještě se nezačalo psát.
    var draft: ReviewDraft?
    /// Verdikt, který platí — moje volba, nebo návrh z nálezů (#114). Nebere se z `draft`:
    /// návrh se neukládá, takže v draftu není.
    var draftVerdict: EffectiveVerdict?
    var isDraftStale = false
    /// Je to můj vlastní PR? Pak se návrh nepředvyplňuje a panel to vysvětlí.
    var isOwnPullRequest = false
    /// Čí je PR (#330). **Rozhoduje, který druhý segment se kreslí**: na cizím `Moje review`,
    /// na vlastním `Zadání`. Není to totéž jako `isOwnPullRequest`: ten se ptá konverzace na to,
    /// co GitHub udělá s odeslaným review, kdežto tohle je rozřazení podle autora, které platí
    /// od první obtažené obrazovky.
    var ownership: PullRequestOwnership = .theirs
    /// Zadání pro agenta (#333). `nil` u cizího PR — tam se panel na něj neptá.
    var agentPrompt: AgentPrompt?
    var agentPromptActions = AgentPromptActions()
    /// Co zbývá předat (#334). Panel z toho kreslí razítko, novinky nebo varování po pushi;
    /// rozhoduje `Policy.handoff`, tedy tatáž funkce jako u odznaku v railu.
    var handoff: HandoffReport = .never
    /// Stav načtení konverzace — panel se zadáním z něj kreslí větu o tom, že cizí komentáře
    /// nemá odkud vzít.
    var conversation: ConversationState?
    /// Proč se do draftu nedá psát. `nil` = dá se.
    var draftUnavailable: String?
    var draftActions = DraftActions()
    var jumpToComment: (ReviewDraftComment) -> Void = { _ in }
    /// Labely a vyžádaní reviewery (#392). `nil` = ještě se nenačetly; prázdný snímek je platná
    /// odpověď a znamená, že se sekce nekreslí.
    var metadata: MetadataState?
    /// Smí se to měnit? Na cizím PR `.absent`, tedy **žádné akce** — ne zašedlé.
    var metadataEditing: Policy.MetadataEditing = .absent
    var knownLabels: [PullRequestLabel] = []
    var reviewerCandidates: [ReviewerCandidate] = []
    /// Proč je nabídka prázdná (`nil` = načetla se). „Repo žádné labely nezná“ a „nepodařilo se je
    /// zjistit“ se v nabídce nesmí slít.
    var labelPickerFailure: String?
    var reviewerPickerFailure: String?
    var hasLoadedLabels = false
    var hasLoadedCandidates = false
    var metadataActionState: MetadataActionState?
    var metadataActions = MetadataActions()
    /// Sekce `Větev` (#465) — stav větve a to, co se s ní dá udělat. `nil` na cizím PR, kde se
    /// nekreslí vůbec; rozhoduje o tom `Policy.branchSection`, ne panel.
    var branch: Policy.BranchSection?
    var branchActions = BranchActions()
    /// Jak dopadlo poslední srovnání větve (#466). `nil` = nedělo se nic.
    var branchSync: BranchSyncState?
    /// Co zapisující session nad tímhle PR dělala — posledních pár kroků (#511, mění #467).
    /// Prázdné = neběží nic, nebo ještě nic neřekla.
    var branchSyncTail: [String] = []
    /// Proti kterému kódu nálezy platí (#392). Kreslí se **jen v tabu `Commity`** — rozhoduje
    /// `Policy.findingsHeadNotice`, ne panel.
    var headNotice: Policy.FindingsHeadNotice = .none

    /// Šířku si drží uživatel taháním a přežívá restart — kolik místa chce dát nálezům,
    /// ví jen on. **Vlastní klíč** (#182), ne přejmenovaná výška: uložených 220 by jako šířka
    /// dalo panel užší, než v jakém se dá nález přečíst.
    @AppStorage("findingsPanelWidth") private var width = ReviewPanel.defaultWidth
    /// Kde stojí kurzor procházení (#187). Karta na tom místě dostane rámeček, takže panel
    /// a diff ukazují **totéž** — bez toho by po skoku šipkou nebylo v seznamu poznat, kde jsem.
    var current: FindingPlace?

    /// Který tab je vidět. Drží ho `AppStore` (#242): přidání poznámky do těla review se z diffu
    /// musí umět přepnout na tab, do kterého ta poznámka spadla, **a rozložit složený panel** —
    /// jinak text zmizí někam, kde ho nikdo nehledá.
    @Binding var tab: ReviewPanelTab
    /// Šířka na začátku tažení. Bez ní se posun načítá z každé události znovu a panel
    /// utíká pryč.
    @State private var widthAtDragStart: Double?

    /// Šířka z návrhu (`grid-template-columns: … 300px`) a meze kolem ní.
    ///
    /// Podlaha je **změřená na obsahu**, ne odhadnutá: karta nálezu (#175) nese kategorii, odznak
    /// a shrnutí, a pod 240 body se shrnutí láme po dvou slovech. Strop drží slib z `CLAUDE.md`,
    /// že diff dostane šířku — panel přes půl okna by ho porušil bez ohledu na displej.
    private static let defaultWidth = 300.0
    private static let minimumWidth = 240.0
    private static let maximumWidth = 520.0
    /// Šířka složeného proužku, taky z návrhu (`.work.wide`).
    private static let collapsedWidth = 38.0

    /// Uložená šířka se ořezává **při použití**, ne jen při tažení: v `UserDefaults` může
    /// být cokoli (ruční editace, jiný rozsah ze starší verze) a `frame(width:)` se
    /// zápornou hodnotou rozhodí celé okno.
    private var clampedWidth: Double { clamp(width) }

    /// Šířka, která v bloku labelů zbývá na chipy — panel minus jeho odsazení. **Spočítaná, ne
    /// vyjednaná**: dvouřádkový strop a `+N` se z pružného rozvržení vyjádřit nedají (pravidlo
    /// #220). Odsazení si bere **z toho typu, který ho kreslí**, ne z vlastní konstanty.
    private var metadataContentWidth: Double {
        PanelMetadataView.contentWidth(inPanelOf: clampedWidth)
    }

    private func clamp(_ value: Double) -> Double {
        min(max(Self.minimumWidth, value), Self.maximumWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isExpanded {
                resizeHandle
                VStack(spacing: 0) {
                    header
                    // **Nad segmenty** (#392): platí to pro celý PR, ne pro vybraný segment.
                    PanelMetadataView(
                        state: metadata,
                        editing: metadataEditing,
                        // Repo se bere z identity PR, ne z vlastního parametru — jedna pravda o tom,
                        // kam se nový label založí (#413).
                        repo: pullRequest.repo,
                        contentWidth: metadataContentWidth,
                        known: knownLabels,
                        candidates: reviewerCandidates,
                        labelPickerFailure: labelPickerFailure,
                        reviewerPickerFailure: reviewerPickerFailure,
                        hasLoadedLabels: hasLoadedLabels,
                        hasLoadedCandidates: hasLoadedCandidates,
                        actionState: metadataActionState,
                        actions: metadataActions
                    )
                    // **Pod labely a reviewery** (#465), jak to kreslí návrh: je to třetí věc,
                    // která platí pro celý pull request, ne pro vybraný segment.
                    if let branch {
                        PanelBranchView(
                            section: branch,
                            contentWidth: metadataContentWidth,
                            syncState: branchSync,
                            syncTail: branchSyncTail,
                            // Tentýž stav jako blok labelů nad ním (#482) — a je to schválně jedna
                            // hodnota, ne dvě: dvě odesílání nad jedním PR naráz neběží, takže
                            // rozhoduje jedině to, **kde** se věta o neúspěchu kreslí
                            // (`MetadataActionState.noticePlace`).
                            actionState: metadataActionState,
                            actions: branchActions
                        )
                    }
                    segments
                    content
                }
                .frame(width: clampedWidth)
            } else {
                collapsedStrip
            }
        }
        .background(Palette.chrome)
        .overlay(alignment: .leading) { Rectangle().fill(Palette.lineSoft).frame(width: 1) }
    }

    // MARK: - Hlavička a proužek

    /// Řádek nad segmenty: sbalení a zkratka k němu.
    ///
    /// **Stáří výsledku a `Zahodit nálezy` se odsud odstěhovaly do tabu `Nálezy`** (#242). Platí
    /// pro uložený záznam, ne pro panel, a v tabu přes celé okno je na ně místo — kdežto tady se
    /// o 300 bodů praly s tím, co se čte.
    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { isExpanded = false }
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(Palette.ink3)
                    .font(.caption)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(Policy.shortcutHelp("Složit panel", .reviewPanel))
            .accessibilityLabel("Složit panel")
            Spacer(minLength: 4)
            Text(verbatim: Policy.windowShortcut(.reviewPanel).display)
                .font(.system(size: 9.5, design: .monospaced))
                .padding(.horizontal, 4)
                .foregroundStyle(Palette.ink3)
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line) }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    /// Složený panel — proužek na hraně okna, ne zmizelý panel.
    ///
    /// Nese **počet nálezů** a značku rozdělaného review, takže je z něj poznat, že je co číst
    /// i že něco leží rozepsané. Bez těch značek je složení tichá ztráta práce.
    private var collapsedStrip: some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { isExpanded = true }
        } label: {
            VStack(spacing: 9) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink3)
                if !findings.isEmpty {
                    stripMark(
                        "\(findings.count)",
                        tint: hasBlocking ? Palette.crit : Palette.ink2,
                        background: hasBlocking ? Palette.crit.opacity(0.15) : Palette.raised
                    )
                }
                draftMark
                // Na vlastním PR je vedle nálezů zadání, ne review (#333) — proužek má říkat,
                // co za ním je.
                Text(verbatim: ownership == .mine ? "nálezy · zadání" : "nálezy · review")
                    .font(.system(size: 10.5))
                    .tracking(0.6)
                    .foregroundStyle(Palette.ink3)
                    // Svislý text jako v návrhu (`writing-mode: vertical-rl`). Otočením, protože
                    // svislou sazbu SwiftUI neumí — a proužek je na popisek naležato moc úzký.
                    //
                    // Po otočení se omezuje **výška, ne šířka**: rámeček zůstává vodorovný, takže
                    // šířkou se text ořízne a přeleze přes odznak nad sebou.
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    // Otočený otisk (úzký a vysoký) — bez něj si proužek vezme šířku
                    // nenatočeného textu a roztáhne se.
                    .frame(width: 13, height: 84)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .frame(width: Self.collapsedWidth, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(collapsedHelp)
        .accessibilityLabel("Rozložit panel")
        .accessibilityValue(collapsedHelp)
    }

    /// Značka rozdělaného review v proužku (#242).
    ///
    /// Počet **komentářů**, když nějaké jsou, jinak puntík: draft, ve kterém je jen vybraný verdikt
    /// nebo tělo, je plnohodnotný (čtvrtina vzorku z #63), takže „0“ by o něm lhala. Zastaralý je
    /// okrový — je to „platilo to, dneska už ne“, ne výstraha.
    @ViewBuilder private var draftMark: some View {
        if let draft {
            let tint = isDraftStale ? Palette.stale : Palette.accent
            if draft.comments.isEmpty {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .help(draftHelp)
            } else {
                stripMark("\(draft.comments.count)", tint: tint, background: tint.opacity(0.15))
                    .help(draftHelp)
            }
        }
    }

    private var draftHelp: String {
        isDraftStale
            ? "Rozdělané review je psané proti staršímu commitu"
            : "Něco leží rozepsané v mém review"
    }

    private var collapsedHelp: String {
        var parts: [String] = []
        if !findings.isEmpty {
            parts.append(Plural.czech(findings.count, one: "nález", few: "nálezy", many: "nálezů"))
        }
        if let draft {
            parts.append(draft.comments.isEmpty
                ? "rozdělané review"
                : Plural.czech(
                    draft.comments.count,
                    one: "komentář v mém review",
                    few: "komentáře v mém review",
                    many: "komentářů v mém review"
                ))
        }
        // Zkratka je z katalogu (#441), ne napsaná vedle — jinak by se s klávesou rozešla.
        let shortcut = Policy.windowShortcut(.reviewPanel).display
        guard !parts.isEmpty else { return "Rozložit panel (\(shortcut))" }
        return "\(parts.joined(separator: " · ")) — rozložit panel (\(shortcut))"
    }

    private func stripMark(_ text: String, tint: Color, background: Color) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(background, in: .rect(cornerRadius: 4))
    }

    private var hasBlocking: Bool {
        Policy.tally(of: findings, dismissals: dismissals, categories: blockingCategories).blocking > 0
    }

    /// Segmenty z návrhu, ne `Picker(.segmented)`: systémový přepínač si bere výšku
    /// i šířku podle textu a v panelu 300 bodů se `Nálezy · 12 / Moje review ●` nevejde.
    /// Sazba je z `.seg` — poloměr 6, 11,5 bodu, aktivní na vyvýšené ploše.
    ///
    /// **Který druhý segment to je, rozhoduje `Policy.reviewPanelTabs`** (#333): na vlastním PR
    /// `Zadání`, na cizím `Moje review`. Nikdy oba — verdikt na vlastním PR GitHub odmítne, takže
    /// tam nemá co dělat ani jako zašedlý.
    private var segments: some View {
        HStack(spacing: 2) {
            ForEach(Policy.reviewPanelTabs(for: ownership), id: \.self) { tag in
                switch tag {
                case .findings:
                    segment("Nálezy", count: findings.isEmpty ? nil : findings.count, tag: .findings)
                case .draft:
                    segment(draftLabel, tag: .draft)
                case .agentPrompt:
                    // Nula se nekreslí — „Zadání 0“ tvrdí, že se počítalo a nic nevyšlo, kdežto
                    // důvod (nenačtená konverzace, nespuštěné review) je uvnitř tabu.
                    segment("Zadání", count: agentPromptCount, tag: .agentPrompt)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 9)
        .padding(.bottom, 4)
    }

    private func segment(_ title: String, count: Int? = nil, tag: ReviewPanelTab) -> some View {
        Button {
            tab = tag
            // Složený panel bez obsahu vypadá jako chyba — přepnutí segmentu ho proto otevře.
            isExpanded = true
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: title)
                if let count {
                    Text(verbatim: "\(count)")
                        .monospacedDigit()
                        .foregroundStyle(tab == tag ? Palette.ink2 : Palette.ink3)
                }
            }
            .font(.system(size: 11.5, weight: tab == tag ? .semibold : .regular))
            .foregroundStyle(tab == tag ? Palette.ink : Palette.ink2)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background {
                if tab == tag {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Palette.raised)
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == tag ? .isSelected : [])
    }

    /// Tažením za levou hranu se panelu mění šířka. Pruh je schválně širší než čára, aby
    /// se do něj dalo trefit.
    private var resizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(.rect)
            // `pointerStyle` místo ručního `NSCursor.push()`/`pop()`: když view zmizí uprostřed
            // hoveru, druhá půlka páru se nikdy nezavolá a v aplikaci zůstane cizí kurzor.
            .pointerStyle(.frameResize(position: .leading))
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        let start = widthAtDragStart ?? clampedWidth
                        widthAtDragStart = start
                        width = clamp(start - drag.translation.width)
                    }
                    .onEnded { _ in widthAtDragStart = nil }
            )
    }

    // MARK: - Obsah

    /// Vybraný tab se **přeloží** podle toho, čí PR to je (#333) — volba je jedna pro celé okno,
    /// takže po přepnutí z cizího PR na vlastní ukazuje na segment, který tady není.
    @ViewBuilder private var content: some View {
        switch Policy.reviewPanelTab(tab, for: ownership) {
        case .findings: findingsTab
        case .draft:
            DraftPanel(
                pullRequest: pullRequest,
                draft: draft,
                verdict: draftVerdict,
                isStale: isDraftStale,
                isOwnPullRequest: isOwnPullRequest,
                unavailable: draftUnavailable,
                actions: draftActions,
                jump: jumpToComment
            )
        case .agentPrompt:
            // `nil` znamená „cizí PR“, a tam se tenhle segment nekreslí (`Policy.reviewPanelTabs`),
            // takže sem to nedojde. Je to rozbalení optionalu, ne stav k zobrazení — kdyby se to
            // rozešlo, je chyba v tom, kdo panel skládá, ne prázdno k vysvětlení.
            if let agentPrompt {
                AgentPromptPanel(
                    prompt: agentPrompt,
                    conversation: conversation,
                    toggle: agentPromptActions.toggle,
                    isEnabled: agentPromptActions.isEnabled,
                    compose: agentPromptActions.compose,
                    // Draft na vlastním PR se od #333 nezakládá, ale co tam zbylo z dřívějška,
                    // musí zůstat vidět a smazatelné.
                    leftoverDraft: draft,
                    discardDraft: draftActions.discard,
                    report: handoff,
                    composeFresh: agentPromptActions.composeFresh,
                    runReview: agentPromptActions.runReview,
                    isReviewing: isRunning
                )
            }
        }
    }

    @ViewBuilder private var findingsTab: some View {
        if let reason = emptyReason {
            // Tatáž vysvětlivka jako v tabu `Nálezy` (#242) — dvě různé věty o tom, proč je
            // prázdno, by se dřív nebo později rozešly a jedna z nich by tvrdila „čisto“.
            FindingsEmptyView(reason: reason)
        } else {
            VStack(spacing: 0) {
                // Věta **nad** kartami a mimo `ScrollView` (#392): tvrzení o tom, ke kterému kódu
                // nálezy patří, nesmí odscrollovat pryč od nálezů, o kterých mluví.
                FindingsHeadNoticeView(notice: headNotice)
                cards
            }
        }
    }

    /// Karty, ne tabulka (#175).
    ///
    /// Tabulka se při šířkách z #60 nedala rozumně nasázet: kategorie, místo a shrnutí se
    /// perou o místo, odmítnutí (#113) muselo skončit jako odznak u kategorie a delší nález
    /// se vešel na dva řádky bez možnosti rozbalit. Karta má místa dost a **závažnost nese
    /// proužek na hraně**, takže se čte dřív než text — jako v řádku fronty (#172).
    ///
    /// **Řazení podle sloupců se sem nevrátilo ani po #242**, kde tabulka vznikla v tabu přes celé
    /// okno: v panelu se sloupce pořád nemají kam vejít. Platí tady pořadí z `Policy.sorted`, tedy
    /// podle závažnosti — a kdo chce řadit, má na to tab.
    private var cards: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(rows) { row in
                    FindingCardView(
                        row: row,
                        isCurrent: current == FindingPlace(row.finding),
                        findingActions: findingActions,
                        editor: editor,
                        jump: { jump(row.finding) }
                    )
                }
            }
            .padding(10)
            // **Ztlumené, ne schované** (#392): u staršího commitu nálezy o kódu na obrazovce
            // nemluví, ale pořád platí — schovat je by znamenalo, že v `Commitech` panel nálezy
            // nemá, a to je zrovna ta ztráta, kterou #392 řešila. Hodnota je z návrhu (0,52).
            .opacity(headNotice.dimsFindings ? 0.52 : 1)
        }
        // **Rozměr se měří, nevyjednává** (#361): karty stojí ve `VStack`u pod větou o hlavě,
        // takže by mu ten `VStack` posílal průzkumné dotazy na pružnost skrz na `LazyVStack`.
        .fillingSlot()
    }

    // MARK: - Data

    /// Pořadí dává `Policy` — podle závažnosti, ne podle toho, co si kdo naklikal ve sloupci.
    private var rows: [FindingRow] {
        FindingRow.rows(
            of: findings,
            blocking: blockingCategories,
            dismissals: dismissals,
            rechecks: rechecks
        )
    }

    private var emptyReason: FindingsEmptyReason? {
        Policy.findingsEmptyReason(
            visible: findings,
            record: record,
            isRunning: isRunning,
            categories: blockingCategories
        )
    }

    /// Rozdělané review se hlásí **odznakem, ne počtem**: draft, ve kterém je jen vybraný
    /// verdikt, je plnohodnotný (čtvrtina vzorku z #63), takže „· 0“ by o něm lhalo.
    /// Zastaralý si přidá varování — banner uvnitř tabu není vidět, dokud se do něj neklikne.
    private var draftLabel: String {
        guard draft != nil else { return "Moje review" }
        return isDraftStale ? "Moje review ⚠︎" : "Moje review ●"
    }

    /// Počet položek u segmentu `Zadání`. `nil` u nuly i bez zadání — nula by tvrdila, že se
    /// spočítalo a vyšlo prázdno, a to má vysvětlit obsah tabu.
    private var agentPromptCount: Int? {
        guard let total = agentPrompt?.included.total, total > 0 else { return nil }
        return total
    }
}
