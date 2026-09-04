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
    /// Levý sloupec s itinerářem, jak ho automatika pohledu (#188) smí přepnout — **od toho, kdo
    /// ho kreslí** (#506, třetí kolo). `nil` = vedle téhle plochy sloupec nestojí, takže se ho
    /// automatika nedotkne; tatáž hranice jako u `panelExpanded` o řádku výš.
    ///
    /// **Rozhodnutí zůstává tady, stav i stráž jsou venku.** Podlaha, kvůli které se sloupec
    /// skládá, je podlaha **kolony kódu** (`Policy.minimumCodeWidth`), a ta existuje jedině
    /// v diffu — kdežto stav sloupec přežívá v `UserDefaults` a stráž proti druhému uplatnění
    /// musí přežít stejně dlouho. Proč, je u `DiffColumnActions`.
    var columnActions: DiffColumnActions?
    var stepFinding: ((NavigationStep) -> Void)?
    /// Hledání v diffu (#152). Stav drží store (musí přežít přepnutí tabu i složení panelu), tudy
    /// jdou akce. **Prázdné znamená „tady se nehledá“** — tak to má náhled i sonda.
    var search = DiffSearchActions()
    /// Značky `Prošlo` (#500). `nil` = tahle obrazovka je nemá — diff commitu (#317) ani rozsahový
    /// diff „co od minule přibylo“ (#284) nemluví o hlavě PR, takže by se jejich otisky se značkou
    /// nepotkaly. Zaškrtávátko, ✓ ve stromu ani počet v hlavičce se pak **nekreslí vůbec**.
    var read: DiffReadActions?
    /// Výřez a rozsahy souborů **zvenku** (#501). `nil` = na tuhle obrazovku se nikdo odjinud
    /// nedívá (diff commitu, náhled), takže si je diff drží sám.
    ///
    /// Existuje kvůli mapě PR: ta leží **nad pruhem záložek**, tedy mimo `DiffView`, a ptá se na
    /// tutéž věc jako ukotvená hlavička souboru — který soubor drží horní hranu. Předat jednu
    /// krabici je proti tomu levnější než druhé měření: rozsahy se zapisují z geometrie sekcí
    /// a dvě místa, která je počítají, by se rozešla (#236).
    var tracking: DiffTracking?
    /// Kde stojí kurzor procházení nálezů (#187). Karta v okraji na tom místě dostane rámeček,
    /// takže okraj a lišta ukazují **totéž** — bez toho by po `⌥↓` nebylo poznat, o které kartě
    /// lišta mluví. Do #503 to potřeboval jen panel, protože v diffu se o kurzoru dozvěděl skok.
    var current: FindingPlace?
    /// Kam hlásit, kde stojí výřez (#527) — z toho se skládá kotva scrollu v `tabs.json`.
    /// `nil` = **tuhle obrazovku nikdo neobnovuje**, takže se ani nepočítá: diff commitu (#317),
    /// rozsahový diff (#284) ani náhled o pull requestu nic neukládají.
    var reportScrollAnchor: ((DiffScrollAnchor?) -> Void)?
    /// Kam hlásit, že výřez dojel na konec obsahu (#507) — z toho si mezerník bere klávesu.
    /// `nil` = **tuhle obrazovku nikdo neposlouchá**, takže se ani neměří: rozsahový diff (#284),
    /// diff commitu (#317) ani náhled o itineráři nic neříkají.
    var reportContentEnd: ((Bool) -> Void)?

    /// Šířka, kterou diff dostal — okno bez railu, **bez levého sloupce** a bez panelu vpravo
    /// (#220, od #506 bez sloupce). Odsud se počítá kolona kódu; o kolonách samotných rozhoduje
    /// ten, kdo je kreslí (detail PR).
    @Environment(\.availableWidth) private var slotWidth
    /// Šířka, o kterou se dělí levý sloupec, kolona kódu a okraj (#506) — **od toho, kdo sloupec
    /// kreslí**, tedy od detailu PR. `nil` = vedle téhle plochy sloupec nestojí, takže se dělí
    /// tím, co dostala. Proč se to nedopočítává tady, je u `SideColumnsWidthKey`.
    @Environment(\.sideColumnsWidth) private var sharedWidth
    /// Kreslit nálezy jako bubliny **pod** jejich řádkem? **Od #548 zapnuto**, tedy zpátky to, co
    /// platilo do #503: okraj vpravo si bere 300 bodů natrvalo — i v souboru bez nálezu, což je
    /// skoro pořád —, kdežto bublina zabere místo jen tam, kde nález doopravdy je, a svisle, kde
    /// je ho dost. Okraj zůstává **za přepínačem** `Nálezy pod řádky` v liště.
    ///
    /// **Klíč se nepřejmenovává, i když se u #503 přejmenoval** (`showFindingBubbles` do #503,
    /// `showInlineFindingBubbles` od té doby). Tehdy se otočil **význam hodnoty** — zapnuto přešlo
    /// z „takhle to má být“ na „chci to po starém“ —, takže se starý klíč zahodit musel. Teď se
    /// otáčí jen **výchozí hodnota**: `true` pořád znamená bubliny a `false` pořád okraj. Uložená
    /// hodnota je tedy dál platná odpověď a přejmenovat klíč by znamenalo zahodit volbu toho,
    /// kdo si okraj vědomě nechal.
    ///
    /// Předvolba pohledu napříč pull requesty, takže patří do `UserDefaults`, ne do store.
    @AppStorage("showInlineFindingBubbles") private var showBubbles = true
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
    /// Které rozhodnutí o postranních kolonách už automatika provedla (#188, od #503 i okraj),
    /// **když si tu stráž nikdo nedrží zvenku** (#506/3). Bez ní by se rozhodnutí opakovalo při
    /// každém vzniku view a přebíjelo ruční `⌘1`/`⌘2`.
    ///
    /// Vzniká jednou na identitu view — tedy `columnActions == nil` znamená přesně to, co platilo
    /// do #506/3: diff si stráž drží sám a s ním zaniká. Tentýž vzorec jako `ownTracking` (#501).
    @State private var ownAppliedColumns: DiffSideColumns?
    /// Rámečky řádků pro tažení rozsahu (#110). `@State`, aby přežily překreslení; obsah je
    /// mimo observable stav, takže se jimi diff nepřekresluje — viz `DiffRowFrames`.
    @State private var rowFrames = DiffRowFrames()
    /// Hunk otevřený jako text k vybírání (#157). Sheet drží diff, protože je nad celým seznamem
    /// řádků — a `nil` znamená, že žádný otevřený není.
    @State private var codeText: CodeText?
    /// Výřez a rozsahy souborů, když si je nikdo nepředává (#501). Vzniká jednou na identitu
    /// view, takže `tracking == nil` znamená přesně to, co bylo do #501: diff si obojí drží sám.
    @State private var ownTracking = DiffTracking()

    /// Kde je výřez v obsahu (#469). Z něj si bloky berou pás, ve kterém se nasazují, a ukotvená
    /// hlavička polohu. Viz `DiffViewport` — dvě vlastnosti, protože každou čte někdo jiný a jinak
    /// často.
    private var viewport: DiffViewport { (tracking ?? ownTracking).viewport }
    /// Kde v obsahu leží který soubor (#469). Krabice mimo observable stav; plní ji sekce, čte ji
    /// ukotvená hlavička.
    private var fileExtents: DiffFileExtents { (tracking ?? ownTracking).extents }
    /// Stráž proti druhému uplatnění rozhodnutí o kolonách — **od toho, kdo sloupec kreslí**, a jen
    /// když tam takový někdo je (#506/3). Viz `ownAppliedColumns`.
    private var appliedColumns: Binding<DiffSideColumns?> {
        columnActions?.applied ?? $ownAppliedColumns
    }
    /// Kde v obsahu leží řádky s kartou v okraji (#503). **Jediná sledovaná krabice v diffu** —
    /// z téhle se kreslí, viz `DiffMarginAnchors`.
    @State private var marginAnchors = DiffMarginAnchors()

    /// Souřadnicový prostor **obsahu** diffu. Rámečky řádků i poloha myši při tažení se čtou
    /// v něm, takže scrollování s nimi nehýbe.
    static let contentSpace = "prism-diff-content"

    var body: some View {
        let _ = RenderDiagnostics.pass(Self.self)
        // **Karty se skládají jednou za průchod**, ne jednou za soubor a ještě raz pro okraj:
        // vybírají se hledáním řádku v hunkách, takže dvě složení znamenají dvojí průchod diffem
        // — a hlavně dvě odpovědi na to, které karty v okraji jsou.
        let cards = marginCards
        // Rozhodnutí o postranních kolonách se skládá **jednou** a slouží dvakrát: je to identita
        // `task`u níž **i** hodnota, kterou uplatní. Dvě složení jedné odpovědi jsou dvě odpovědi.
        //
        // **Ptá se na společnou šířku, ne na tu svoji** (#506): sloupec od #506 odečítá rozvržení
        // detailu PR, takže `slotWidth` je štěrbina, ve které už není — a rozhodnutí o sloupci by
        // se jinak dělalo podle toho, co po sloupci zbylo, tedy samo podle sebe. Kdo sloupec vedle
        // sebe nemá, `sharedWidth` nedodá a dělí se tím, co dostal.
        let columns = Policy.diffSideColumns(
            layout: layout,
            hasMargin: !cards.isEmpty,
            available: (sharedWidth ?? slotWidth).map(Double.init)
        )
        // Šířka kolony kódu se **předává** (#546, pravidlo #220): plocha, na kterou se sází, je
        // štěrbina bez okraje a bez mezery před ním — a ta se dá spočítat, takže se
        // nemá co měřit. Do #546 si ji obsah bral z `onGeometryChange` a měřil něco jiného.
        let code = Policy.diffCodeColumnWidth(available: slotWidth.map(Double.init), columns: columns)
        // Diagnostika kreslení (#546): na čem scéna doopravdy stojí. Vypnutá stojí jeden load
        // `Optional`u; viz `WidthSite`.
        let _ = slotWidth.map { RenderDiagnostics.measured(.diffSlot, Double($0)) }
        let _ = code.map { RenderDiagnostics.measured(.diffCodeColumn, $0) }
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                toolbar(codeWidth: code)
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
                // Kód a vedle něj okraj s kartami (#503). **Levý sloupec tady od #506 není** —
                // itinerář stojí vedle všech tabů, takže ho hostí detail PR a diff dostane
                // štěrbinu, ve které už není. Do té doby byl součástí tohohle `HStack`u a mizel
                // s přepnutím tabu.
                HStack(spacing: 0) {
                    // **Rozměr se měří, nevyjednává** (#361) — jinak `HStack` posílá líným
                    // seznamem diffu svoje průzkumné dotazy na pružnost a `LazyVStack` na každý
                    // z nich odpovídá zápisem do svého stavu.
                    // **Kolona kódu je vlastní štěrbina, a musí to vědět i podstrom** (#546).
                    // Do #546 tady zůstávala štěrbina **celého tabu**, takže se všechno, co si
                    // šířku bere z prostředí (`filling()` — v diffu bublina vlákna), přibilo na
                    // okno bez railu a panelu, tedy o strom, okraj a mezeru **širší**, než jaké
                    // místo dostalo. `ScrollView` se v nescrollované ose velikostí řídí obsahem,
                    // takže z toho byla plocha širší než kolona — a ta se centrovala, tedy vylila
                    // **doleva** přes rail. Změřeno v okně 1100: kolona 970 b, obsah 1110 b.
                    files(cards: cards)
                        .availableWidth(code.map { CGFloat($0) } ?? slotWidth)
                        // **Zarovnání doleva, ne na střed** (#546). Ve zdravém stavu na něm
                        // nezáleží (plocha má přesně tu velikost, kterou dostala); rozhoduje
                        // teprve tehdy, když si obsah vezme víc — a pak je rozdíl mezi „ořízne se
                        // vpravo, kde je okraj“ a „vyleze doleva přes rail a sežere čísla řádků“.
                        // **Vadu to neschovává**: šířka té plochy se pořád dá změřit a přeteklá je
                        // pořád jiná než kolona, takže na ni test vidí (`DiffCodeColumnWidthTests`).
                        .fillingSlot(alignment: .topLeading)
                        // **Vzduch mezi kódem a tím, co je vpravo** (#503). Mimo `fillingSlot`,
                        // takže se ta mezera odečte od štěrbiny — a `Policy.diffCodeColumnWidth`
                        // ji odečítá taky, aby předaná šířka byla ta, kterou `HStack` doopravdy dá.
                        .padding(.trailing, Policy.codeColumnTrailingGap)
                    // Okraj s kartami nálezů (#503) — třetí kolona z návrhu
                    // (`210px 1fr 300px`), a **jen když je co do ní postavit**: okraj bez karet
                    // je ubraná šířka bez informace.
                    margin(cards: columns.margin ? cards : [])
                }
            }
            .background(alignment: .topLeading) { searchShortcut }
            .background(alignment: .topLeading) { readShortcut }
            .background(alignment: .topLeading) { anchorReporter }
            // Stav hledání **prostředím** (#152), ne parametrem: dotaz se mění při každém písmenu
            // a čtou ho bloky kódu a hlavičky souborů, tedy listy hierarchie. Identita objektu se
            // nemění, takže tělo diffu se tím nepřekresluje — sledují se jeho **vlastnosti**, každou
            // čte někdo jiný (viz `DiffSearchState`). Tentýž vzorec jako u `DiffViewport`.
            .environment(search.state)
            // **Pohled vedle sebe složí postranní kolony** (#188). Řádek se v něm dělí na dvě
            // strany, takže na 14" nezbude ani 100 znaků; pod sebou je zase rozbalí. Ruční
            // `⌘1`/`⌘2` to přebijí jednoduše tím, že platí až do **další** změny pohledu.
            //
            // `task(id:)`, ne `onChange`: pohled se drží napříč pull requesty (a výchozí je
            // z nastavení), takže s `onChange` by se na PR otevřeném rovnou ve splitu nesložilo
            // nic — změna nepřišla. `task(id:)` se spustí i při vzniku.
            //
            // **Identita je samo rozhodnutí, ne jeho vstupy** (#503): `task` má běžet tehdy, když
            // z `Policy` vyjde něco jiného než minule — a to je od #503 i tím, že se objevil
            // okraj s kartami.
            //
            // **Sloupec se odsud pořád přepíná, i když ho kreslí detail** (#506) — ale stav i stráž
            // jsou od #506/3 **jeho** (`columnActions`), ne diffu. Do té doby tady stál druhý
            // `@AppStorage` nad klíčem `diffTreeExpanded` a stráž ve `@State`, kterou přepnutí tabu
            // zahodilo: každý návrat do `Změněných souborů` byl nový `DiffView`, který uplatnil
            // rozhodnutí podruhé a přepsal tím volbu člověka. Viz `DiffColumnActions`.
            //
            // **A od #506/4 se uplatňuje jen to pole, které se změnilo** (`Policy.sideColumnsToApply`).
            // Do té doby se zapisovalo obojí, jakmile se rozhodnutí změnilo v čemkoli — a `margin`
            // se mění při kliknutí na `Nálezy pod řádky`, při sbalení souboru i při odkrytí kontextu,
            // takže tyhle kliky přepisovaly uloženou volbu u sloupce. Změřeno v uživatelově okně,
            // kde se žádná šířková mez nepřekračuje.
            .task(id: columns) {
                // **Jen jednou na rozhodnutí.** `task(id:)` se spustí i při novém vzniku view —
                // a to nastane pokaždé, když se přepne panel vpravo (přestaví se `HStack` v detailu
                // PR) i při každém návratu do tabu s diffem. Bez téhle stráže se ručně otevřený
                // sloupec hned zase složil a nešel otevřít vůbec.
                // **Kdo nemá co přepnout, nezapisuje ani stráž** (#506/3): diff commitu (#317)
                // a náhledy nedostanou ani sloupec, ani panel, takže by tady jinak vznikl zápis do
                // `@State`, který nikdo nepřečte — a s ním průchod tělem při každé změně šířky.
                guard columnActions != nil || panelExpanded != nil else { return }
                guard appliedColumns.wrappedValue != columns else { return }
                // **Stráž se posune i tehdy, když se neuplatní nic** — je to záznam „takhle
                // `Policy` rozhodla naposledy“, ne „takhle jsem naposledy zapsal“. Bez toho by
                // se změna v `margin` porovnávala proti zastaralému základu a příští skutečná
                // změna `tree` by se od něj spočítala špatně.
                let update = Policy.sideColumnsToApply(
                    applied: appliedColumns.wrappedValue,
                    columns: columns
                )
                appliedColumns.wrappedValue = columns
                guard !update.isEmpty else { return }
                withAnimation(.snappy(duration: 0.15)) {
                    if let tree = update.tree { columnActions?.expanded.wrappedValue = tree }
                    if let panel = update.panel { panelExpanded?.wrappedValue = panel }
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
                // **Druh cíle se pozná z cíle, ne z toho, kdo ho nastavil** (#506). Od #506
                // nastavuje cíl i sloupec s itinerářem, který stojí mimo `DiffView` — takže by mu
                // `jumpTarget` v `@State` diffu nebyl k ničemu.
                let kind = Policy.jumpTarget(of: target, files: diff.files, requested: jumpTarget)
                proxy.scrollTo(spot.id, anchor: jumpAnchor(of: spot, kind: kind, metrics: measured(spot)))
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
                proxy.scrollTo(spot.id, anchor: jumpAnchor(of: spot, kind: kind, metrics: measured(spot)))
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
            findings: findings,
            inlineFindings: showBubbles,
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
    private func jumpAnchor(
        of spot: DiffJumpSpot,
        kind: DiffJumpTarget,
        metrics: DiffJumpMetrics?
    ) -> UnitPoint {
        let size = metrics ?? Policy.jumpMetrics(of: spot, rowHeight: DiffTextView.rowHeight)
        guard let y = Policy.jumpAnchorY(of: kind, viewport: viewportHeight, metrics: size)
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
    private func files(cards: [DiffMarginCard]) -> some View {
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
                            rows(of: file, cards: cards)
                        }
                    }
                    .id(file.id)
                }
            }
            .coordinateSpace(.named(Self.contentSpace))
        }
        // Dojel výřez na konec? (#507) Druhý posluchač geometrie vedle toho níž schválně: ten
        // počítá pás nasazení a horní hranu, tohle je jeden `Bool`, který se mění na přechodu —
        // slít je do jedné hodnoty by znamenalo hlásit `top` i tomu, kdo se ptá na konec.
        .reportsContentEnd(reportContentEnd)
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
            // **Šířka se odsud už nikam nezapisuje** (#546). Do #546 z ní byl `contentWidth` pro
            // ukazatel „znaků na stranu“, jenže je to velikost **plochy**, a ta je při přeteklém
            // obsahu větší než kolona — v okně 1512 z ní vyšlo 84 znaků nad kolonou, do které se
            // jich vejde 62. Ukazatel proto bere šířku předanou (`Policy.diffCodeColumnWidth`)
            // a tohle zbylo jako **měřidlo do diagnostiky**: rozdíl proti spočítané koloně je celá
            // #546 a bez něj by ho nebylo z čeho přečíst.
            RenderDiagnostics.measured(.diffMeasuredContent, $0.width)
        }
        .sheet(item: $codeText) { CodeTextSheet(content: $0) }
        // Rozsahy i změřené výšky bloků patří **tomuhle** diffu: `@State` detailu přetéká mezi
        // pull requesty, takže by se jinak držely hodnoty z PR, který v okně dávno není — a řádek
        // se stejnou identitou (`CLAUDE.md|174` má každý druhý PR) by dostal cizí výšku.
        .onChange(of: subject, initial: true) {
            fileExtents.reset(for: subject)
            // Polohy karet patří **tomuhle** diffu ze stejného důvodu (#274): klíč `CLAUDE.md|174`
            // má kdejaký PR, takže by karta v novém PR chvíli stála tam, kde byl řádek v tom
            // předchozím. Bloky se po přepnutí ohlásí znovu, takže se nová poloha má kde vzít.
            marginAnchors.reset()
            viewport.generation += 1
        }
    }

    /// Okraj vpravo s kartami nálezů (#503).
    ///
    /// **Bez karet se nekreslí vůbec**, ani jako prázdná kolona: tři sta bodů bez informace ubírá
    /// diffu šířku, o které #182 spočítalo, že ji potřebuje. Prázdný okraj by navíc vypadal jako
    /// druhý složený panel.
    @ViewBuilder private func margin(cards: [DiffMarginCard]) -> some View {
        if !cards.isEmpty {
            DiffMarginView(
                cards: cards,
                anchors: marginAnchors,
                viewport: viewport,
                // **Změřená výška, ne pružný rámec** (#220): `viewportHeight` je plocha, kterou
                // dostal diff, tedy přesně tolik, kolik má mít okraj vedle něj.
                height: viewportHeight,
                blockingCategories: blockingCategories,
                findingActions: findingActions,
                drafts: marginDrafts(for: cards),
                highlighted: highlighted,
                current: current
            )
        }
    }

    /// Karty do okraje. Rozhoduje `Policy` nad daty — `nil` vstup (zapnuté bubliny pod řádky) je
    /// **prázdný okraj**, ne okraj s prázdnými kartami: obojí naráz by znamenalo tentýž nález na
    /// obrazovce dvakrát, tedy zrovna to, co #503 ruší.
    private var marginCards: [DiffMarginCard] {
        guard !showBubbles, !findings.isEmpty else { return [] }
        return Policy.marginCards(
            of: findings,
            in: diff.files.map { file in
                let state = expansion.state(file)
                return DiffMarginSource(
                    file: file,
                    // Tatáž úvaha jako v `DiffRow.rows`: bez obsahu není co odkrývat, takže by se
                    // karta kotvila na řádek, který se nekreslí.
                    revealed: state.content.isEmpty ? RevealedLines() : state.revealed,
                    isFolded: folding.isFolded(file)
                )
            },
            categories: blockingCategories
        )
    }

    /// Akce draftu pro soubory, ve kterých karta je — **jednou za soubor, ne za kartu**, a
    /// s **líně hledanými kotvami** (`bound(lazilyTo:)`): karta se draftu ptá jedině na nález,
    /// takže složit kotvy všech komentovatelných řádků by byl průchod hunky, který nikdo nepřečte.
    private func marginDrafts(for cards: [DiffMarginCard]) -> [String: FileDraftActions] {
        var result: [String: FileDraftActions] = [:]
        for path in Set(cards.map(\.path)) {
            guard let file = diff.files.first(where: { $0.displayPath == path }) else { continue }
            result[path] = draft.bound(lazilyTo: file)
        }
        return result
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

    private func rows(of file: FileDiff, cards: [DiffMarginCard]) -> some View {
        let state = expansion.state(file)
        let language = Language(path: file.displayPath)
        // Značky pruhů **jednou za soubor**, ne za řádek: je to překlad karet na čísla řádků
        // a bloky si z něj vybírají podle svých rámečků — tentýž důvod jako u kotev pod tímhle
        // řádkem. Prázdné, když se okraj nekreslí.
        let marks = Policy.marginMarks(of: cards, in: file.displayPath)
        // Řádky se před vykreslením slijí do bloků (#157), aby v nich šlo vybírat text přes víc
        // řádků — v obou pohledech. Ve split se slévají **dvojice** (`blockedPairs`) do dvou
        // sloupců, které si odpovídají řádek po řádku; podrobnosti u `DiffPairBlockView`.
        let rows = DiffRow.rows(
            of: file,
            layout: layout,
            revealed: state.revealed,
            content: state.content,
            findings: findings,
            // Zakotvený nález jde pod řádek, dokud si někdo nepřepne okraj (#548) — pak stojí
            // v okraji. Nález **bez řádku** se tím neřídí a visí u hlavičky souboru vždycky:
            // v okraji se nemá k čemu zarovnat, takže by jinak zmizel.
            inlineFindings: showBubbles,
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
                filePath: file.displayPath,
                marginMarks: marks,
                // Krabice jedině tehdy, když se okraj kreslí: blok, který nemá kam hlásit, si
                // hlášení odpustí celé (`noteMargin`).
                marginAnchors: marks.isEmpty ? nil : marginAnchors
            )
        }
    }

    /// Lišta nad diffem.
    ///
    /// **Šířka kolony přichází parametrem, ne z počítané vlastnosti** (#546): skládá se z karet
    /// v okraji (`marginCards`) a ty se smí složit **jednou za průchod** — dvě složení jsou dvě
    /// odpovědi na to, které karty v okraji jsou (viz `body`).
    private func toolbar(codeWidth: Double?) -> some View {
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
            // **Předaná šířka kolony, ne změřená plocha** (#546): měřená plocha je při přeteklém
            // obsahu širší než kolona, takže by ukazatel sliboval sloupec, který na obrazovce není.
            // `0` znamená „štěrbinu nikdo nezměřil“ a ukazatel se pak nekreslí vůbec — `DiffView`
            // hostovaný mimo okno (náhledy) o šířce nemá co tvrdit.
            contentWidth: codeWidth ?? 0,
            // `nil`, když hledání nikdo nedodal (náhledy, sondy) — popisek se pak nekreslí, místo
            // aby otevíral pruh, který nemá kde vzniknout.
            openSearch: search.open,
            isSearching: search.isOpen
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

    /// Hlášení polohy výřezu pro kotvu scrollu (#527).
    ///
    /// **Vlastní view a ne kus těla `DiffView`u**, ze stejného důvodu jako `readShortcut`
    /// a `DiffPinnedHeader`: čte `viewport.top`, tedy hodnotu, která se mění při každém otočení
    /// kolečka. A **nekreslí se vůbec, když ho nikdo nečte** — pravidlo z #438: modifikátor,
    /// jehož výsledek nikdo nepřečte, se nepřipojuje.
    @ViewBuilder private var anchorReporter: some View {
        if let reportScrollAnchor {
            DiffAnchorReporter(
                files: diff.files,
                extents: fileExtents,
                frames: rowFrames,
                viewport: viewport,
                report: reportScrollAnchor
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
