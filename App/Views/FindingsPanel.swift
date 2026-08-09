import SwiftUI

/// Panel napravo od diffu: nálezy, rozdělané review a průběh běhu.
///
/// Je to **jediné místo pro nálezy bez `file:line`** — chybějící testy, poznámky
/// k architektuře. Právě kvůli nim nestačí bubliny u kódu.
///
/// **Napravo, ne dole** (#182). Do té doby si bral výšku, které je v diffu nejmíň: kód je
/// dlouhý a úzký, takže dole se pere o to jediné, čeho je málo. Napravo bere šířku, které je
/// v okně přes celou obrazovku dost — spočítané v zadání #182: v pohledu pod sebou se i na 14"
/// vejde 126 znaků na stranu, tedy slib „PHP na 120 znaků se vejde“ drží. V pohledu vedle sebe
/// ho neunese žádný displej pod 27"; složení sloupců v tom režimu řeší #188.
///
/// Složený je **proužek na hraně** s počtem nálezů, ne zmizelý panel: schovaná práce je práce,
/// o které nikdo neví.
struct FindingsPanel: View {
    /// `nil` při **prvním** běhu, než se uloží záznam — právě tehdy je průběh
    /// nejzajímavější, takže se na něj nesmí čekat.
    let record: ReviewRecord?
    /// Zahodí uložené nálezy. `nil` = není co zahodit, tlačítko se nekreslí.
    var clear: (() async throws -> Void)?
    @Binding var isExpanded: Bool
    /// Odskok do diffu na místo nálezu.
    let jump: (Finding) -> Void
    /// Co reviewery dělaly. Prázdné, dokud se nic nespustilo.
    /// Nálezy k zobrazení — po filtru chipů, takže ne nutně všechny ze záznamu.
    var findings: [Finding] = []
    /// Jak jsem nálezy posoudil (#113). Celá mapa ze záznamu — řádek si z ní vezme to své.
    var dismissals: [FindingKey: FindingDismissal] = [:]
    /// Odmítnutí a vrácení nálezu. Kontextové menu se bez toho nekreslí.
    var findingActions: FindingActions?
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    var timelines: [ReviewerTimeline] = []
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
    /// Proč se do draftu nedá psát. `nil` = dá se.
    var draftUnavailable: String?
    var draftActions = DraftActions()
    var jumpToComment: (ReviewDraftComment) -> Void = { _ in }

    enum Tab: Hashable {
        case findings
        case progress
        /// Rozdělané review — tělo, verdikt a řádkové komentáře.
        case draft
    }

    /// Šířku si drží uživatel taháním a přežívá restart — kolik místa chce dát nálezům,
    /// ví jen on. **Vlastní klíč** (#182), ne přejmenovaná výška: uložených 220 by jako šířka
    /// dalo panel užší, než v jakém se dá nález přečíst.
    @AppStorage("findingsPanelWidth") private var width = FindingsPanel.defaultWidth
    /// Sledovat konec časové osy. Předvolba pohledu, takže `UserDefaults`, ne store.
    @AppStorage("progressFollowsTail") private var followsTail = true
    /// Kde stojí kurzor procházení (#187). Karta na tom místě dostane rámeček, takže panel
    /// a diff ukazují **totéž** — bez toho by po skoku šipkou nebylo v seznamu poznat, kde jsem.
    var current: FindingPlace?

    /// Který tab je vidět. Drží ho detail PR, ne panel: přidání poznámky do těla review se
    /// z diffu musí umět přepnout na tab, do kterého ta poznámka spadla — jinak text zmizí
    /// někam, kde ho nikdo nehledá.
    @Binding var tab: Tab
    /// Šířka na začátku tažení. Bez ní se posun načítá z každé události znovu a panel
    /// utíká pryč.
    @State private var widthAtDragStart: Double?
    @State private var isConfirmingClear = false
    @State private var isClearing = false
    @State private var clearFailure: String?

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

