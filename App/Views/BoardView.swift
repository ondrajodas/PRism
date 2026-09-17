import SwiftUI

/// Domácí záložka (#515) — **deska pruhů podle mého tahu**.
///
/// Nahradila `DashboardView` z #181. Ten odpovídal na „kolik toho je“ pěti kartami a dvěma
/// bloky front podle autora (#331); tenhle odpovídá na **„co udělám teď“** šesti pruhy podle
/// toho, čí je tah. Karty odešly celé — čísla, která nesly, zůstávají v railu a ve stavovém
/// řádku, tedy tam, kde jsou vidět ze všech obrazovek.
///
/// **Rozhodování je v `Policy`, tady se kreslí.** Do kterého pruhu PR patří, co je na akci nad
/// pruhem, kolik řádků se z pruhu nakreslí a jak zní věta pod pozdravem — všechno vydá
/// `Policy.board(…)` a spol. Rozměry a mezery jsou z návrhu (sekce 45) doslova; kdo je mění,
/// mění návrh.
struct BoardView: View {
    @Bindable var store: AppStore
    /// Otevře PR jako záložku — kliknutí do pruhu je tu hlavní pohyb.
    let open: (PRIdentifier) -> Void

    /// Ptá se potvrzení na hromadné spuštění review.
    ///
    /// **Jediná akce desky, která z jednoho kliknutí utratí víc než jednu session** — proto se
    /// u ní zastavíme, a proto jen u ní (`LaneAction.needsConfirmation`). Otevřít záložky nic
    /// nestojí a jde to vzít zpátky.
    @State private var isConfirmingBulkRun = false

    /// Pruhy, které si člověk rozbalil nad strop (#515).
    ///
    /// **Klíčované pruhem, ne jedním `Bool`em**: rozbalit `Čeká na ostatní` neznamená rozbalit
    /// `Rozhodnout`. Je to stav pohledu v jednom běhu, takže se nikam neukládá — tatáž úvaha
    /// jako u sledování konce ve výpisu kroků (#325).
    ///
    /// **Značka po skrytém pruhu tady zůstane, a je to vědomé.** Od proklikání #515 se prázdný
    /// pruh nekreslí, takže pruh, který se vyprázdnil a zase naplnil, se vrátí **rozbalený**.
    /// Uklízet to jde jedině zápisem do `@State` při kresbě, a to je zakázaná třída (#503);
    /// cena je jeden rozbalený pruh navíc, kdežto zápis při kresbě je průchod tělem na každý tik.
    @State private var expandedLanes: Set<WorkLane> = []

    /// Patka bloku pod kurzorem, klíčovaná sekcí, do které vede (#371).
    ///
    /// Od #515 je taková patka **jedna** (blok `Dění`), ale klíč zůstává: pojmenovaný
    /// `isFooterHovered` by u druhé patky rozsvítil obě, a druhá patka je otázka jednoho bloku
    /// v pravém sloupci.
    @State private var hoveredFooter: RailSection?

    /// Rozbalovací patka pruhu pod kurzorem (#515). Vlastní stav, protože patka pruhu **nikam
    /// nevede** — jen rozbaluje na místě, takže s patkami bloků nesdílí ani cíl, ani klíč.
    @State private var hoveredLane: WorkLane?

    var body: some View {
        // **Jednou za překreslení.** `Policy.board` projde všechny záznamy, u vlastních PR se
        // ptá na předání i na merge a skládá blok `Dění`; getter volaný z každého pruhu zvlášť
        // by tu práci udělal šestkrát za sebou.
        let board = store.board
        // **Taky jednou za překreslení**, ze stejného důvodu jako `board`: mluví o něm věta pod
        // pozdravem i blok v pravém sloupci, a getter volaný z obou by ten seznam prošel dvakrát.
        let snoozed = store.snoozedPullRequests
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                head(board, snoozed: snoozed.count)
                // Brief (#516) — **nad pruhy a pod pozdravem**, jak ho kreslí návrh. Jestli se
                // kreslí vůbec, rozhoduje `Policy.briefBlock`: s vypnutou bránou vrací `nil`
                // a domov vypadá jako do #516.
                brief
                columns(board, snoozed: snoozed)
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .background(Palette.surface)
        .confirmationDialog(bulkRunQuestion, isPresented: $isConfirmingBulkRun) {
            Button("Spustit") { store.startReviewsForNotReviewed() }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Každé z nich utratí vlastní session Claude Code. Souběžně jich poběží \(store.configuration.global.maxConcurrentReviews), zbytek počká ve frontě.")
        }
    }

