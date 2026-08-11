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
    /// Rozbalení bublin nálezů (#185) — blokující je rozbalený rovnou, ostatní jsou značka na
    /// hraně řádku. Rozhoduje store, protože bublina je buňka líného seznamu a diff sám se
    /// přestaví při každém složení panelu vpravo.
    var findingDisclosure = FindingDisclosureActions()
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
    /// Rozložený panel nálezů (#197). Diff ho **nepřepíná tlačítkem** (od #219 se panel skládá
    /// u sebe), ale skládá ho automatika pohledu vedle sebe (#188) — proto tu ten binding je.
    /// `nil` = automatika se panelu nedotkne. Stav drží detail PR, protože panel je vidět
    /// i v tabu, kde diff není.
    var panelExpanded: Binding<Bool>?
    var stepFinding: ((NavigationStep) -> Void)?

    /// Předvolba pohledu napříč pull requesty, takže patří do `UserDefaults`, ne do store.
    @AppStorage("showFindingBubbles") private var showBubbles = true
    /// Rozložený strom v levém sloupci (#197). Předvolba pohledu napříč PR, takže `UserDefaults`
    /// — a ne stav ve store, ze stejného důvodu jako u bublin.
    @AppStorage("diffTreeExpanded") private var isTreeExpanded = true
    /// Výška viditelné části diffu — z ní se počítá, kam skočí nález. Čte se jen měřením
    /// (`onGeometryChange`), takže do rozvržení nezasahuje: `GeometryReader` by naopak sám
    /// zabral místo a v tomhle okně už jednou nadělal škodu.
    @State private var viewportHeight = 0.0
    /// Pro který pohled už automatika sloupce složila (#188). Bez toho by se opakovala při
    /// každém vzniku view a přebíjela ruční `⌘1`/`⌘2`.
    @State private var appliedLayout: DiffLayout?
    /// Šířka, kterou má diff k dispozici — z ní se počítá, kolik znaků se vejde na stranu (#188).
    @State private var contentWidth = 0.0
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
                toolbar
                // Strom vlevo, diff vedle něj (#197). Do té doby byl strom jen v popoveru,
                // takže u PR o padesáti souborech nešlo poznat, kde v něm člověk je, aniž by
                // ho otevřel.
                HStack(spacing: 0) {
                    tree(jumpingWith: proxy)
                    files
                }
            }
            .background(alignment: .topLeading) { treeShortcut }
            // **Pohled vedle sebe složí postranní sloupce** (#188). Řádek se v něm dělí na dvě
            // strany, takže na 14" nezbude ani 100 znaků; pod sebou je zase rozbalí. Ruční
            // `⌘1`/`⌘2` to přebijí jednoduše tím, že platí až do **další** změny pohledu.
            //
            // `task(id:)`, ne `onChange`: pohled se drží napříč pull requesty (a výchozí je
            // z nastavení), takže s `onChange` by se na PR otevřeném rovnou ve splitu nesložilo
            // nic — změna nepřišla. `task(id:)` se spustí i při vzniku.
            .task(id: layout) {
                // **Jen jednou na pohled.** `task(id:)` se spustí i při novém vzniku view —
                // a to nastane pokaždé, když se přepne panel vpravo, protože se tím přestaví
                // `HStack` v detailu PR. Bez téhle stráže se ručně otevřený strom hned zase
                // složil a nešel otevřít vůbec.
                guard appliedLayout != layout else { return }
                appliedLayout = layout
                withAnimation(.snappy(duration: 0.15)) {
                    isTreeExpanded = layout != .split
                    panelExpanded?.wrappedValue = layout != .split
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            viewportHeight = $0.height
            contentWidth = $0.width
        }
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
                findingDisclosure: findingDisclosure,
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

    private var toolbar: some View {
        DiffToolbar(
            diff: diff,
            layout: $layout,
            navigation: navigation,
            onlyBlocking: onlyBlocking,
            stepFinding: stepFinding,
            showBubbles: $showBubbles,
            hasFindings: !findings.isEmpty,
            folding: folding,
            collapseExpansion: expansion.collapse,
            missingThreads: missingThreads,
            contentWidth: contentWidth
        )
    }

    /// ⌘1 na složení stromu. Bydlí **mimo lištu**, protože v ní od #219 žádné tlačítko na sloupce
    /// není — skládají se u sebe, tlačítkem v hlavičce sloupce a proužkem, kterým se zase otevřou.
    /// Zkratka tedy nemá na čem viset a musí být samostatně. Průhledné tlačítko, ne `.hidden()`:
    /// skryté view z hierarchie zmizí i se zkratkou. Tentýž vzorec jako ⌘2 v detailu PR.
    private var treeShortcut: some View {
        Button("Strom souborů") {
            withAnimation(.snappy(duration: 0.15)) { isTreeExpanded.toggle() }
        }
        .keyboardShortcut("1", modifiers: .command)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Levý sloupec se stromem souborů (#197), nebo proužek, když je složený.
    ///
    /// Šířka 210 bodů je z návrhu (`grid-template-columns: 210px 1fr 300px`). Složený je proužek
    /// 34 bodů — **ne zmizelý sloupec**: kolik souborů PR mění, je ta první otázka nad diffem
    /// a bez čísla na hraně se na ni po složení nedá odpovědět.
    @ViewBuilder private func tree(jumpingWith proxy: ScrollViewProxy) -> some View {
        if isTreeExpanded {
            VStack(spacing: 0) {
                // Hlavička jako u panelu vpravo: popisek z návrhu (`7 SOUBORŮ`) a šipka, kterou
                // se sloupec zavře. Zavírat jedině z lišty nad diffem znamená hledat tlačítko
                // na druhém konci okna, než u kterého člověk zrovna je.
                HStack(spacing: 8) {
                    Text(verbatim: Plural.czech(
                        diff.files.count,
                        one: "soubor",
                        few: "soubory",
                        many: "souborů"
                    ).uppercased())
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        withAnimation(.snappy(duration: 0.15)) { isTreeExpanded = false }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                            .foregroundStyle(Palette.ink3)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Složit strom souborů (⌘1)")
                    .accessibilityLabel("Složit strom souborů")
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }

                FileTreeView(files: diff.files, markers: fileMarkers) { file in
                    jump(to: file, with: proxy)
                }
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
                    // Svislý popisek: **`fixedSize` a pak výška**, ne šířka. Otočený text má
                    // pořád vodorovný rámeček, takže omezením šířky se ořízne — a delší
                    // popisek pak leze přes odznak nad sebou.
                    Text(verbatim: Plural.word(
                        diff.files.count,
                        one: "soubor",
                        few: "soubory",
                        many: "souborů"
                    ))
                        .font(.system(size: 10.5))
                        .tracking(0.6)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize()
                        .rotationEffect(.degrees(90))
                        // Otočení **nemění rozvržení** — rámeček zůstává vodorovný. Bez rámečku
                        // po otočení si tedy proužek vezme šířku nenatočeného textu a roztáhne
                        // se; proto se tady zadává **otočený otisk** (úzký a vysoký).
                        .frame(width: 13, height: 62)
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

    /// Skok na soubor ze stromu. Sbalený soubor se **nejdřív rozbalí** — jinak by se ukázala
    /// jen jeho hlavička.
    private func jump(to file: FileDiff, with proxy: ScrollViewProxy) {
        // Skočit na sbalený soubor jde — hlavička zůstává — ale ukázala by se jen ona.
        // Kdo si ho ze stromu vybral, chce ho vidět.
        if folding.isFolded(file) { folding.toggle(file) }
        withAnimation { proxy.scrollTo(file.id, anchor: .top) }
    }

    static let treeWidth = 210.0
    private static let collapsedTreeWidth = 34.0

    /// Které soubory nesou nález (#197). Počítá `Policy`, ať strom a panel neříkají o téže věci
    /// každý něco jiného.
    private var fileMarkers: [String: FileMarker] {
        // `findings` jsou **skupiny** (shoda reviewerů na `file:line`), takže se rozbalí zpátky
        // na platné nálezy — značka mluví o souboru, ne o skupině.
        let markers = Policy.fileMarkers(of: findings.flatMap(\.activeFindings), categories: blockingCategories)
        // **Přejmenovaný soubor má dvě cesty.** Reviewer umí nález nahlásit pod tou starou,
        // kdežto strom kreslí `displayPath` (novou) — bez překladu by se u přejmenovaného
        // souboru značka nezobrazila vůbec. `Diff.file(at:)` hledá po obou stranách, takže
        // je to tentýž překlad, jaký dělá skok na nález.
        return Dictionary(
            markers.compactMap { path, marker in
                diff.file(at: path).map { ($0.displayPath, marker) }
            },
            // Když se stará i nová cesta potkají na témž souboru, blokující vyhrává — stejné
            // pravidlo jako uvnitř `Policy.fileMarkers`.
            uniquingKeysWith: { left, right in left == .blocking || right == .blocking ? .blocking : left }
        )
    }

    private func fileHeader(_ file: FileDiff) -> some View {
        DiffFileHeaderView(
            file: file,
            isFolded: folding.isFolded(file),
            findings: findings(in: file),
            blockingCategories: blockingCategories,
            toggle: { folding.toggle(file) }
        )
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
}