    private func clamp(_ value: Double) -> Double {
        min(max(Self.minimumWidth, value), Self.maximumWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isExpanded {
                resizeHandle
                VStack(spacing: 0) {
                    header
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
        // `presenting:` podá text nepovinný, takže v těle není `?? ""` — default, který se
        // nikdy nepoužije, čte příště jako možnost prázdné hlášky.
        .alert(
            "Nálezy se nepodařilo zahodit",
            isPresented: .init(get: { clearFailure != nil }, set: { if !$0 { clearFailure = nil } }),
            presenting: clearFailure
        ) { _ in
            Button("Zavřít", role: .cancel) { clearFailure = nil }
        } message: { detail in
            Text(verbatim: detail)
        }
    }

    // MARK: - Hlavička a proužek

    /// Řádek nad segmenty: sbalení, stáří výsledku a zahození nálezů.
    ///
    /// Návrh v sekci 02 hlavičku nekreslí — jenže tyhle tři věci v aplikaci jsou a někam patří.
    /// Do segmentů ne (přepínají obsah), do obsahu taky ne (platí pro všechny tři). Sazba je
    /// z `.side > header` v návrhu, který na to místo v CSS pamatuje.
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
            .help("Složit panel (⌘2)")
            .accessibilityLabel("Složit panel")

            if tab == .progress {
                Toggle("Sledovat konec", isOn: $followsTail)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Posouvat osu na nejnovější událost")
            }
            Spacer(minLength: 4)
            if let finishedAt = record?.finishedAt {
                Text(finishedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
            }
            clearButton
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    /// Složený panel — proužek na hraně okna, ne zmizelý panel.
    ///
    /// Nese **počet nálezů**, takže je z něj poznat, že je co číst; červený je, když mezi nimi
    /// něco blokuje. Bez toho čísla je složení tichá ztráta práce, kterou reviewer odvedl.
    private var collapsedStrip: some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { isExpanded = true }
        } label: {
            VStack(spacing: 9) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink3)
                if !findings.isEmpty {
                    Text(verbatim: "\(findings.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(hasBlocking ? Color.red : Palette.ink2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            (hasBlocking ? Color.red.opacity(0.15) : Palette.raised),
                            in: .rect(cornerRadius: 4)
                        )
                }
                Text(verbatim: "nálezy · review")
                    .font(.system(size: 10.5))
                    .tracking(0.6)
                    .foregroundStyle(Palette.ink3)
                    // Svislý text jako v návrhu (`writing-mode: vertical-rl`). Otočením, protože
                    // svislou sazbu SwiftUI neumí — a proužek je na popisek naležato moc úzký.
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: Self.collapsedWidth)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .frame(width: Self.collapsedWidth, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Rozložit panel nálezů (⌘2)")
        .accessibilityLabel("Rozložit panel nálezů")
    }

    private var hasBlocking: Bool {
        findings.contains { Policy.isBlocking($0, categories: blockingCategories) }
    }

    /// Zahození uložených nálezů.
    ///
    /// Vpravo, **ne vedle tabů**, jak psalo zadání #81: mazací tlačítko těsně u přepínače,
    /// do kterého se kliká pořád, si o překlep říká. Za běhu je zakázané — doběhlý skill by
    /// se zapsal do právě vyčištěného záznamu.
    @ViewBuilder private var clearButton: some View {
        if let clear {
            Button("Zahodit nálezy", systemImage: "trash") {
                isConfirmingClear = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.callout)
            .disabled(isRunning || isClearing)
            .help(isRunning
                ? "Nejdřív nech review doběhnout, nebo ho zruš"
                : "Zahodit uložené nálezy tohohle commitu a pustit review znovu")
            // Potvrzení schválně: vrátit se k nálezům jde jedině novým během, a ten stojí
            // session. Není to nevratné zdánlivě, je to nevratné doopravdy.
            .confirmationDialog(
                "Zahodit uložené nálezy?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Zahodit", role: .destructive) { runClear(clear) }
                Button("Zpět", role: .cancel) {}
            } message: {
                Text("Zpátky je dostaneš jedině novým review, které stojí session. Historie starších commitů zůstane.")
            }
        }
    }

    private func runClear(_ clear: @escaping () async throws -> Void) {
        isClearing = true
        Task {
            defer { isClearing = false }
            do {
                try await clear()
            } catch {
                // Nesmazaný záznam se nesmí tvářit jako smazaný — vrátil by se po restartu
                // a nikdo by nevěděl proč.
                clearFailure = error.localizedDescription
            }
        }
    }

    /// Segmenty z návrhu, ne `Picker(.segmented)`: systémový přepínač si bere výšku
    /// i šířku podle textu a v panelu 300 bodů se `Nálezy · 12 / Průběh / Moje review ●`
    /// nevejde. Sazba je z `.seg` — poloměr 6, 11,5 bodu, aktivní na vyvýšené ploše.
    private var segments: some View {
        HStack(spacing: 2) {
            segment("Nálezy", count: findings.isEmpty ? nil : findings.count, tag: .findings)
            segment(draftLabel, tag: .draft)
            segment("Průběh", tag: .progress)
        }
        .padding(.horizontal, 11)
        .padding(.top, 9)
        .padding(.bottom, 4)
    }

    private func segment(_ title: String, count: Int? = nil, tag: Tab) -> some View {
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

    @ViewBuilder private var content: some View {
        switch tab {
        case .findings: findingsTab
        case .progress: progress
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
        }
    }

    @ViewBuilder private var findingsTab: some View {
        if findings.isEmpty {
            emptyExplanation
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            cards
        }
    }

    /// Karty, ne tabulka (#175).
    ///
    /// Tabulka se při šířkách z #60 nedala rozumně nasázet: kategorie, místo a shrnutí se
    /// perou o místo, odmítnutí (#113) muselo skončit jako odznak u kategorie a delší nález
    /// se vešel na dva řádky bez možnosti rozbalit. Karta má místa dost a **závažnost nese
    /// proužek na hraně**, takže se čte dřív než text — jako v řádku fronty (#172).
    ///
    /// **Řazení podle sloupců se tím ztrácí, a je to vědomé.** Nálezů je typicky pod dvacet
    /// a `Policy.sorted` je řadí podle závažnosti, tedy tak, jak se mají číst; zúžit je jde
    /// filtrem reviewerů a přepínačem `jen blokující` v liště nad diffem (#187). Kdyby se
    /// ukázalo, že řazení chybí, vrátí se jako druhý pohled — proto zůstává `FindingRow`
    /// se svými `Comparable` klíči, ze kterých tabulka žila.
    private var cards: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(rows) { row in
                    FindingCardView(
                        row: row,
                        isCurrent: current == FindingPlace(row.finding),
                        findingActions: findingActions,
                        jump: { jump(row.finding) }
                    )
                }
            }
            .padding(10)
        }
    }

    private var progress: some View {
        ReviewTimelineView(timelines: timelines, followsTail: followsTail)
    }

    /// Prázdná tabulka neznamená sama o sobě čisté review — reviewer taky nemusel nálezy
    /// nahlásit vůbec nebo se je nepodařilo přečíst. Vysvětlení se bere ze stavu, který
    /// z toho počítá `Policy`, ne z vlastní věty tady.
    @ViewBuilder private var emptyExplanation: some View {
        // Schované nálezy nejsou žádné nálezy. Bez téhle věty vypadá zapnutý filtr jako
        // čisté review — tedy jako schválený PR s neohlášenou chybou.
        if let record, !record.findings.isEmpty {
            Text("Nálezy jsou schované filtrem reviewerů.").foregroundStyle(.secondary)
        } else if let record {
            explanation(of: record)
        } else if isRunning {
            Text("Review běží. Co se právě děje, je v tabu Průběh.").foregroundStyle(.secondary)
        } else {
            Text("Nálezy k tomuhle běhu nejsou.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func explanation(of record: ReviewRecord) -> some View {
        switch Policy.reviewState(for: record, categories: blockingCategories) {
        case .clean:
            Text("Review doběhlo a nic nenašlo.").foregroundStyle(.secondary)
        case .failed(let detail), .checkoutFailed(let detail):
            Text(detail).foregroundStyle(.orange)
        default:
            Text("Nálezy k tomuhle běhu nejsou.").foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    /// Bez řazení podle sloupce platí pořadí z `Policy` — tabulka nemá vlastní představu
    /// o tom, co patří nahoru, včetně toho, že odmítnuté jdou naspod.
    /// Pořadí dává `Policy` — podle závažnosti, ne podle toho, co si kdo naklikal ve sloupci.
    private var rows: [FindingRow] {
        FindingRow.rows(of: findings, blocking: blockingCategories, dismissals: dismissals)
    }

    /// Rozdělané review se hlásí **odznakem, ne počtem**: draft, ve kterém je jen vybraný
    /// verdikt, je plnohodnotný (čtvrtina vzorku z #63), takže „· 0“ by o něm lhalo.
    /// Zastaralý si přidá varování — banner uvnitř tabu není vidět, dokud se do něj neklikne.
    private var draftLabel: String {
        guard draft != nil else { return "Moje review" }
        return isDraftStale ? "Moje review ⚠︎" : "Moje review ●"
    }

}