    // MARK: - Hlavička

    private func head(_ board: Board, snoozed: Int) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: greeting)
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.5)
                Text(verbatim: summarySentence(board, snoozed: snoozed))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 8)
            tick
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ink3)
        }
    }

    /// Blok `brief` (#516). Tři věty o stavu aplikace, které složila session **bez nástrojů**.
    ///
    /// **Pozdrav zůstává nad ním.** Zákres z decku má obojí: pozdrav s větou o pruzích odpovídá na
    /// „jak to stojí“ z dat, která aplikace má jistě, kdežto brief je text od modelu — a ten se
    /// smí nepovést. Kdyby pozdrav nahradil, byl by vypnutý nebo spadlý brief dírou nad deskou.
    @ViewBuilder private var brief: some View {
        if let block = Policy.briefBlock(mode: store.configuration.global.brief, state: store.briefState) {
            BriefBlockView(
                block: block,
                write: { store.writeBrief() },
                // **Tatáž cesta jako `prism://` a `Odkaz` v paletě** (#531): PR ze zdrojů se
                // otevře beze změny, PR, který mezitím z fronty vypadl, jako záložka ke čtení.
                open: { store.openPullRequest($0) }
            )
        }
    }

    /// Pozdrav podle denní doby. Je to jediné místo v aplikaci, které mluví na člověka —
    /// domov se otevírá jako první věc a „Deska“ nad prázdnou obrazovkou zní jako chybová
    /// hláška.
    ///
    /// **Zůstává i vedle briefu** (#516), a je to rozhodnutí: pozdrav a věta pod ním mluví
    /// z dat, která aplikace má jistě, kdežto brief je text od modelu a smí se nepovést. Blok
    /// s briefem visí **pod** nimi.
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<10: "Dobré ráno."
        case 10..<18: "Dobrý den."
        default: "Dobrý večer."
        }
    }

    /// Věta pod pozdravem — `8 věcí na tahu · 4 čekají na ostatní · 1 se dá mergnout`.
    ///
    /// **Skládá ji `Policy.boardSentence`**, protože mluví o pruzích a ty skládá tatáž funkce.
    /// Do #515 to byly dvě věty (o frontě a o vlastních PR), tedy dva počty podle **autora**;
    /// od #515 je počet **na tahu**, což je tatáž osa jako celá obrazovka pod tím.
    ///
    /// **Nenačtená fronta větu nedostane.** „Načítám frontu…“ je stav, ve kterém se o práci nedá
    /// tvrdit nic — a nula nad nenačtenými daty je ta nebezpečná strana.
    private func summarySentence(_ board: Board, snoozed: Int) -> String {
        guard store.lastSuccess != nil else { return "Načítám frontu…" }
        // **Odložené se připisují** (#512): na desce nejsou v žádném pruhu, takže by o nich jinak
        // domov neřekl nic. Rozbalit se dají v bloku `Odložené` v pravém sloupci — do opravy #512
        // tady stálo číslo, ke kterému z téhle obrazovky nevedla cesta.
        //
        // **Počet chodí shora** (`snoozedPullRequests`, tedy před filtrem — na tomtéž vstupu stojí
        // pruhy): filtr je věc fronty, ne desky. Kdyby si ho tahle funkce brala ze storu sama,
        // prošel by se ten seznam podruhé kvůli jednomu číslu.
        return Policy.boardSentence(board, snoozed: snoozed)
    }

    /// Kdy se to naposledy načetlo a kolik zbývá do příštího tiku — `poslední tik 09:41 ·
    /// za 43s znovu`.
    ///
    /// **Odpočet, ne absolutní čas** (#237). Vteřiny si odtiká `DashboardCountdown` sám ve svém
    /// `TimelineView`, a tělo desky se u toho nepřepočítává — proto se text skládá ze **dvou
    /// kusů**: ten druhý musí zůstat samostatné view.
    @ViewBuilder private var tick: some View {
        switch DashboardTick(
            lastSuccess: store.lastSuccess,
            nextPoll: store.nextPoll,
            isRefreshing: store.isRefreshing,
            now: .now
        ) {
        case .never:
            Text("zatím se nenačetlo")
        case .idle(let last):
            Text(verbatim: "poslední tik \(clock(last))")
        case .countdown(let last, let deadline):
            HStack(spacing: 0) {
                Text(verbatim: "poslední tik \(clock(last)) · ")
                DashboardCountdown(deadline: deadline)
            }
        case .polling(let last):
            Text(verbatim: last.map { "poslední tik \(clock($0)) · ptám se…" } ?? "ptám se…")
        }
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Dva sloupce

    private func columns(_ board: Board, snoozed: [PullRequestSummary]) -> some View {
        // Poměr z návrhu (`1.45fr 1fr`), ne pevná šířka: pravý sloupec drží dění a útratu, a ty
        // se v proužku číst nedají.
        ProportionalColumns(ratios: [1.45, 1], spacing: 16) {
            // **Jen neprázdné pruhy** (`Board.visibleLanes`, z proklikání #515): prázdný rámeček
            // s nulou nese jedinou informaci a šest takových je pět šestin obrazovky za odpověď,
            // o kterou se nikdo neptal. Mezera 12 je z návrhu (sekce 45), tedy jiná než 16 mezi
            // sloupci.
            VStack(spacing: 12) {
                if board.isEverythingDone {
                    everythingDone
                } else {
                    ForEach(board.visibleLanes) { lane in
                        laneBlock(lane)
                    }
                }
            }
            VStack(spacing: 12) {
                // **Nahoře, ne pod útratou** (#512, oprava po proklikání): věta pod pozdravem
                // hlásí `· 2 odložené` a tenhle blok je jediné místo domova, kde se to číslo dá
                // rozbalit — má tedy být v jedné výšce s ní, ne na konci sloupce. Když odložené
                // nic není, nekreslí se a sloupec vypadá jako dřív.
                snoozedBlock(snoozed)
                activity(board.activity)
                spendBlock
            }
        }
    }

    /// Deska, na které není ani jeden pruh.
    ///
    /// **Vlastní blok, ne prázdná plocha**: prázdno by se čtlo jako porucha, přitom je to
    /// nejlepší možný stav. Věty skládá `Policy.boardEmpty(isLoaded:)` — včetně toho, že
    /// **nenačtená fronta není vyřízená fronta**.
    private var everythingDone: some View {
        let empty = Policy.boardEmpty(isLoaded: store.lastSuccess != nil)
        return block(empty.title, action: { EmptyView() }) {
            Text(verbatim: empty.explanation)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
        }
    }

    // MARK: - Pruh

    /// Jeden pruh: hlavička s počtem a akcí, pod ní řádky, nebo věta.
    ///
    /// **Ztlumený je celý tichý pruh**, ne jen jeho popisek — `opacity` z návrhu
    /// (`.brd-quiet { opacity: 0.7 }`) platí i na počet, kapsli a řádky, a to je právě to
    /// chtěné: je to pruh, ve kterém se nic nedělá.
    @ViewBuilder private func laneBlock(_ lane: Board.Lane) -> some View {
        block(lane.lane.title, count: lane.count, action: { laneHeaderAction(lane) }) {
            laneRows(lane)
        }
        .opacity(lane.lane.isQuiet ? 0.7 : 1)
    }

    /// Akce nebo popisek vpravo v hlavičce pruhu.
    ///
    /// **Popisek u tichého pruhu je `Text`, ne zašedlé tlačítko**: v tichém pruhu se nedělá nic
    /// nikdy, takže zašedlé tlačítko by tvrdilo „tady se to dělá, jen teď ne“ — tatáž úvaha jako
    /// u akcí na cizím PR (`Policy.MetadataEditing.absent`).
    @ViewBuilder private func laneHeaderAction(_ lane: Board.Lane) -> some View {
        if let title = lane.action.title {
            Button { run(lane) } label: {
                HStack(spacing: 7) {
                    Text(verbatim: title)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    if let shortcut = lane.action.shortcut {
                        Text(verbatim: Policy.windowShortcut(shortcut).display)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 4)
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Palette.line, lineWidth: 1)
                            }
                            .opacity(0.7)
                    }
                }
            }
            .buttonStyle(AccentLinkButtonStyle())
            // Zkratka z katalogu (#441), a `nil` u akce, která žádnou nemá. Zakázané tlačítko
            // klávesu nebere, takže `⏎` nad otevřenou paletou propadne dál.
            .windowShortcut(lane.action.shortcut)
            .disabled(!isEnabled(lane))
            .help(help(for: lane))
        } else if let note = lane.action.note {
            Text(verbatim: note)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.ink3)
                .lineLimit(1)
        }
    }

    /// Smí se akce pruhu zmáčknout?
    ///
    /// Jediné, co se u ní **mění**, je `⏎` nad otevřenou paletou ⌘K (`Policy.canOpenFirstOnBoard`)
    /// — zakázané tlačítko klávesu nebere, takže propadne dál. Ostatní akce prázdný pruh nemá
    /// vůbec (`LaneAction.none`), takže se zakazovat nemají čím.
    private func isEnabled(_ lane: Board.Lane) -> Bool {
        guard case .openFirst = lane.action else { return true }
        return Policy.canOpenFirstOnBoard(count: lane.count, isPaletteOpen: store.isPaletteOpen)
    }

    /// Nápověda u akce — **co se stane**, ne jak se to jmenuje. Zkratka se do ní přidává
    /// z katalogu (`Policy.shortcutHelp`), nikdy se neopisuje vedle klávesy (#441).
    private func help(for lane: Board.Lane) -> String {
        let text = switch lane.action {
        case .openFirst: "Otevře \(lane.rows.first.map { "\($0.pullRequest.repo.name)#\($0.pullRequest.number)" } ?? "první pull request v pruhu")"
        case .runReviews(let count): "Pustí review na \(Plural.czech(count, one: "pull requestu", few: "pull requestech", many: "pull requestech")) z pruhu"
        case .buildPrompts(let count): "Otevře \(Plural.czech(count, one: "záložku", few: "záložky", many: "záložek")) s panelem Zadání"
        case .finishDraft: "Otevře PR s nejstarším rozdělaným review"
        case .quiet, .none: ""
        }
        guard let shortcut = lane.action.shortcut else { return text }
        return Policy.shortcutHelp(text, shortcut)
    }

    /// Co akce pruhu doopravdy udělá.
    ///
    /// **Řádky bere z pruhu, ne ze storu podruhé.** `Pustit review` je jediná výjimka a je
    /// vědomá: pouští `startReviewsForNotReviewed()`, tedy tu množinu, kterou store spouští
    /// odjakživa a která čte **jen cizí PR** (#332) — kdyby si deska skládala vlastní seznam,
    /// vznikla by druhá cesta, jak review spustit, a #332 by na ní neplatilo.
    private func run(_ lane: Board.Lane) {
        switch lane.action {
        case .openFirst, .finishDraft:
            if let first = lane.rows.first { open(first.id) }
        case .runReviews:
            // **O potvrzení rozhoduje `LaneAction.needsConfirmation`, ne tenhle switch.** Kdyby
            // si to view rozhodovalo samo, dala by se hromadná akce přidat bez potvrzení a nic by
            // to nehlásilo; takhle je pravidlo na jednom místě a testuje se výčtem.
            if lane.action.needsConfirmation {
                isConfirmingBulkRun = true
            } else {
                store.startReviewsForNotReviewed()
            }
        case .buildPrompts:
            // Panel `Zadání` se skládá v záložce toho PR (`AppStore.openAgentPrompt`), ne
            // v sheetu — proto se otevře záložka na každý PR pruhu. Návrh mluví o „dvou sheetech
            // za sebou“; sheet, ve kterém se prompt skládá, aplikace nemá, viz záznam rozhodnutí.
            for entry in lane.rows { store.openAgentPrompt(in: entry.id) }
        case .quiet, .none:
            break
        }
    }

    /// Řádky pruhu a pod nimi patka, když se pruh do stropu nevešel.
    ///
    /// **Prázdná větev tu není, a je to důsledek skrývání** (z proklikání #515): kreslí se jedině
    /// `Board.visibleLanes`, takže sem prázdný pruh nedojde. Věta na prázdný pruh proto odešla
    /// i z `WorkLane` — text, který se nemá kde ukázat, je mrtvá váha.
    ///
    /// **`LazyVStack` sem nepatří** (#469): strop je z `Policy`, ne odhad, takže i rozbalený
    /// pruh je pevný seznam. Neomezenost seznamu není důvod ten vzor snést — a tady ani
    /// neomezený není.
    private func laneRows(_ lane: Board.Lane) -> some View {
        let slice = Policy.laneSlice(
            lane.rows,
            of: lane.lane,
            expanded: expandedLanes.contains(lane.lane)
        )
        return VStack(spacing: 0) {
            ForEach(slice.rows) { entry in
                row(entry)
                if entry.id != slice.rows.last?.id { separator }
            }
            // **Podmínka je nad plným pruhem, ne nad řezem.** `slice.hidden` je v rozbaleném
            // stavu nula, takže by patka po rozbalení zmizela — a kdyby se ptala jen na
            // `expanded`, zůstala by tam i po tiku, který pruh zmenšil pod strop, tedy jako
            // tlačítko, po kterém se nic nestane.
            if lane.rows.count > Policy.laneRowLimit(lane.lane) {
                // **Čára je tady, a jedna** (#371): patka svou vlastní horní linku nemá,
                // protože by se sečetla s tou pod posledním řádkem.
                separator
                laneFooter(lane.lane, hidden: slice.hidden)
            }
        }
    }

    /// Jeden řádek pruhu — **týž `PullRequestRow` jako v seznamu** (#172), ne třetí podoba.
    ///
    /// Čí PR to je, se čte tady, ne v řádku: řádek store nemá. Vlastní PR má vpravo `Prompt →`
    /// a v hlavičce šipku v mintu, ať leží v kterémkoli pruhu.
    private func row(_ entry: QueueEntry) -> some View {
        let ownership = store.ownership(of: entry.pullRequest)
        // Kolik zbývá předat (#334) a co od minule přibylo (#335) — **jeden report**, tatáž
        // otázka jako u odznaku v railu a u pruhu `Předat agentovi`. Jen u vlastních PR: u cizího
        // řádku se nekreslí ani pilulka, ani novinky.
        let handoff = ownership == .mine ? store.handoffReport(for: entry.id) : .never
        return Button { open(entry.id) } label: {
            PullRequestRow(
                pullRequest: entry.pullRequest,
                reviewState: entry.state,
                hasDraft: entry.hasDraft,
                row: entry.row,
                // Mapa PR do mini pásu (#502) — **ze storu, jako ostatní odvozená data řádku**:
                // `QueueEntry` ji nenese schválně, protože pořadí v pruhu na ní nezávisí a fronta
                // se řadí podle závažnosti, ne podle toho, co je načtené.
                map: store.queueMap(for: entry.id),
                ownership: ownership,
                openPrompt: { store.openAgentPrompt(in: entry.id) },
                pending: handoff.pending,
                activity: handoff.activity,
                // Agent na vlastním PR (#511) — **jeden řádek, jedna podoba**, tedy i tady:
                // z pilulky se pozná, že nad PR běží něco, co jsem nespustil, nebo že v kopii repa
                // leží commit k přetlačení.
                agent: store.agentRowPill(for: entry.pullRequest),
                // Návrh review (#520) — **jeden řádek, jedna podoba**, tedy i tady: z pilulky se
                // pozná, že po reviewerech leží v panelu připravený návrh a kolik z něj zůstalo
                // sporné. Brána i razítko jsou za `AppStore.autoDraftPill`, takže s vypnutou
                // volbou se nekreslí nic.
                autoDraft: store.autoDraftPill(for: entry.id),
                // Odložit i na desce (#512, oprava po proklikání) — **jeden řádek, jedna podoba**.
                // Deska je první obrazovka, kterou vidím, a věta pod pozdravem o odložených mluví;
                // nabídka, která by tady chyběla, by z toho čísla udělala tvrzení bez cesty dál.
                snoozeAction: store.snoozeAction(for: entry.pullRequest),
                // Dráha smyčky (#509) — **jeden řádek, jedna podoba**, z téhož reportu jako
                // pilulka o pár řádků výš. Vlastnictví se ptá tady, jako u `handoff`u: deska míchá
                // cizí a vlastní PR v jednom pruhu, takže je to zrovna to místo, kde by se dráha
                // nad cizím řádkem počítala nejčastěji.
                loop: ownership == .mine
                    ? store.ownLoopRow(for: entry.pullRequest, handoff: handoff)
                    : nil,
                // Série (#513) — **pilulka ano, popisek ne**: skupinu drží `Policy.byUrgency`
                // uvnitř pořadí, ale pruhy jsou druhá osa a strop na pět řádků je třetí, takže
                // popisek nad skupinou by tvrdil o seznamu víc, než v něm je vidět.
                series: store.seriesPlacement(for: entry.id)
            )
            // Vlevo nic: proužek stavu má sedět na hraně pruhu, jak ho kreslí návrh.
            .padding(.trailing, 13)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Patka pruhu — `Zobrazit všechny (+2)`, nebo `Zobrazit méně`.
    ///
    /// **Rozbaluje na místě, nepřepíná do sekce.** Pruh míchá cizí a vlastní PR, takže žádná
    /// sekce railu nemá tutéž množinu a odkaz na sekci by vedl někam jinam, než co je nad ním
    /// (proto tady není `BlockFooter`, který má cíl).
    private func laneFooter(_ lane: WorkLane, hidden: Int) -> some View {
        let isExpanded = expandedLanes.contains(lane)
        return Button {
            if isExpanded { expandedLanes.remove(lane) } else { expandedLanes.insert(lane) }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: isExpanded ? "Zobrazit méně" : "Zobrazit všechny")
                    .font(.system(size: 11.5, weight: .medium))
                if !isExpanded {
                    Text(verbatim: "+\(hidden)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9))
            }
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            // Hover je `Palette.raised` = `--panel-3` v návrhu, jako u patky bloku (#384).
            .background(hoveredLane == lane ? Palette.raised : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        // Zápis jen na změnu, jako v `PullRequestTabBar`: odchod z patky nesmí přepsat hover,
        // který si mezitím vzala jiná.
        .onHover { hoveredLane = $0 ? lane : (hoveredLane == lane ? nil : hoveredLane) }
    }

    // MARK: - Blok

    /// Blok s hlavičkou. `count` je počet vedle nadpisu, `action` obsah vpravo v hlavičce.
    private func block(
        _ title: String,
        count: Int? = nil,
        @ViewBuilder action: () -> some View,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(verbatim: title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                if let count {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                }
                Spacer(minLength: 8)
                action()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
            content()
        }
        .background(Palette.chrome, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private var separator: some View {
        Rectangle().fill(Palette.lineSoft).frame(height: 1)
    }

    // MARK: - Odložené

    /// Blok `Odložené` na desce (#512, oprava po proklikání).
    ///
    /// **Číslo, ze kterého nevede cesta, je horší než žádné číslo.** Věta pod pozdravem hlásila
    /// `· 2 odložené` a domov na to neuměl odpovědět: blok visel jedině pod frontou, tedy na jiné
    /// obrazovce. Tenhle blok je odpověď — **z týchž řádků** jako ten pod frontou
    /// (`SnoozedRowsView`), aby se ty dvě podoby nemohly rozejít.
    ///
    /// **Nekreslí se, když odložené nic není**, jako prázdný pruh desky (#515) a jako blok pod
    /// frontou: rámeček s nulou je odpověď na otázku, kterou nikdo nepoložil. Rozhoduje o tom
    /// `isEmpty`, ne `Policy.snoozedBlockTitle`: nadpis tady skládá rám bloku (`block(_:count:)`),
    /// takže volat funkci na titulek a titulek zahodit by bylo tvrzení o sdílení, které neplatí.
    ///
    /// **Cesta do fronty je v hlavičce**, jako u `Dění`: odložené se odkládají tam a v seznamu je
    /// vidět i to, co je nad nimi.
    @ViewBuilder private func snoozedBlock(_ snoozed: [PullRequestSummary]) -> some View {
        if !snoozed.isEmpty {
            // **Strop, jako u pruhů a u `Dění`.** Nadpis počítá všechny, kreslí se prvních pět
            // a patka řekne, kolik se nevešlo — bez toho by dvacet odložených roztáhlo pravý
            // sloupec přes celou obrazovku a nikde by nestálo, že je to všechno.
            let shown = Array(snoozed.prefix(Policy.snoozedBoardRowLimit))
            block("Odložené", count: snoozed.count, action: { sectionLink(.queue, title: "do fronty →") }) {
                VStack(spacing: 0) {
                    SnoozedRowsView(
                        pullRequests: shown,
                        note: store.snoozeNote(for:),
                        open: { store.openTab($0) },
                        wake: { pr in Task { await store.wake(pr) } }
                    )
                    .padding(.vertical, 4)
                    if snoozed.count > shown.count {
                        separator
                        footerRow(BlockFooter(
                            title: "Zobrazit všechny odložené",
                            rest: "+\(snoozed.count - shown.count)",
                            section: .queue
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Dění

    /// Blok `Dění` (#443) — od #515 **osm** nejnovějších řádků a cesta do sekce.
    ///
    /// Pravý sloupec drží od #515 dva bloky místo tří (legenda reviewerů odešla s kartami,
    /// `Reviewery` postaví #514), takže se strop bloku zvedl z pěti na osm
    /// (`Policy.activityRowLimit`).
    private func activity(_ activity: DashboardActivity) -> some View {
        block(activity.title, action: { sectionLink(.activity, title: "celé dění →") }) {
            activityRows(activity)
        }
    }

    /// Odkaz vpravo v hlavičce bloku, který přepne do sekce railu.
    ///
    /// Akcent nese `.block > header .more` z návrhu; `AccentLinkButtonStyle` přidá ukazováček
    /// a ztlumení při zmáčknutí. Nápověda jde z `RailSection.switchHelp`, tedy z téhož místa
    /// jako u patky pod blokem — dvě cesty do jedné sekce mají říkat totéž.
    private func sectionLink(_ section: RailSection, title: String) -> some View {
        Button { store.show(section) } label: {
            Text(verbatim: title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(AccentLinkButtonStyle())
        .help(section.switchHelp)
    }

    /// Řádky bloku `Dění` — nebo jedna věta, když v záznamu nic není.
    ///
    /// **`LazyVStack` sem nepatří**: osm řádků je strop z `Policy`, ne odhad.
    @ViewBuilder private func activityRows(_ activity: DashboardActivity) -> some View {
        if let explanation = activity.emptyExplanation {
            // Bez osy: svislá čára jde přes celý blok, takže by u jediné věty stála čára, na
            // které nic nevisí.
            Text(verbatim: explanation)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
        } else {
            // **Jedny hodiny na celý blok** (nález Copilota na #418): `store.time.now` uvnitř
            // `ForEach`e by je vzalo osmkrát, takže se dva řádky ze stejné minuty mohou rozejít
            // o vteřinu — a s ní i o hranici mezi `před 2 min` a `v 07:58`.
            let now = store.time.now
            VStack(spacing: 0) {
                ActivityTimeline {
                    ForEach(activity.rows) { event in
                        ActivityRowView(
                            event: event,
                            now: now,
                            place: .dashboard,
                            open: { store.show($0) }
                        )
                    }
                }
                if let footer = activity.footer {
                    separator
                    footerRow(footer)
                }
            }
        }
    }

    /// Patka bloku (`.block > .more-rows`) — `Zobrazit celé dění +122 →`.
    ///
    /// **Není to řádek dění**, jen cesta do sekce: nekreslí se jako řádek a nepočítá se do řádků
    /// bloku. Text i počet skládá `Policy`, tady se kreslí.
    private func footerRow(_ footer: BlockFooter) -> some View {
        Button { store.show(footer.section) } label: {
            HStack(spacing: 6) {
                Text(verbatim: footer.title)
                    .font(.system(size: 11.5, weight: .medium))
                Text(verbatim: footer.rest)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
            }
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(hoveredFooter == footer.section ? Palette.raised : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover {
            hoveredFooter = $0 ? footer.section : (hoveredFooter == footer.section ? nil : hoveredFooter)
        }
        .help(footer.section.switchHelp)
    }

    // MARK: - Dneska stálo

    /// Útrata za dnešek jako **malý blok** v pravém sloupci (návrh, sekce 45), ne karta.
    ///
    /// **Nenačtená není nulová** — `0,00 $` by tvrdilo, že se dneska nic neutratilo. Značku `≥`
    /// u neúplného součtu skládá `RunUsageText`, tedy totéž místo jako ve stavovém řádku.
    private var spendBlock: some View {
        block("Dneska stálo", action: {
            Text(verbatim: store.dailySpend.map(RunUsageText.spent) ?? "—")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.accent)
                .monospacedDigit()
        }) {
            SpendSparkline(days: store.spendHistory)
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
    }

    private var bulkRunQuestion: String {
        let count = store.pullRequestsNotReviewed.count
        return "Spustit review na " + Plural.czech(
            count,
            one: "pull requestu",
            few: "pull requestech",
            many: "pull requestech"
        ) + "?"
    }
}
