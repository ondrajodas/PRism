import SwiftUI

/// Diff v plné šířce: soubory pod sebou, hlavička souboru se při scrollu drží nahoře.
///
/// **Seznam je pevný (`VStack`), laznost je v nasazování bloků** (#469). Líný seznam by diff
/// skládal po kusech sám, jenže si při umisťování položek zapisuje do grafu, ze kterého čte,
/// a to kolo se nemá kde zastavit (#361, tam u osy konverzace). Od #469 tedy o tom, jestli má blok
/// kódu živý `NSTextView`, rozhoduje `Policy.mountBand(visible:)` a `DiffBlockSlot`; ukotvenou
/// hlavičku, kterou uměl `LazyVStack(pinnedViews:)`, kreslí `DiffPinnedHeader` přes výřez.
struct DiffView: View {
    let diff: Diff
    /// Co se kreslí — pull request (`owner/repo#číslo`), nebo commit v tabu `Commity`.
    ///
    /// **Není to dekorace, je to klíč ke krabici ploch pro tažení** (#274). Jeden `DiffView`
    /// obslouží všechny otevřené záložky, protože `@State` detailu přetéká mezi pull requesty —
    /// takže bez identity toho, co se kreslí, by se v `DiffRowFrames` vrstvily plochy každého
    /// prohlédnutého PR a zápis by s každou další záložkou zdražoval.
    let subject: String
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
    /// Hledání v diffu (#152). Stav drží store (musí přežít přepnutí tabu i složení panelu), tudy
    /// jdou akce. **Prázdné znamená „tady se nehledá“** — tak to má náhled i sonda.
    var search = DiffSearchActions()
    /// Značky `Prošlo` (#500). `nil` = tahle obrazovka je nemá — diff commitu (#317) ani rozsahový
    /// diff „co od minule přibylo“ (#284) nemluví o hlavě PR, takže by se jejich otisky se značkou
    /// nepotkaly. Zaškrtávátko, ✓ ve stromu ani počet v hlavičce se pak **nekreslí vůbec**.
    var read: DiffReadActions?

    /// Předvolba pohledu napříč pull requesty, takže patří do `UserDefaults`, ne do store.
    @AppStorage("showFindingBubbles") private var showBubbles = true
    /// Rozložený strom v levém sloupci (#197). Předvolba pohledu napříč PR, takže `UserDefaults`
    /// — a ne stav ve store, ze stejného důvodu jako u bublin.
    @AppStorage("diffTreeExpanded") private var isTreeExpanded = true
    /// Výška viditelné části diffu — z ní se počítá, kam skočí nález. Čte se jen měřením
    /// (`onGeometryChange`), takže do rozvržení nezasahuje: `GeometryReader` by naopak sám
    /// zabral místo a v tomhle okně už jednou nadělal škodu.
    @State private var viewportHeight = 0.0
    /// Co je cílem posledního skoku — z toho se počítá, kolik místa nad ním zůstane (#152).
    ///
    /// **Nastavuje se spolu s cílem a platí pro jeden skok**: `scrollTarget` je binding, do kterého
    /// píše i panel nálezů, a ten o hledání nic neví. Kdo cíl nastaví odjinud, dostane tedy
    /// `.bubble`, protože se hodnota po každém skoku vrací.
    @State private var jumpTarget = DiffJumpTarget.bubble
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
    /// Kde je výřez v obsahu (#469). Z něj si bloky berou pás, ve kterém se nasazují, a ukotvená
    /// hlavička polohu. Viz `DiffViewport` — dvě vlastnosti, protože každou čte někdo jiný a jinak
    /// často.
    @State private var viewport = DiffViewport()
    /// Kde v obsahu leží který soubor (#469). Krabice mimo observable stav; plní ji sekce, čte ji
    /// ukotvená hlavička.
    @State private var fileExtents = DiffFileExtents()

    /// Souřadnicový prostor **obsahu** diffu. Rámečky řádků i poloha myši při tažení se čtou
    /// v něm, takže scrollování s nimi nehýbe.
    static let contentSpace = "prism-diff-content"

