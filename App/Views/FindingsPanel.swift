import SwiftUI

/// Spodní panel pod diffem: přehled nálezů a (zatím prázdný) průběh běhu.
///
/// Je to **jediné místo pro nálezy bez `file:line`** — chybějící testy, poznámky
/// k architektuře. Právě kvůli nim nestačí bubliny u kódu.
///
/// Sbalený ukazuje jen to podstatné: návrh verdiktu, počet nálezů a stáří. Diff je to
/// hlavní, kvůli čemu je okno otevřené, takže panel si o místo musí říct.
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

    /// Výška si drží uživatel taháním a přežívá restart — kolik místa chce dát nálezům,
    /// ví jen on.
    @AppStorage("findingsPanelHeight") private var height = 220.0
    /// Sledovat konec časové osy. Předvolba pohledu, takže `UserDefaults`, ne store.
    @AppStorage("progressFollowsTail") private var followsTail = true
    /// Kde stojí kurzor procházení (#187). Karta na tom místě dostane rámeček, takže panel
    /// a diff ukazují **totéž** — bez toho by po skoku šipkou nebylo v seznamu poznat, kde jsem.
    var current: FindingPlace?

    /// Který tab je vidět. Drží ho detail PR, ne panel: přidání poznámky do těla review se
    /// z diffu musí umět přepnout na tab, do kterého ta poznámka spadla — jinak text zmizí
    /// někam, kde ho nikdo nehledá.
    @Binding var tab: Tab
    /// Výška na začátku tažení. Bez ní se posun načítá z každé události znovu a panel
    /// utíká pryč.
    @State private var heightAtDragStart: Double?
    @State private var isConfirmingClear = false
    @State private var isClearing = false
    @State private var clearFailure: String?

    /// Podlaha panelu. **Změřená, ne odhadnutá** (#69): obsah tabu `Moje review` má se
    /// zastaralým draftem přirozenou výšku 198 pt (banner, verdikt, dva editory) a bez banneru
    /// 161 pt — offscreen render `DraftPanel`u. Se starou podlahou 120 pt se proto scrolloval,
    /// i když byl panel vytažený, a scrollbar v pruhu pod diffem vypadá jako rozbité rozvržení.
    ///
    /// Vejde se tím i tabulka nálezů (šest řádků) a časová osa. Scroll uvnitř draftu zůstává jako
    /// pojistka pro úzké okno, kde se banner zalomí na víc řádků.
    private static let minimumHeight = 200.0
    private static let maximumHeight = 600.0

    /// Uložená výška se ořezává **při použití**, ne jen při tažení: v `UserDefaults` může
    /// být cokoli (ruční editace, jiný rozsah ze starší verze) a `frame(height:)` se
    /// zápornou hodnotou rozhodí celý panel.
    private var clampedHeight: Double { clamp(height) }

    private func clamp(_ value: Double) -> Double {
        min(max(Self.minimumHeight, value), Self.maximumHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            bar
            if isExpanded {
                Divider()
                // **Strop, ne pevná výška.** `frame(height:)` je nesmlouvavá: v nízkém okně
                // se panel nezmenší, přeteče — a co se nevejde, se odřízne spodní hranou
                // okna, takže poslední řádek tabulky je půlka. S `maxHeight` si vezme jen
                // to, co je, a tabulka uvnitř scrolluje. Podlaha je tam proto, aby zůstal
                // aspoň řádek: panel zmáčknutý na deset bodů je horší než sbalený.
                content.frame(minHeight: Self.minimumHeight, maxHeight: clampedHeight)
            }
        }
        .background(.bar)
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

    // MARK: - Lišta

    private var bar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            tabs
            Spacer()
            if tab == .progress {
                Toggle("Sledovat konec", isOn: $followsTail)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .help("Posouvat osu na nejnovější událost")
            }
            if let finishedAt = record?.finishedAt {
                Text(finishedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            clearButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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

    private var tabs: some View {
        Picker("", selection: $tab) {
            Text(verbatim: countText).tag(Tab.findings)
            Text("Průběh").tag(Tab.progress)
            Text(verbatim: draftText).tag(Tab.draft)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        // Rozbalený panel bez obsahu vypadá jako chyba — přepnutí tabu ho proto otevře.
        .onChange(of: tab) { _, _ in isExpanded = true }
    }

    /// Tažením za horní hranu se panelu mění výška. Pruh je schválně vyšší než čára, aby
    /// se do něj dalo trefit.
    private var resizeHandle: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(height: 8)
                    .contentShape(.rect)
                    // `pointerStyle` místo ručního `NSCursor.push()`/`pop()`: když view
                    // zmizí uprostřed hoveru, druhá půlka páru se nikdy nezavolá a
                    // v aplikaci zůstane cizí kurzor.
                    .pointerStyle(.frameResize(position: .top))
                    .gesture(
                        DragGesture()
                            .onChanged { drag in
                                let start = heightAtDragStart ?? clampedHeight
                                heightAtDragStart = start
                                isExpanded = true
                                height = clamp(start - drag.translation.height)
                            }
                            .onEnded { _ in heightAtDragStart = nil }
                    )
            }
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

    private var countText: String {
        findings.isEmpty ? "Nálezy" : "Nálezy · \(findings.count)"
    }

    /// Rozdělané review se hlásí **odznakem, ne počtem**: draft, ve kterém je jen vybraný
    /// verdikt, je plnohodnotný (čtvrtina vzorku z #63), takže „· 0“ by o něm lhalo.
    /// Zastaralý si přidá varování — banner uvnitř tabu není vidět, dokud se do něj neklikne.
    private var draftText: String {
        guard draft != nil else { return "Moje review" }
        return isDraftStale ? "Moje review ⚠︎" : "Moje review ●"
    }

}
