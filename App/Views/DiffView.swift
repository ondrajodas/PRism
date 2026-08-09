import SwiftUI

/// Diff v plné šířce: soubory pod sebou, hlavička souboru se při scrollu drží nahoře.
///
/// Skládá se líně (`LazyVStack`) — diff o tisících řádků je běžný a vykreslit ho celý
/// naráz by okno na chvíli položilo.
struct DiffView: View {
    let diff: Diff
    /// Kam odscrollovat. Nastaví ho panel nálezů; po skoku se vrací na `nil`, aby šlo
    /// na totéž místo skočit i podruhé.
    @Binding var scrollTarget: String?
    /// Rozbalování kontextu. Bere se ze store, ne z vlastního stavu — jinak by rozbalení
    /// přeteklo z jednoho pull requestu na druhý.
    let expansion: DiffExpansionActions
    /// Sbalování celých souborů. Taky ze store, ze stejného důvodu jako `expansion`.
    let folding: DiffFoldingActions
    /// Nálezy k zavěšení pod řádky. Seskupené podle místa už volajícím.
    var findings: [FindingGroup] = []
    /// Odmítnutí a vrácení nálezu (#113). Skupiny si stav nesou samy, tudy jdou jen akce.
    var findingActions: FindingActions?
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    /// Místo, na které se právě skočilo z tabulky nálezů.
    var highlighted: FindingHighlight?
    /// Vlákna konverzace, která mají v tomhle diffu kotvu. Vybral je volající
    /// (`Policy.threadsInTheDiff`) — zastaralá patří do `Overview`, ne sem.
    var threads: [ReviewThread] = []
    /// Kolik vláken se do stránky konverzace nevešlo. Nula u běžného PR — sto vláken je
    /// řádově víc, než kolik jich vzniká.
    var missingThreads = 0
    var viewer: String = ""
    /// Rozbalení, odpovídání a vyřešení vláken (#73) — jeden parametr, protože patří k sobě.
    var threadActions = ThreadActions()
    /// Moje rozdělané komentáře. Kreslí se ty, které v diffu mají kotvu — celý seznam je
    /// v panelu, takže se komentář na zmizelém řádku neztratí.
    var comments: [ReviewDraftComment] = []
    var draft = DraftActions()
    /// Pohled na diff — pod sebou, nebo vedle sebe.
    ///
    /// Binding do storu, ne `@AppStorage` jako u přepínače nálezů: výchozí hodnota je
    /// v `config.json` (mění se v nastavení) a přepínač v liště je proti ní jen **odchylka do
    /// zavření aplikace**. Zapisovat ji na disk by znamenalo, že se nastavená hodnota mění
    /// sama tím, že si člověk u jednoho souboru otočí pohled.
    @Binding var layout: DiffLayout
    /// Stav procházení nálezů (#187). Počítá ho volající, protože skáče taky on — lišta jen
    /// ukazuje, co z toho vyšlo.
    var navigation: FindingNavigation = .none
    var onlyBlocking: Binding<Bool> = .constant(false)
    /// Rozložený panel nálezů (#197). `nil` = tlačítko se nekreslí; stav drží detail PR, protože
    /// panel je vidět i v tabu, kde tahle lišta není.
    var panelExpanded: Binding<Bool>?
    var stepFinding: ((NavigationStep) -> Void)?

    /// Předvolba pohledu napříč pull requesty, takže patří do `UserDefaults`, ne do store.
    @AppStorage("showFindingBubbles") private var showBubbles = true
    @State private var isPickingFile = false
    /// Rozložený strom v levém sloupci (#197). Předvolba pohledu napříč PR, takže `UserDefaults`
    /// — a ne stav ve store, ze stejného důvodu jako u bublin.
    @AppStorage("diffTreeExpanded") private var isTreeExpanded = true
    /// Výška viditelné části diffu — z ní se počítá, kam skočí nález. Čte se jen měřením
    /// (`onGeometryChange`), takže do rozvržení nezasahuje: `GeometryReader` by naopak sám
    /// zabral místo a v tomhle okně už jednou nadělal škodu.
    @State private var viewportHeight = 0.0
    /// Rámečky řádků pro tažení rozsahu (#110). `@State`, aby přežily překreslení; obsah je
    /// mimo observable stav, takže se jimi diff nepřekresluje — viz `DiffRowFrames`.
    @State private var rowFrames = DiffRowFrames()
    /// Hunk otevřený jako text k vybírání (#157). Sheet drží diff, protože je nad celým seznamem
    /// řádků — a `nil` znamená, že žádný otevřený není.
    @State private var codeText: CodeText?