    var body: some View {
        let _ = RenderDiagnostics.pass(Self.self)
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                toolbar
                // Pruh hledání (#152) — **druhá řádka chromu pod lištou**, přes celou šířku, tedy
                // i nad stromem: hledá se v celém diffu, ne v jednom souboru. Existuje jen
                // otevřený, takže lišta nad ním zůstává, jaká byla.
                //
                // Tělo diffu tím čte **jedinou** vlastnost hledání (`isOpen`), která se mění
                // dvakrát za hledání; dotaz ani počet výskytů si odsud nebere nikdo (#472).
                if let state = search.state, state.isOpen {
                    DiffSearchBar(search: state, actions: search) { direction in
                        step(search: direction)
                    }
                }
                // Strom vlevo, diff vedle něj (#197). Do té doby byl strom jen v popoveru,
                // takže u PR o padesáti souborech nešlo poznat, kde v něm člověk je, aniž by
                // ho otevřel.
                HStack(spacing: 0) {
                    tree(jumpingWith: proxy)
                    // **Rozměr se měří, nevyjednává** (#361) — jinak `HStack` posílá líným
                    // seznamem diffu svoje průzkumné dotazy na pružnost a `LazyVStack` na každý
                    // z nich odpovídá zápisem do svého stavu.
                    files.fillingSlot()
                }
            }
            .background(alignment: .topLeading) { treeShortcut }
            .background(alignment: .topLeading) { searchShortcut }
            .background(alignment: .topLeading) { readShortcut }
            // Stav hledání **prostředím** (#152), ne parametrem: dotaz se mění při každém písmenu
            // a čtou ho bloky kódu a hlavičky souborů, tedy listy hierarchie. Identita objektu se
            // nemění, takže tělo diffu se tím nepřekresluje — sledují se jeho **vlastnosti**, každou
            // čte někdo jiný (viz `DiffSearchState`). Tentýž vzorec jako u `DiffViewport`.
            .environment(search.state)
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
                // prvního — bez překladu `scrollTo` tiše nic neudělá. Od #152 se z téhož místa
                // bere i to, **kolikátý** ten řádek v bloku je: podíl výšky platí pro blok, takže
                // bez toho míří skok na blok a řádek v něm leží, kde leží.
                let spot = DiffRow.blockSpot(of: target, in: blockedRows(covering: target))
                proxy.scrollTo(spot.id, anchor: jumpAnchor(of: spot, metrics: measured(spot)))
                // **Podruhé o průchod později** (#469), a od #152 s **přeměřenými** rozměry.
                //
                // Ten první skok se totiž počítá z ploch, které bloky nahlásily **dosud** — a to
                // může být měření z doby, kdy se blok rozvrhoval na jinou šířku, tedy s jiným
                // zalomením. Změřeno: u souboru se zalomenými řádky přistál první skok 1 946 pt
                // vedle a druhý přesně. Je to **zmírnění, ne záruka**: kolik průchodů to sedne,
                // se řídit nedá, a čekat časovačem je zakázaná třída (#350).
                //
                // **Skok se u toho nechává neanimovaný.** Animovaný první průchod tenhle druhý
                // **utínal** a jeden skok z desítky pak skončil dva až třináct bodů od místa, kde
                // začal — to je ta „někdy se nescrolluje" z proklikání (změřeno, viz
                // `docs/testovani.md`). Je to změna proti #72 a je **vidět**.
                await Task.yield()
                // **Zrušený skok už nesrovnává nic** (nález z vlastní revize #152): `task(id:)`
                // starý průchod při změně cíle zruší, jenže `Task.yield()` z něj nevyskočí — takže
                // by ten starý dokončil posun na **svůj** cíl a nový by vzápětí **vynuloval**.
                guard !Task.isCancelled else { return }
                proxy.scrollTo(spot.id, anchor: jumpAnchor(of: spot, metrics: measured(spot)))
                scrollTarget = nil
                // Zpátky na výchozí druh cíle: příští skok může přijít z panelu nálezů, který
                // `jumpTarget` nenastavuje.
                jumpTarget = .bubble
            }
        }
    }

    /// Skok na další (nebo předchozí) výskyt hledání (#152).
    ///
    /// **Jde stejnou cestou jako skok na nález**: kotva se složí z `DiffRow` a nastaví se do
    /// `scrollTarget`, který si pak sám přeloží řádek na blok (`blockID(covering:)`). Sbalený soubor
    /// se **rozbalí dřív, než se cíl nastaví** — jinak by se ukázala jen jeho hlavička; tentýž
    /// požadavek jako u skoku ze stromu.
    ///
    /// Kotva se skládá **tady, ne ve store**: pohled na diff (`layout`) a rozbalený kontext ví
    /// jedině view, a ve split pohledu na tom identita řádku závisí.
    private func step(search direction: NavigationStep) {
        guard let hit = search.step(direction) else { return }
        guard let file = diff.file(at: hit.path) else { return }
        if folding.isFolded(file) { folding.toggle(file) }
        let state = expansion.state(file)
        // **Druh cíle se nastaví dřív než cíl sám**: `task(id:)` se spustí až po tomhle průchodu,
        // takže si vezme obojí naráz.
        jumpTarget = .searchHit
        scrollTarget = DiffRow.anchor(
            in: diff,
            hit: hit,
            layout: layout,
            revealed: state.revealed,
            content: state.content
        )
    }

    /// `⌘F` otevře pruh a zaostří pole. Bydlí **mimo lištu** ze stejného důvodu jako `⌘1` o kus níž:
    /// v liště je jen popisek `Hledat`, a ten otevírá kliknutím.
    ///
    /// Průhledné tlačítko, ne `.hidden()`: skryté view z hierarchie zmizí i se zkratkou.
    /// `⌘G`/`⌘⇧G` tady **nejsou** — registruje je pruh, takže existují jedině tehdy, když je kam
    /// skákat.
    @ViewBuilder private var searchShortcut: some View {
        // **Nad prázdným diffem se nenabízí, stejně jako popisek v liště**: pruh, ve kterém se
        // nedá nic najít, je zkratka, po které se nic nestane — a ta je k nerozeznání od rozbité
        // aplikace. Zakázané tlačítko klávesu nebere a propadne dál.
        if let open = search.open, !diff.files.isEmpty {
            Button("Hledat v diffu", action: open)
                .windowShortcut(.findInDiff)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Řádky souboru, ve kterém cíl leží, **už slité do bloků** — z nich se pozná, na co `scrollTo`
    /// míří a kolikátý řádek bloku to je (`DiffRow.blockSpot`). Prázdné, když ten soubor v diffu není.
    ///
    /// Skládá se **týmiž vstupy, jakými se ten soubor kreslí** (pohled, odkryté úseky, bubliny,
    /// vlákna, komentáře): kde se blok přeruší, na nich totiž závisí, a index poskládaný z jiných
    /// vstupů by ukazoval na blok, který v seznamu není. Počítá se jen při skoku, tedy jednou za
    /// kliknutí, a jen pro **jeden** soubor.
    private func blockedRows(covering target: String) -> [DiffRow] {
        // Porovnává se na **celé** `id`, ne na prefix: cesty se přejmenováním umí stát prefixem
        // jedna druhé (`src/A.php` a `src/A.php.bak`) a index by se pak skládal z cizího souboru.
        // Cíl je buď `file.id` sám (skok na hlavičku), nebo `file.id|<řádek>`.
        guard
            let file = diff.files.first(where: { target == $0.id || target.hasPrefix($0.id + "|") })
        else { return [] }
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
        return layout == .split ? DiffRow.blockedPairs(rows) : DiffRow.blocked(rows)
    }

    /// Kam v okně skočí cíl — **k vršku, ale s odstupem na kontext**. Kolik toho odstupu je
    /// a jak se z něj stane podíl výšky, rozhoduje `Policy` (`jumpOffset(of:viewport:)`
    /// a `jumpAnchorY(of:viewport:row:rowHeight:)`); tady se to jen složí do `UnitPoint`u.
    ///
    /// **Podíl se počítá z polohy řádku v bloku, ne z výšky výřezu** (#152) — jinak se posouvá blok
    /// a řádek v něm leží, kde leží. Čísla i zamítnutá varianta jsou u té funkce.
    ///
    /// Dokud výška výřezu nedorazí, platí střed — je to jediná hodnota, která nezávisí na tom, co
    /// ještě nevíme.
    private func jumpAnchor(of spot: DiffJumpSpot, metrics: DiffJumpMetrics?) -> UnitPoint {
        let size = metrics ?? Policy.jumpMetrics(of: spot, rowHeight: DiffTextView.rowHeight)
        guard let y = Policy.jumpAnchorY(of: jumpTarget, viewport: viewportHeight, metrics: size)
        else { return .center }
        return UnitPoint(x: 0, y: y)
    }

    /// Rozměry cíle **z toho, co bloky doopravdy nakreslily** (#152). `nil` = ten blok se ještě nikdy
    /// nekreslil, takže se rozměry dopočítají z výšky řádku.
    ///
    /// Bere se z `DiffRowFrames`, tedy z krabice, do které bloky hlásí plochy kvůli tažení rozsahu
    /// — **žádné měření navíc**: plochy tam leží od prvního rozvržení, kdy se nasadí i bloky mimo pás
    /// (#469). Jsou to plochy v souřadnicích obsahu, ale počítá se z nich jedině **rozdíl uvnitř
    /// bloku** a jeho výška, takže na posunu obsahu nezáleží.
    ///
    /// Kdyby se od posledního hlášení změnila **šířka** okna, může být záznam nemounted bloku
    /// zastaralý (jinak se zalamuje) a skok bude o ten rozdíl vedle — pořád ale blíž, než kam mířil
    /// odhad z počtu řádků.
    private func measured(_ spot: DiffJumpSpot) -> DiffJumpMetrics? {
        guard let block = rowFrames.block(spot.id), block.height > 0 else { return nil }
        // Ve split pohledu nese plocha řádku ještě stranu; svisle jsou obě zarovnané, takže
        // rozhoduje ta, která se najde.
        let keys = ["\(spot.id)l\(spot.above)"]
            + [DiffSide.right, .left].map { "\(spot.id)l\(spot.above)|\($0.rawValue)" }
        guard let row = keys.lazy.compactMap({ rowFrames.rect(of: $0) }).first else { return nil }
        return DiffJumpMetrics(above: row.minY - block.minY, height: block.height)
    }

    /// Každý **řádek** je vlastní buňka seznamu, ne každý hunk. Hunk jako celek se po změně šířky
    /// okna překresloval jen zčásti a v diffu zůstávala prázdná místa.
    ///
    /// **Pevný `VStack`, ne `LazyVStack` — a je to oprava #469, ne úspora.** Líný seznam zapisuje
    /// při umisťování položek do grafu, ze kterého sám čte, a to kolo se nemá kde zastavit; u osy
    /// konverzace to vyřešilo #361 týmž způsobem a kolo se přestěhovalo sem. Laznost tím ale
    /// nezmizela, jen se přestěhovala z rozvržení do jednoho rozhodnutí: blok kódu se nasazuje jen
    /// v pásu kolem výřezu (`DiffBlockSlot`, `Policy.mountBand(visible:)`). Bez toho by pevný
    /// stack diff položil — čísla jsou u té funkce.
    private var files: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(diff.files, id: \.diagnosedID) { file in
                    DiffFileSection(extents: fileExtents, fileID: file.id) {
                        fileHeader(file)
                    } content: {
                        // Sbalený soubor se nevykresluje vůbec — u padesátisouborového PR
                        // je to hlavní důvod, proč se sbaluje. Hlavička zůstává, takže
                        // sekce nezmizí a skok na soubor pořád funguje.
                        if !folding.isFolded(file) {
                            rows(of: file)
                        }
                    }
                    .id(file.id)
                }
            }
            .coordinateSpace(.named(Self.contentSpace))
        }
        // **Jediné místo, kam se scrollování zapisuje** (#469). Pás se mění jednou za výřez a čtou
        // ho všechny bloky; `top` se mění při každém snímku a čte ho jenom ukotvená hlavička.
        .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, visible in
            let band = Policy.mountBand(visible: visible)
            if viewport.band != band { viewport.band = band }
            if viewport.top != visible.minY { viewport.top = visible.minY }
        }
        // Výřez do prostředí, ne parametrem: prochází přes `DiffRowView` až do slotu bloku
        // a cesta k němu je dlouhá. Identita objektu se nemění, takže tělo diffu se tím
        // nepřekresluje — sledují se jeho **vlastnosti**, každou čte někdo jiný (viz `DiffViewport`).
        .environment(viewport)
        // Ukotvená hlavička souboru — jedna, přes výřez. Do #469 to dělal
        // `LazyVStack(pinnedViews:)`; proč se to kreslí takhle, je u `Policy.pinnedFileHeader`.
        .overlay(alignment: .topLeading) {
            DiffPinnedHeader(files: diff.files, extents: fileExtents, viewport: viewport) {
                fileHeader($0)
            }
        }
        // Jen měření, žádný vliv na rozvržení — proto `onGeometryChange` a ne `GeometryReader`.
        .onGeometryChange(for: CGSize.self) {
            RenderDiagnostics.inGraph(.viewportGeometry)
            return $0.size
        } action: {
            viewportHeight = $0.height
            contentWidth = $0.width
        }
        .sheet(item: $codeText) { CodeTextSheet(content: $0) }
        // Rozsahy i změřené výšky bloků patří **tomuhle** diffu: `@State` detailu přetéká mezi
        // pull requesty, takže by se jinak držely hodnoty z PR, který v okně dávno není — a řádek
        // se stejnou identitou (`CLAUDE.md|174` má každý druhý PR) by dostal cizí výšku.
        .onChange(of: subject, initial: true) {
            fileExtents.reset(for: subject)
            viewport.generation += 1
        }
    }

    /// Hunk jako text k vybírání. Kód se skládá **stejnou funkcí jako pro schránku**
    /// (`Policy.code(of:)`), takže se vybraný text nemůže rozejít s tím, co dá `Kopírovat hunk`.
    ///
    /// Hlavička se skládá tady, ne v sheetu (#417): sheet nemá znát `DiffHunk` ani to, co se
    /// zrovna kreslí — a `subject` je jediné místo, kde je vidět, jestli je diff z pull requestu,
    /// nebo z jednoho commitu.
    private func codeText(of hunk: DiffHunk, in file: FileDiff) -> CodeText {
        let code = Policy.code(of: hunk)
        return CodeText(
            kind: .hunk,
            id: "\(file.displayPath)#\(hunk.header)",
            title: CodeSheetText.hunkTitle(path: file.displayPath),
            slug: CodeSheetText.hunkSlug(header: hunk.header, subject: subject),
            note: CodeSheetText.hunkNote(code: code),
            path: file.displayPath,
            code: code,
            link: nil
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
        // **Tažení a kopírování se skládají jednou za soubor, ne za řádek** — tentýž důvod jako
        // u kotev a rozsahů nad tímhle řádkem: ani jeden z těch osmi uzávěrů na řádku nezávisí,
        // všechny berou soubor a to, co dostanou parametrem. Při přepnutí tabu se přitom všechny
        // řádky skládají znovu (294 průchodů tělem `DiffRowView` u 2000řádkového diffu), takže
        // je to 8 uzávěrů na soubor místo 2 352.
        //
        // **Na ceně to ale změřit nešlo** (#472): přepnutí tabu vyšlo 407 / 682 ms proti
        // 428 / 602 ms před úpravou, tedy uvnitř rozptylu — cenu drží rozvržení, ne skládání
        // řádků. Zůstává to proto jako **kratší kód**, ne jako zlevnění.
        let rangeDrag = RangeDragActions(
            box: .init(frames: rowFrames, subject: subject),
            move: { draft.dragRange(file.displayPath, $0, $1) },
            end: draft.endRangeDrag
        )
        // Kopírování (#157) se skládá **až při otevření menu**: text rozsahu se hledá přes
        // všechny hunky, takže při vykreslení každého řádku by to byla práce navíc u operace,
        // kterou nikdo nevyvolal. Rozsahy se berou z **mých rozdělaných** komentářů — tažení už
        // je vybírá a zvýrazňuje, jen se s nimi dosud dala udělat jediná věc.
        let copy = DiffCopyActions(
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
        let reveal: (ClosedRange<Int>) -> Void = { expansion.reveal(file, $0) }
        return ForEach(
            layout == .split ? DiffRow.blockedPairs(rows) : DiffRow.blocked(rows),
            id: \.diagnosedID
        ) { row in
            DiffRowView(
                row: row,
                language: language,
                layout: layout,
                isLoadingContent: state.isLoading,
                contentFailure: state.failure,
                reveal: reveal,
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
                rangeDrag: rangeDrag,
                copy: copy,
                // Cesta souboru, ne dotaz hledání (#152): dotaz si blok přečte z prostředí sám,
                // takže se tělo diffu při psaní nepřekresluje. Odsud jde jen to, co se mění
                // se **souborem**, tedy jednou za jeho vykreslení.
                filePath: file.displayPath
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
            contentWidth: contentWidth,
            // `nil`, když hledání nikdo nedodal (náhledy, sondy) — popisek se pak nekreslí, místo
            // aby otevíral pruh, který nemá kde vzniknout.
            openSearch: search.open,
            isSearching: search.isOpen
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
        .windowShortcut(.fileTree)
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
                    // `7 SOUBORŮ · 3 PROŠLÉ` (#500) — druhá polovina se objeví, teprve když má
                    // co říct. Skládá ji `Policy`, ať se počet v hlavičce nemůže rozejít s tím,
                    // co je v seznamu pod ní.
                    Text(verbatim: Policy.fileTreeSummary(
                        files: diff.files.count,
                        read: readFileCount
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
                    .help(Policy.shortcutHelp("Složit strom souborů", .fileTree))
                    .accessibilityLabel("Složit strom souborů")
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }

                readProgress

                FileTreeView(
                    files: diff.files,
                    markers: fileMarkers,
                    readStates: read?.states ?? [:]
                ) { file in
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
            .help(Policy.shortcutHelp("Rozložit strom souborů", .fileTree))
            .accessibilityLabel("Rozložit strom souborů")
        }
    }

    /// Kolik souborů je prošlých (#500). Nula, když značky tahle obrazovka nemá.
    private var readFileCount: Int {
        Policy.readFileCount(in: read?.states ?? [:])
    }

    /// Tenký proužek podílu pod hlavičkou stromu (#500) — 3 body, `--ok` na `--panel-3`, jak ho
    /// má návrh (sekce 40).
    ///
    /// **Nekreslí se, dokud není zaškrtnuté nic**: prázdná linka nad nezapočatým PR je stálý prvek
    /// bez informace. `Policy` na to odpovídá `nil`em, ne nulou — tady se jen rozhoduje, co to
    /// znamená v kresbě.
    @ViewBuilder private var readProgress: some View {
        if let share = Policy.readFileShare(read: readFileCount, of: diff.files.count) {
            // **Šířka se počítá, nevyjednává** (#220): proužek zná šířku sloupce, takže se podíl
            // dá vyjádřit rámečkem, ne pružností.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Palette.ok)
                    .frame(width: (Self.treeWidth - 26) * share)
                Spacer(minLength: 0)
            }
            .frame(height: 3)
            .background(Palette.raised)
            .clipShape(.rect(cornerRadius: 2))
            .padding(.horizontal, 13)
            .padding(.top, 7)
            .accessibilityLabel(Text(verbatim: Policy.fileTreeSummary(
                files: diff.files.count,
                read: readFileCount
            )))
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
            toggle: { folding.toggle(file) },
            read: read.map { $0.state(of: file) },
            toggleRead: read.map { actions in { actions.toggle(file) } }
        )
    }

    /// `⌥V` na soubor, jehož hlavička je zrovna **ukotvená nahoře** (#500).
    ///
    /// **Vlastní malé view, ne zkratka na zaškrtávátku v hlavičce**, a je to podmínka: hlaviček
    /// je v diffu tolik co souborů, takže by tutéž kombinaci registrovalo padesát tlačítek —
    /// a to je přesně ten stav, kdy vyhraje to zaregistrované později a ostatní „nefungují“
    /// (#151, #184). Zkratka proto visí na jednom průhledném tlačítku.
    ///
    /// Čte `viewport.top`, tedy hodnotu, která se mění při každém otočení kolečka — proto **vlastní
    /// view a ne kus těla `DiffView`u**, ze stejného důvodu jako `DiffPinnedHeader`: tělo diffu
    /// skládá řádky všech souborů a překládat ho při každém snímku je zakázaná třída (#469).
    ///
    /// Bez ukotveného souboru (rozsahy ještě nikdo nezměřil) je tlačítko **zakázané** — a zakázané
    /// klávesu nebere, takže propadne dál, místo aby zaškrtlo něco jiného, než na co se člověk dívá.
    @ViewBuilder private var readShortcut: some View {
        if let read {
            DiffReadShortcut(
                files: diff.files,
                extents: fileExtents,
                viewport: viewport,
                toggle: read.toggle
            )
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
}