    /// Souřadnicový prostor **obsahu** diffu. Rámečky řádků i poloha myši při tažení se čtou
    /// v něm, takže scrollování s nimi nehýbe.
    static let contentSpace = "prism-diff-content"

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                summary(jumpingWith: proxy)
                Divider()
                // Strom vlevo, diff vedle něj (#197). Do té doby byl strom jen v popoveru,
                // takže u PR o padesáti souborech nešlo poznat, kde v něm člověk je, aniž by
                // ho otevřel.
                HStack(spacing: 0) {
                    tree(jumpingWith: proxy)
                    files
                }
            }
            // Kam cíl skočí, řeší `jumpAnchor`: **k vršku, ale s odstupem**. Na vrch samotný
            // ne — ukotvená hlavička souboru vršek překrývá a bublina visí **pod** svým
            // řádkem, takže by bylo vidět jen ji a kód nad ní ne.
            //
            // **`task(id:)`, ne `onChange`.** Od #72 se dá na nález kliknout i z `Přehledu`,
            // odkud se nejdřív přepne tab — a diff v tu chvíli **vzniká**. Cíl už v něm tedy
            // je a `onChange` by se nespustil, protože žádná změna nepřišla; `task(id:)` se
            // spustí i při vzniku.
            .task(id: scrollTarget) {
                guard let target = scrollTarget else { return }
                // Cíl je **řádek**, ale v seznamu je od #157 blok, který nese `id` jen toho
                // prvního — bez překladu `scrollTo` tiše nic neudělá.
                withAnimation { proxy.scrollTo(blockID(covering: target), anchor: jumpAnchor) }
                scrollTarget = nil
            }
        }
    }

    /// Blok, který cílový řádek pokrývá — a když žádný, cíl sám.
    ///
    /// Skládá se **týmiž vstupy, jakými se ten soubor kreslí** (pohled, odkryté úseky, bubliny,
    /// vlákna, komentáře): kde se blok přeruší, na nich totiž závisí, a index poskládaný z jiných
    /// vstupů by ukazoval na blok, který v seznamu není. Počítá se jen při skoku, tedy jednou za
    /// kliknutí, a jen pro **jeden** soubor.
    private func blockID(covering target: String) -> String {
        // Porovnává se na **celé** `id`, ne na prefix: cesty se přejmenováním umí stát prefixem
        // jedna druhé (`src/A.php` a `src/A.php.bak`) a index by se pak skládal z cizího souboru.
        // Cíl je buď `file.id` sám (skok na hlavičku), nebo `file.id|<řádek>`.
        guard
            let file = diff.files.first(where: { target == $0.id || target.hasPrefix($0.id + "|") })
        else { return target }
        let state = expansion.state(file)
        let rows = DiffRow.rows(
            of: file,
            layout: layout,
            revealed: state.revealed,
            content: state.content,
            findings: showBubbles ? findings : [],
            threads: threads,
            comments: comments
        )
        let blocked = layout == .split ? DiffRow.blockedPairs(rows) : DiffRow.blocked(rows)
        return DiffRow.blockIDs(in: blocked)[target] ?? target
    }

    /// Kam v okně skočí nález — **k vršku, ale s odstupem na pár řádků kontextu**.
    ///
    /// `scrollTo` umí jen podíl výšky, ne body, takže se z bodů podíl počítá: nad cílem má
    /// zůstat ukotvená hlavička souboru (překrývá vršek) a pod ní ještě pár řádků, ať je vidět,
    /// do čeho nález patří. Doprostřed to skákalo do #72 a půlka obrazovky nad nálezem byla
    /// zbytečná; na vrch samotný zase cíl skončí pod hlavičkou.
    ///
    /// Strop `0.5` je pojistka pro nízké okno: v pruhu o výšce dvou řádků je „pět řádků nad“
    /// nesplnitelné a střed je pak to nejlepší, co jde udělat. Dokud výška nedorazí, platí
    /// taky střed — je to jediná hodnota, která nezávisí na tom, co ještě nevíme.
    private var jumpAnchor: UnitPoint {
        guard viewportHeight > 0 else { return .center }
        return UnitPoint(x: 0, y: min(0.5, Self.contextAbove / viewportHeight))
    }

    /// Ukotvená hlavička souboru (~30 pt) a tři řádky diffu (~22 pt na řádek). Vyladěné na
    /// běžící aplikaci: se pěti řádky (140 pt) odskok působil zbytečně velký.
    private static let contextAbove = 90.0

    /// Každý **řádek** je vlastní buňka líného seznamu, ne každý hunk. Hunk jako celek
    /// se po změně šířky okna překresloval jen zčásti a v diffu zůstávala prázdná místa.
    private var files: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(diff.files) { file in
                    Section {
                        // Sbalený soubor se nevykresluje vůbec — u padesátisouborového PR
                        // je to hlavní důvod, proč se sbaluje. Hlavička zůstává, takže
                        // sekce nezmizí a skok na soubor pořád funguje.
                        if !folding.isFolded(file) {
                            rows(of: file)
                        }
                    } header: {
                        fileHeader(file)
                    }
                    .id(file.id)
                }
            }
            .coordinateSpace(.named(Self.contentSpace))
        }
        // Jen měření, žádný vliv na rozvržení — proto `onGeometryChange` a ne `GeometryReader`.
        .onGeometryChange(for: Double.self) { $0.size.height } action: { viewportHeight = $0 }
        .sheet(item: $codeText) { CodeTextSheet(content: $0) }
    }

    /// Hunk jako text k vybírání. Kód se skládá **stejnou funkcí jako pro schránku**
    /// (`Policy.code(of:)`), takže se vybraný text nemůže rozejít s tím, co dá `Kopírovat hunk`.
    private func codeText(of hunk: DiffHunk, in file: FileDiff) -> CodeText {
        CodeText(
            id: "\(file.displayPath)#\(hunk.header)",
            path: file.displayPath,
            heading: hunk.header,
            code: Policy.code(of: hunk)
        )
    }

    private func rows(of file: FileDiff) -> some View {
        let state = expansion.state(file)
        let language = Language(path: file.displayPath)
        // Řádky se před vykreslením slijí do bloků (#157), aby v nich šlo vybírat text přes víc
        // řádků — v obou pohledech. Ve split se slévají **dvojice** (`blockedPairs`) do dvou
        // sloupců, které si odpovídají řádek po řádku; podrobnosti u `DiffPairBlockView`.
        let rows = DiffRow.rows(
            of: file,
            layout: layout,
            revealed: state.revealed,
            content: state.content,
            findings: showBubbles ? findings : [],
            // Vlákna se přepínačem `Nálezy` **neschovávají**. Ten přepínač je o nálezech
            // naší aplikace; cizí komentář u kódu je důvod, proč se na PR člověk dívá,
            // a schovat ho spolu s nálezy by ho připravilo o to hlavní. Totéž platí o mých
            // rozdělaných komentářích — ty se schovat nesmí o důvod víc, protože se odešlou.
            threads: threads,
            comments: comments
        )
        // Kotvy jednou za soubor, ne pro každý řádek: `Policy.commentableSide` ověřuje
        // příslušnost k hunku hledáním, takže po řádcích je to kvadratické.
        let fileDraft = draft.bound(to: file, anchors: Policy.commentAnchors(in: file))
        // Rozsahy taky jednou za soubor: hledání konců jde přes všechny hunky, takže po řádcích
        // by to bylo kvadratické — tentýž důvod jako u kotev.
        let rangeCells = Policy.commentRangeCells(of: comments, in: file)
        // Rozsah, který se právě táhne, se drží **zvlášť**: svítí výrazněji než hotový komentář
        // a jen na jeho konci je vidět tlačítko, aby šlo s myší.
        let dragged = draft.draggedRange.flatMap { $0.path == file.displayPath ? $0.anchor : nil }
        let draggedCells = dragged.map { Policy.rangeCells(of: $0, in: file) } ?? []
        return ForEach(layout == .split ? DiffRow.blockedPairs(rows) : DiffRow.blocked(rows)) { row in
            DiffRowView(
                row: row,
                language: language,
                layout: layout,
                isLoadingContent: state.isLoading,
                contentFailure: state.failure,
                reveal: { expansion.reveal(file, $0) },
                highlighted: highlighted,
                blockingCategories: blockingCategories,
                findingActions: findingActions,
                viewer: viewer,
                threads: threadActions,
                draft: fileDraft,
                commentRangeCells: rangeCells,
                draggedCells: draggedCells,
                dragEnd: dragged?.end,
                rangeDrag: RangeDragActions(
                    frames: rowFrames,
                    move: { draft.dragRange(file.displayPath, $0, $1) },
                    end: draft.endRangeDrag
                ),
                // Kopírování (#157) se skládá **až při otevření menu**: text rozsahu se hledá přes
                // všechny hunky, takže při vykreslení každého řádku by to byla práce navíc u
                // operace, kterou nikdo nevyvolal. Rozsahy se berou z **mých rozdělaných**
                // komentářů — tažení už je vybírá a zvýrazňuje, jen se s nimi dosud dala udělat
                // jediná věc.
                copy: DiffCopyActions(
                    targets: { Policy.copyTargets(for: $0, in: file, comments: comments) },
                    hunkTargets: { hunk in
                        [DiffCopyTarget(id: "hunk", title: "Kopírovat hunk", text: Policy.code(of: hunk))]
                    },
                    selectableText: { line in
                        Policy.hunk(containing: line, in: file).map { codeText(of: $0, in: file) }
                    },
                    selectableHunkText: { codeText(of: $0, in: file) },
                    showText: { codeText = $0 }
                )
            )
        }
    }

    private func summary(jumpingWith proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            (Text(verbatim: "\(files(diff.files.count)) · ")
                + DiffCounts.text(additions: diff.additions, deletions: diff.deletions))
                .font(.callout)
                .foregroundStyle(.secondary)
            if diff.unrecognizedLines > 0 {
                unrecognizedWarning
            }
            if missingThreads > 0 {
                missingThreadsWarning
            }
            Spacer()
            // Procházení stojí **vlevo od pohledu a přepínačů**: je to jediná věc v liště,
            // která se používá při každém review, kdežto zbytek se nastaví a nechá být.
            if let stepFinding, !navigation.isEmpty {
                FindingNavigationView(
                    navigation: navigation,
                    onlyBlocking: onlyBlocking,
                    step: stepFinding
                )
                Divider().frame(height: 16)
            }
            layoutPicker
            if !findings.isEmpty {
                // Jmenuje se `Nálezy`, ne `Bubliny`: schovává **jen** nálezy, kdežto
                // „bubliny“ jsou od #64 i vlákna konverzace. Chytilo se to při zkoušení —
                // obecný název sliboval, že vypne obojí.
                Toggle("Nálezy", isOn: $showBubbles)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .help("Zobrazit nálezy u řádků, kterých se týkají. Vlákna konverzace zůstanou.")
            }
            foldAllButton
            if let collapse = expansion.collapse {
                Button("Zobrazit jen diff", systemImage: "arrow.down.right.and.arrow.up.left") {
                    collapse()
                }
                .font(.callout)
                .buttonStyle(.borderless)
            }
            columnToggles
            jumpMenu(proxy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Přepnutí pohledu na diff. Segmentovaný přepínač s ikonami, ne přepínač v nastavení:
    /// otočit pohled je věc, která se dělá **při čtení konkrétního souboru** — chodit pro ni
    /// do ⌘, a hledat pole je pro tenhle pohyb špatné.
    ///
    /// Zůstává **do zavření aplikace** a napříč pull requesty: pohled je způsob čtení, takže
    /// přepnutím na jiný PR nemá důvod se vracet. Po restartu platí zase to, co je v nastavení.
    private var layoutPicker: some View {
        Picker("Pohled na diff", selection: $layout) {
            ForEach(DiffLayout.allCases, id: \.self) { option in
                Image(systemName: option.symbol)
                    .accessibilityLabel(Text(verbatim: option.displayName))
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        // Popisek zůstává vyplněný a jen se schová: pro VoiceOver je to pořád jediný popis
        // celého přepínače.
        .labelsHidden()
        .fixedSize()
        .help("Kreslit diff vedle sebe (starý a nový obsah proti sobě), nebo pod sebou")
    }

    /// Jedno tlačítko, ne dvě. Který ze dvou stavů dává smysl, plyne z toho, co je zrovna
    /// na obrazovce — dvě tlačítka by znamenala, že je jedno z nich pořád k ničemu.
    ///
    /// Nepleteme si to se „Zobrazit jen diff“ vedle: to sbaluje **kontext uvnitř** souborů,
    /// tohle celé soubory.
    @ViewBuilder private var foldAllButton: some View {
        if !diff.files.isEmpty {
            let allFolded = diff.files.allSatisfy(folding.isFolded)
            Button {
                if allFolded { folding.unfoldAll() } else { folding.foldAll(diff.files) }
            } label: {
                Label(
                    allFolded ? "Rozbalit vše" : "Sbalit vše",
                    systemImage: allFolded ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
                )
            }
            .font(.callout)
            .buttonStyle(.borderless)
            .help(allFolded ? "Rozbalit diffy všech souborů" : "Sbalit diffy všech souborů")
        }
    }

    /// Vlákna, která nedorazila, nemají jak chybět **viditelně**: v diffu se prostě
    /// neobjeví bublina a to od „nikdo tam nic nenapsal“ nikdo nepozná. Hlásí se proto
    /// stejně jako nepřečtené řádky diffu.
    private var missingThreadsWarning: some View {
        // Sloveso je **v tvarech**: „2 vlákna se nevešlo“ je špatně česky.
        let count = Plural.czech(
            missingThreads,
            one: "vlákno konverzace se nevešlo",
            few: "vlákna konverzace se nevešla",
            many: "vláken konverzace se nevešlo"
        )
        return Label {
            Text(verbatim: "\(count) — otevři PR na GitHubu")
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    /// Nerozpoznaný řádek znamená, že se člověk dívá na neúplný podklad. Bez téhle věty
    /// by neúplný diff vypadal jako úplný.
    private var unrecognizedWarning: some View {
        let count = Plural.czech(diff.unrecognizedLines, one: "řádek", few: "řádky", many: "řádků")
        return Label {
            Text(verbatim: "\(count) diffu se nepodařilo přečíst")
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    /// Přepínače postranních sloupců, jak je má návrh v liště nad diffem (#197): `Strom ⌘1`
    /// a `Nálezy ⌘2`.
    ///
    /// Zkratky visí jinde — ⌘1 tady, ⌘2 v detailu PR (panel je vidět i v tabu `Přehled`, kde
    /// tahle lišta není). Tlačítka jsou proto **jen tlačítka**, popisek klávesy nese nápověda.
    @ViewBuilder private var columnToggles: some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { isTreeExpanded.toggle() }
        } label: {
            Image(systemName: "sidebar.left")
                .foregroundStyle(isTreeExpanded ? Color.accentColor : Palette.ink3)
        }
        .buttonStyle(.borderless)
        .help(isTreeExpanded ? "Složit strom souborů (⌘1)" : "Rozložit strom souborů (⌘1)")
        .accessibilityLabel("Strom souborů")
        .keyboardShortcut("1", modifiers: .command)

        if let panelExpanded {
            Button {
                withAnimation(.snappy(duration: 0.15)) { panelExpanded.wrappedValue.toggle() }
            } label: {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(panelExpanded.wrappedValue ? Color.accentColor : Palette.ink3)
            }
            .buttonStyle(.borderless)
            .help(panelExpanded.wrappedValue ? "Složit panel nálezů (⌘2)" : "Rozložit panel nálezů (⌘2)")
            .accessibilityLabel("Panel nálezů")
        }
    }

    /// Levý sloupec se stromem souborů (#197), nebo proužek, když je složený.
    ///
    /// Šířka 210 bodů je z návrhu (`grid-template-columns: 210px 1fr 300px`). Složený je proužek
    /// 34 bodů — **ne zmizelý sloupec**: kolik souborů PR mění, je ta první otázka nad diffem
    /// a bez čísla na hraně se na ni po složení nedá odpovědět.
    @ViewBuilder private func tree(jumpingWith proxy: ScrollViewProxy) -> some View {
        if isTreeExpanded {
            FileTreeView(files: diff.files, markers: fileMarkers, isCompact: true) { file in
                jump(to: file, with: proxy)
            }
            .frame(width: Self.treeWidth)
            .background(Palette.chrome)
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.lineSoft).frame(width: 1) }
        } else {
            Button {
                withAnimation(.snappy(duration: 0.15)) { isTreeExpanded = true }
            } label: {
                VStack(spacing: 9) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink3)
                    Text(verbatim: "\(diff.files.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Palette.raised, in: .rect(cornerRadius: 4))
                    Text("soubory")
                        .font(.system(size: 10.5))
                        .tracking(0.6)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize()
                        .rotationEffect(.degrees(90))
                        .frame(width: Self.collapsedTreeWidth)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .frame(width: Self.collapsedTreeWidth, alignment: .top)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(Palette.chrome)
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.lineSoft).frame(width: 1) }
            .help("Rozložit strom souborů (⌘1)")
            .accessibilityLabel("Rozložit strom souborů")
        }
    }

    /// Skok na soubor — **jedno místo pro strom i popover**, ať se sbalený soubor rozbalí v obou.
    private func jump(to file: FileDiff, with proxy: ScrollViewProxy) {
        // Skočit na sbalený soubor jde — hlavička zůstává — ale ukázala by se jen ona.
        // Kdo si ho ze stromu vybral, chce ho vidět.
        if folding.isFolded(file) { folding.toggle(file) }
        withAnimation { proxy.scrollTo(file.id, anchor: .top) }
    }

    static let treeWidth = 210.0
    private static let collapsedTreeWidth = 34.0

    /// Popover se stromem, ne rozbalovací menu: u PR přes třicet souborů je plochý seznam
    /// cest nepoužitelný a vnořená podmenu se špatně trefují.
    private func jumpMenu(_ proxy: ScrollViewProxy) -> some View {
        Button {
            isPickingFile = true
        } label: {
            Label("Přejít na soubor", systemImage: "list.bullet.indent")
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isPickingFile, arrowEdge: .bottom) {
            FileTreeView(files: diff.files, markers: fileMarkers) { file in
                isPickingFile = false
                jump(to: file, with: proxy)
            }
            // Rozměr popoveru drží **volající**, ne strom: v levém sloupci (#197) je týž strom
            // pružný a pevná velikost by ho v něm rozbila.
            .frame(width: 420, height: 320)
        }
    }

    /// Které soubory nesou nález (#197). Počítá `Policy`, ať strom a panel neříkají o téže věci
    /// každý něco jiného.
    private var fileMarkers: [String: FileMarker] {
        // `findings` jsou **skupiny** (shoda reviewerů na `file:line`), takže se rozbalí zpátky
        // na platné nálezy — značka mluví o souboru, ne o skupině.
        Policy.fileMarkers(of: findings.flatMap(\.activeFindings), categories: blockingCategories)
    }

    /// Celá hlavička je tlačítko, ne jen šipka — na GitHubu se kliká kamkoli do řádku
    /// a trefit se do šipky u padesáti souborů je práce navíc.
    private func fileHeader(_ file: FileDiff) -> some View {
        Button {
            folding.toggle(file)
        } label: {
            headerContent(file)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: file.displayPath))
        .accessibilityHint(folding.isFolded(file) ? "Rozbalí diff souboru" : "Sbalí diff souboru")
    }

    private func headerContent(_ file: FileDiff) -> some View {
        HStack(spacing: 8) {
            Image(systemName: folding.isFolded(file) ? "chevron.right" : "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10)
            Text(verbatim: file.displayPath)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .truncationMode(.head)
            if let badge = badge(for: file) {
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
            }
            if file.change == .renamed, let oldPath = file.oldPath {
                Text(verbatim: "← \(oldPath)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            fileFindings(file)
            DiffCounts.text(additions: file.additions, deletions: file.deletions)
                .font(.caption)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        // Ukotvená hlavička jede přes obsah, takže pod ní musí být neprůhledné pozadí.
        .background(.bar)
        // **Ne `Divider()`.** Ten si orientaci bere z okolní osy a v `overlay` žádná není,
        // takže se vykreslí **svisle** — pod hlavičkami tedy nikdy nebyla čára, kterou tam
        // tenhle kód chtěl, ale svislá čárka uprostřed. Dokud mezi hlavičkami byly řádky
        // diffu, ztrácely se; po sbalení všech souborů (#59) se poskládaly do jedné čáry.
        .overlay(alignment: .bottom) {
            Rectangle().fill(.separator).frame(height: 1)
        }
    }

    /// Kolik nálezů v souboru je.
    ///
    /// Ukazuje se **vždycky**, ne jen u sbaleného. U sbaleného je to nutnost — zavřený
    /// soubor s nevyřízeným nálezem by se dal zapomenout a tabulka nálezů je jiná
    /// obrazovka. U rozbaleného to není šum, ale zkratka: projedu hlavičky a vím, kde
    /// nálezy jsou, aniž bych scrolloval obsahem.
    /// Počítá **platné** nálezy (#113). Odznak je zkratka „kde je co vyřídit“, takže odmítnutý
    /// nález v něm nemá co dělat — a hlavně by u sbaleného souboru svítil červeně nad něčím, co
    /// jsem už posoudil. Nemizí tím nic: bublina u řádku i řádek v tabulce zůstávají.
    @ViewBuilder private func fileFindings(_ file: FileDiff) -> some View {
        let groups = findings(in: file).filter { !$0.activeFindings.isEmpty }
        if !groups.isEmpty {
            let blocking = groups.contains { group in
                group.activeFindings.contains { Policy.isBlocking($0, categories: blockingCategories) }
            }
            Label(
                Plural.czech(groups.count, one: "nález", few: "nálezy", many: "nálezů"),
                systemImage: blocking ? "exclamationmark.triangle.fill" : "text.magnifyingglass"
            )
            .font(.caption)
            .foregroundStyle(blocking ? .red : .secondary)
        }
    }

    /// Nálezy patřící k souboru. Nález umí přijít pod **starou** cestou přejmenovaného
    /// souboru, takže se porovnává proti oběma.
    ///
    /// Stejně jako `DiffRow.groups(of:from:)`, a je to podmínka správnosti, ne kosmetika:
    /// odznak musí počítat přesně to, co se ukáže jako bubliny. Přes `Diff.file(at:)` by se
    /// to rozešlo u řetězu přejmenování, kde jedna cesta sedí na dva soubory — a bylo by to
    /// navíc lineární hledání uvnitř dvojité smyčky.
    private func findings(in file: FileDiff) -> [FindingGroup] {
        findings.filter { group in
            guard let path = group.file else { return false }
            return path == file.newPath || path == file.oldPath
        }
    }

    private func badge(for file: FileDiff) -> String? {
        if file.isBinary { return "binární" }
        switch file.change {
        case .added: return "nový"
        case .deleted: return "smazaný"
        case .renamed: return "přejmenovaný"
        case .modified: return nil
        }
    }

    private func files(_ count: Int) -> String {
        Plural.czech(count, one: "soubor", few: "soubory", many: "souborů")
    }
}
