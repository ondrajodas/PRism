import AppKit
import Foundation
import Observation
import SwiftUI
import Testing

@testable import PRism

/// Sonda k #469: **co stojí diff bez líného seznamu — a zmizí z něj to, co drží kolo z #361.**
///
/// Sestra `ConversationAxisShapeProbe`. Osa se u #361 vyřešila tím, že se z ní `LazyVStack`
/// odebral; kolo se tím ale **přestěhovalo do diffu** (dva `sample`y ze živého záchvatu 27. 8.,
/// `LazySubviewPlacements.placeSubviews` 25 %, `FileDiff.diagnosedID` i `DiffRow.diagnosedID`
/// v zásobníku a nula `ConversationRow`). Otázka je proto tatáž jako tehdy, jen o dvě obrazovky
/// vedle: **unese diff pevný stack?**
///
/// Poměřují se tři podoby toho jednoho místa a měří se obě strany rozhodnutí:
///
/// 1. `firstLayoutCost` — co se za to platí. U diffu je to celá nevýhoda: pevný stack vyrobí
///    **všechny** bloky, tedy všechny `NSTextView`, ne jen viditelné.
/// 2. `scrollingCost` — co se za to dostane při projíždění. Série se **střídají** (A/B/A/B),
///    protože drift sezení je větší než hledaný rozdíl (#274).
/// 3. `graphUnderTheRow` — **strukturální** doklad: kolik `LazySubview*` atributů je
///    v evaluačním zásobníku pod řádkem diffu. U pevného stacku musí být nula.
/// 4. `burnAfterScrolling` — hoří diff po gestu? **Nedokazuje to nic** (kolo se v harnessu za
///    čtrnáct kol #361 vyrobit nepodařilo), je to kontrola, že se pevný stack nechová hůř.
/// 5. `relayoutCost` (#472) — co stojí **přerovnání shora**, tedy to, co #469 neměřilo:
///    tělo detailu se překládá při každém průchodu tělem `ContentView`, ne jen při scrollování.
///
/// Kvůli té páté jde každá scéna přes `DiffRelayoutHost` (jeden `View` navíc, který drží generaci),
/// takže se čísla z #469 mohou o kousek lišit — poměry mezi podobami tím zůstávají.
///
/// Řádky jsou **skutečné `DiffRowView`** nad skutečnými `DiffRow` z rozparsovaného diffu —
/// tedy včetně `NSTextView` v každém bloku. Bez nich by cena pevného stacku vyšla řádově nižší,
/// než jaká v aplikaci je.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Diff: líný seznam proti pevnému (#469)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct DiffShapeProbe {
    /// Kolik řádků diffu se poměřuje. Diff **mez shora nemá** (na rozdíl od osy, kterou dotaz
    /// zastropuje na čtyři stovky uzlů), takže se měří i velikost, u které je pevný stack zjevně
    /// mimo — z čísla musí být vidět, kde se to láme.
    static let sizes = [500, 2000, 6000, 20000, 50000]

    /// Kolik řádků se poměřuje u projíždění. Míň velikostí než u prvního rozvržení, protože
    /// každá série je gesto v reálném čase — rozhoduje **jestli cena roste s délkou diffu**.
    static let scrollingSizes = [500, 6000]

    /// Co stojí **první rozvržení**, tedy přepnutí na záložku `Soubory`.
    @Test("Kolik stojí první rozvržení diffu")
    func firstLayoutCost() throws {
        for lines in Self.sizes {
            var times: [DiffListShape: [Double]] = [:]
            var facts: [DiffListShape: String] = [:]
            for _ in 0..<3 {
                for shape in DiffListShape.allCases {
                    let (elapsed, fact) = measureFirstLayout(shape: shape, lines: lines)
                    times[shape, default: []].append(elapsed)
                    facts[shape] = fact
                }
            }
            for shape in DiffListShape.allCases {
                let values = times[shape] ?? []
                print("MĚŘENÍ první rozvržení \(lines) řádků, \(shape.rawValue): "
                    + values.map { String(format: "%.0f", $0) }.joined(separator: " / ")
                    + " ms — \(facts[shape] ?? "")")
            }
        }
    }

    /// Co stojí **projíždění**. Gesto je skutečné (`WheelGesture`) — programový posun živé
    /// scrollování nespustí a `LazyLayoutViewCache` si právě při něm říká o předběžné načtení.
    @Test("Kolik stojí projíždění diffu")
    func scrollingCost() throws {
        // **Víc velikostí, ne jedna**: o rozhodnutí nerozhoduje absolutní číslo, ale jestli cena
        // roste s **celým** diffem, nebo jen s tím, co je vidět.
        for lines in Self.scrollingSizes {
            var costs: [DiffListShape: [Double]] = [:]
            for _ in 0..<2 {
                for shape in DiffListShape.allCases {
                    let rows = Self.material(lines: lines)
                    let window = show(rows: rows, shape: shape)
                    defer { window.orderOut(nil) }
                    _ = spinMainRunLoop(seconds: 2)
                    let root = try #require(window.contentView)
                    let scroller = try #require(Self.tallestScroller(in: root))
                    let before = Self.blockWork(in: root)
                    let started = mainThreadCPUSeconds()
                    let landed = WheelGesture.scroll(over: scroller, in: window, steps: 150, step: 40)
                    let cost = mainThreadCPUSeconds() - started
                    costs[shape, default: []].append(cost)
                    print(String(
                        format: "MĚŘENÍ projíždění %d řádků, %@: %.2f s CPU, dojelo na %.0f"
                            + " z obsahu %.0f — před gestem %@, po gestu %@",
                        lines,
                        shape.rawValue,
                        cost,
                        landed,
                        scroller.documentView?.frame.height ?? 0,
                        before.description,
                        Self.blockWork(in: root).description
                    ))
                }
            }
            for shape in DiffListShape.allCases {
                let values = costs[shape] ?? []
                print("MĚŘENÍ projíždění \(lines) řádků, \(shape.rawValue): "
                    + values.map { String(format: "%.2f", $0) }.joined(separator: " / ") + " s CPU")
            }
        }
    }

    /// Co stojí **přerovnání shora** (#472), tedy průchod tělem `PullRequestDetailView`.
    ///
    /// Je to druhá polovina rozhodnutí z #469 a ta, kterou #469 neměřilo: diff se nepřerovnává jen
    /// scrollováním. Když se jeho tělo přeloží, poskládají se v líném seznamu jen viditelné řádky,
    /// v pevném **všechny**.
    ///
    /// **Co tělo detailu překládá, měří `DetailRelayoutMeasurement`** — a vyšlo z toho, že to
    /// **není** průchod tělem `ContentView` (ten detail nechá být, protože se nezměnil), ale
    /// **zápis do sledované vlastnosti**, kterou detail čte. Tahle sonda proto neměří scénář
    /// z aplikace, ale **tvar seznamu**: co stojí přerovnání shora, ať ho vyvolá cokoli.
    ///
    /// Měří se **cena přerovnání, ne příprava** (#274): okno se nechá usadit a teprve pak se
    /// generace bumpne dvacetkrát s kolem runloopu po každém bumpnutí.
    @Test("Kolik stojí přerovnání shora nad diffem")
    func relayoutCost() throws {
        for lines in Self.scrollingSizes {
            var costs: [DiffListShape: [Double]] = [:]
            // Série se střídají A/B/A/B — drift sezení je větší než hledaný rozdíl (#274).
            for _ in 0..<2 {
                for shape in DiffListShape.allCases {
                    let rows = Self.material(lines: lines)
                    let clock = RelayoutClock()
                    let window = show(rows: rows, shape: shape, clock: clock)
                    defer { window.orderOut(nil) }
                    _ = spinMainRunLoop(seconds: 2)
                    let root = try #require(window.contentView)
                    let before = Self.blockWork(in: root)
                    let started = mainThreadCPUSeconds()
                    for _ in 0..<Self.relayouts {
                        clock.tick += 1
                        _ = spinMainRunLoop(seconds: 0.016)
                    }
                    let cost = mainThreadCPUSeconds() - started
                    costs[shape, default: []].append(cost)
                    print(String(
                        format: "MĚŘENÍ přerovnání %d řádků, %@: %.2f s CPU za %d přerovnání"
                            + " (%.0f ms na jedno) — před %@, po %@",
                        lines,
                        shape.rawValue,
                        cost,
                        Self.relayouts,
                        cost / Double(Self.relayouts) * 1000,
                        before.description,
                        Self.blockWork(in: root).description
                    ))
                }
            }
            for shape in DiffListShape.allCases {
                let values = costs[shape] ?? []
                print("MĚŘENÍ přerovnání \(lines) řádků, \(shape.rawValue): "
                    + values.map { String(format: "%.2f", $0) }.joined(separator: " / ") + " s CPU")
            }
        }
    }

    /// Kolikrát se v sérii přerovnává. Dvacet, protože jedno přerovnání je v aplikaci pod
    /// rozlišením `ps` a série musí trvat déle než kolo runloopu.
    private static let relayouts = 20

    /// Kolik práce ve viditelných blocích proběhlo — tatáž konstrukce jako v `IdleDiffSpinProbe`.
    private static func blockWork(in view: NSView) -> BlockWork {
        if let container = view as? DiffPairBlockContainer {
            return BlockWork(updates: container.updates, mounts: container.mounts, blocks: 1)
        }
        if let text = view as? DiffTextView {
            return BlockWork(updates: text.updates, mounts: text.mounts, blocks: 1)
        }
        return view.subviews.reduce(BlockWork()) { $0 + blockWork(in: $1) }
    }

    private struct BlockWork: CustomStringConvertible {
        var updates = 0
        var mounts = 0
        var blocks = 0

        static func + (lhs: Self, rhs: Self) -> Self {
            Self(
                updates: lhs.updates + rhs.updates,
                mounts: lhs.mounts + rhs.mounts,
                blocks: lhs.blocks + rhs.blocks
            )
        }

        var description: String { "\(blocks) bloků, \(updates)× update, \(mounts)× nasazení" }
    }

    /// Co stojí **změna šířky okna**, tedy tažení za hranu.
    ///
    /// Je to druhý konec téhož rozhodnutí a u diffu ten nepříjemnější: šířka je součástí klíče
    /// kreslení bloku (#393), takže se při ní **přesází každý blok, který v okně je** — u pevného
    /// stacku tedy všechny, u líného jen viditelné.
    @Test("Kolik stojí změna šířky okna nad diffem")
    func resizingCost() throws {
        for lines in [2000, 6000] {
            var costs: [DiffListShape: [Double]] = [:]
            for _ in 0..<2 {
                for shape in DiffListShape.allCases {
                    let rows = Self.material(lines: lines)
                    let window = show(rows: rows, shape: shape)
                    defer { window.orderOut(nil) }
                    _ = spinMainRunLoop(seconds: 2)
                    // Dvacet kroků tam a zpátky po 24 bodech, s kolem runloopu po každém — jako
                    // když se táhne za hranu okna. Strop je ve výčtu, žádná smyčka „dokud“.
                    let started = mainThreadCPUSeconds()
                    for step in 0..<20 {
                        let width = 1200 - Double(min(step, 19 - step) * 24)
                        window.setContentSize(NSSize(width: width, height: 800))
                        _ = spinMainRunLoop(seconds: 0.03)
                    }
                    costs[shape, default: []].append(mainThreadCPUSeconds() - started)
                }
            }
            for shape in DiffListShape.allCases {
                let values = costs[shape] ?? []
                print("MĚŘENÍ tažení za hranu \(lines) řádků, \(shape.rawValue): "
                    + values.map { String(format: "%.2f", $0) }.joined(separator: " / ") + " s CPU")
            }
        }
    }

    /// **Strukturální doklad**: co je v evaluačním zásobníku, když se `ForEach` ptá na identitu
    /// řádku diffu. U pevného stacku tam `LazySubview*` nemají jak vzniknout.
    @Test("Co je v grafu pod řádkem diffu")
    func graphUnderTheRow() throws {
        #expect(GraphProbe.prepare(), "AttributeGraph nejde otevřít, sonda nemá čím měřit")
        for shape in DiffListShape.allCases {
            let collector = GraphStackCollector()
            let rows = Self.material(lines: 2000, collector: collector)
            let window = show(rows: rows, shape: shape)
            defer { window.orderOut(nil) }
            _ = spinMainRunLoop(seconds: 1.5)
            let root = try #require(window.contentView)
            if let scroller = Self.tallestScroller(in: root) {
                _ = WheelGesture.scroll(over: scroller, in: window, steps: 40, step: 120)
            }
            _ = spinMainRunLoop(seconds: 1)
            print("SONDA \(shape.rawValue): \(collector.identity) dotazů na identitu,"
                + " \(collector.stacks.count) vzorků, z toho s `LazySubview*` \(collector.lazyAttributes)")
            for line in collector.digest { print("SONDA \(shape.rawValue): \(line)") }
        }
    }

    /// Hoří diff dál, když se dojezdí? Nedokazuje to nic — je to kontrola, že se pevný stack
    /// nechová hůř než líný.
    @Test("Hoří diff po projetí?")
    func burnAfterScrolling() throws {
        for shape in DiffListShape.allCases {
            let rows = Self.material(lines: 2000)
            let window = show(rows: rows, shape: shape)
            defer { window.orderOut(nil) }
            _ = spinMainRunLoop(seconds: 2)
            let root = try #require(window.contentView)
            let scroller = try #require(Self.tallestScroller(in: root))
            _ = WheelGesture.scroll(over: scroller, in: window, steps: 150, step: 40)
            for slice in 1...3 {
                let cpu = spinMainRunLoop(seconds: 3)
                print(String(
                    format: "MĚŘENÍ %@ po gestu, úsek %d: %.2f %% CPU hlavního vlákna",
                    shape.rawValue,
                    slice,
                    cpu / 3 * 100
                ))
            }
        }
    }

    // MARK: - Materiál a okno

    private func measureFirstLayout(shape: DiffListShape, lines: Int) -> (Double, String) {
        let rows = Self.material(lines: lines)
        let host = NSHostingView(rootView: ShapedDiffList(files: rows, shape: shape))
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        let duration = ContinuousClock().measure { host.layoutSubtreeIfNeeded() }
        let elapsed = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
        let content = Self.tallestScroller(in: host)?.documentView?.frame.height ?? 0
        let fact = "obsah \(Int(content)) pt, \(Self.descendants(of: host)) prvků,"
            + " \(Self.blocks(in: host)) bloků kódu"
        window.orderOut(nil)
        return (elapsed, fact)
    }

    /// Rozparsovaný diff složený ze **skutečné** fixture a syntetického doplňku na požadovaný
    /// počet řádků — tentýž postup jako `IdleDiffSpinProbe.prepared(big:)`.
    static func material(lines: Int, collector: GraphStackCollector? = nil) -> [SampledDiffFile] {
        let diff = DiffParser.parse(DiffMaterial.text(lines: lines))
        return diff.files.map { file in
            SampledDiffFile(
                file: file,
                rows: DiffRow.blocked(DiffRow.rows(of: file, layout: .unified))
                    .map { SampledDiffRow(row: $0, collector: collector) },
                collector: collector
            )
        }
    }

    private func show(
        rows: [SampledDiffFile],
        shape: DiffListShape,
        clock: RelayoutClock? = nil
    ) -> NSWindow {
        let host = NSHostingView(
            rootView: DiffRelayoutHost(files: rows, shape: shape, clock: clock)
                .background(Palette.background)
        )
        host.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.level = .floating
        window.orderFrontRegardlessUnanimated()
        return window
    }

    private static func descendants(of view: NSView) -> Int {
        view.subviews.reduce(1) { $0 + descendants(of: $1) }
    }

    private static func blocks(in view: NSView) -> Int {
        view.subviews.reduce(view is DiffPairBlockContainer || view is DiffTextView ? 1 : 0) {
            $0 + blocks(in: $1)
        }
    }

    static func tallestScroller(in view: NSView) -> NSScrollView? {
        var best = view as? NSScrollView
        for child in view.subviews {
            guard let found = tallestScroller(in: child) else { continue }
            let height = found.documentView?.frame.height ?? 0
            if height > (best?.documentView?.frame.height ?? 0) { best = found }
        }
        return best
    }
}

/// Kolikáté přerovnání shora (#472) — pohon sondy `relayoutCost`.
///
/// Musí to být **objekt v prostředí sondy**, ne `@State` uvnitř scény: sonda bumpuje generaci
/// zvenčí a chce, aby se z toho stal průchod tělem hostitele — tedy tatáž cesta, jakou v aplikaci
/// jde tik pollingu (`ContentView` → `PullRequestDetailView` → `DiffView`).
@MainActor @Observable final class RelayoutClock {
    var tick = 0
}

/// Hostitel seznamu — model `PullRequestDetailView`: jeho tělo se překládá a skládá seznam znovu.
struct DiffRelayoutHost: View {
    let files: [SampledDiffFile]
    let shape: DiffListShape
    var clock: RelayoutClock?

    var body: some View {
        ShapedDiffList(files: files, shape: shape, generation: clock?.tick ?? 0)
    }
}

/// Které podoby seznamu řádků se poměřují.
enum DiffListShape: String, CaseIterable {
    /// `LazyVStack` se sekcemi a ukotvenými hlavičkami — podoba do #469.
    case lazyStack = "LazyVStack"
    /// `VStack` **s oknem** — podoba, kterou má diff od #469: blok se nasazuje jen v pásu kolem
    /// výřezu (`DiffBlockSlot`).
    case windowed = "VStack s oknem"
    /// `VStack` **bez okna** — ablace. Prostor výřezu se nedeklaruje, takže
    /// `Policy.isNearViewport(_:in:)` odpoví „nasadit“ a v seznamu visí všechny bloky.
    case eager = "VStack se všemi bloky"
    /// `VStack`, ve kterém jsou **řádky prázdné** (jen rezervovaná výška).
    ///
    /// Není to varianta k nasazení, je to **ablace**: odpovídá na otázku, jestli je cena
    /// projíždění v pevném stacku vlastností toho stacku (pak by rostla i tady), nebo toho, že
    /// v něm visí `NSTextView` na každý blok. Na tom stojí, jestli stačí odpojit **text**, nebo
    /// se musí okno dělat nad celým seznamem.
    case hollow = "VStack bez bloků"
    /// Totéž, ale **bez ukotvených hlaviček** — druhá ablace: co z ceny projíždění patří
    /// samotnému ukotvení (`DiffFileSection`), které za `LazyVStack(pinnedViews:)` musí zaskočit.
    case hollowFlat = "VStack bez bloků a bez ukotvení"
}

/// Soubor diffu i s rozloženými řádky a **hákem sondy**: přečtení identity odebere vzorek
/// evaluačního zásobníku.
struct SampledDiffFile: Identifiable {
    let file: FileDiff
    let rows: [SampledDiffRow]
    let collector: GraphStackCollector?

    var id: String { file.id }
}

/// Řádek diffu plus **hák sondy**: přečtení identity odebere vzorek evaluačního zásobníku.
///
/// Hák patří na **řádek**, ne na soubor: souborů je pár desítek, kdežto na identitu řádku se líný
/// seznam ptá při každém přerovnání obsahu — a právě to je ta cesta, ve které u #361 stály
/// `LazySubview*` atributy.
struct SampledDiffRow: Identifiable {
    let row: DiffRow
    let collector: GraphStackCollector?

    var id: String {
        // `MainActor.assumeIsolated`, protože getter identity je `nonisolated` a `ForEach` si ho
        // čte z hlavního vlákna uvnitř aktualizace grafu — tatáž konstrukce jako u osy.
        if let collector { MainActor.assumeIsolated { collector.note() } }
        return row.id
    }
}

/// Seznam řádků diffu ve dvou podobách. Tvar je opsaný z `DiffView` (`ScrollView`, sekce
/// s hlavičkou souboru, `DiffRowView` na každý řádek), řádky jsou **skutečné**.
struct ShapedDiffList: View {
    let files: [SampledDiffFile]
    let shape: DiffListShape
    /// Kolikáté přerovnání shora (#472). Mění se **jen hodnotou**, obsah seznamu zůstává týž —
    /// je to model toho, co v aplikaci dělá průchod tělem `PullRequestDetailView`: `DiffView`
    /// se poskládá znovu s jinými uzávěry, takže se jeho tělo přeloží, i když se diff nezměnil.
    var generation = 0

    @State private var viewport = DiffViewport()
    @State private var extents = DiffFileExtents()

    var body: some View {
        // Čtení generace je to, čím se tělo při přerovnání přeloží — bez něj by SwiftUI seznam
        // se stejnými daty prohlásil za nezměněný a sonda by měřila nulu u obou podob.
        let _ = generation
        HStack(spacing: 0) {
            GeometryReader { proxy in
                list
                    .availableWidth(proxy.size.width)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var list: some View {
        let scroller = ScrollView {
            stack
                // **Pojmenovaný prostor musí být i v sondě**, jinak `onGeometryChange` v blocích
                // čte rámečky v prostoru, který se scrollováním hýbe — a měřila by se cena, kterou
                // v aplikaci nikdo neplatí (#275).
                .coordinateSpace(.named(DiffView.contentSpace))
        }
        // **Výřez v prostředí dostane jen podoba s oknem.** Bez něj se blok nasadí vždycky, takže
        // se tím jedním modifikátorem zapíná a vypíná celá laznost — a ablace měří přesně to, co
        // se do aplikace dostalo.
        if shape == .windowed {
            scroller
                .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, visible in
                    let band = Policy.mountBand(visible: visible)
                    if viewport.band != band { viewport.band = band }
                    if viewport.top != visible.minY { viewport.top = visible.minY }
                }
                .environment(viewport)
        } else {
            scroller
        }
    }

    @ViewBuilder private var stack: some View {
        switch shape {
        case .lazyStack:
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) { lazySections }
        case .windowed, .eager, .hollow:
            VStack(alignment: .leading, spacing: 0) { sections }
        case .hollowFlat:
            VStack(alignment: .leading, spacing: 0) { flatSections }
        }
    }

    /// Sekce pro **líný** seznam — `Section` s ukotvenou hlavičkou, tedy podoba do #469.
    private var lazySections: some View {
        ForEach(files) { file in
            Section { rows(of: file) } header: { header(of: file) }
                .id(file.file.id)
        }
    }

    /// Sekce pro pevný stack — tvar z aplikace (`DiffFileSection`, ukotvení posunem).
    private var sections: some View {
        ForEach(files) { file in
            DiffFileSection(extents: extents, fileID: file.file.id) {
                header(of: file)
            } content: {
                rows(of: file)
            }
            .id(file.file.id)
        }
    }

    /// Sekce bez ukotvení — hlavička prostě stojí v seznamu.
    private var flatSections: some View {
        ForEach(files) { file in
            VStack(alignment: .leading, spacing: 0) {
                header(of: file)
                rows(of: file)
            }
            .id(file.file.id)
        }
    }

    @ViewBuilder private func rows(of file: SampledDiffFile) -> some View {
        ForEach(file.rows) { row in
            if shape == .hollow || shape == .hollowFlat {
                // Rezervovaná výška místo obsahu — řádek v seznamu zůstává, text z něj mizí.
                Color.clear.frame(height: Self.reserved(for: row.row))
            } else {
                DiffRowView(row: row.row, language: Language(path: file.file.displayPath))
            }
        }
    }

    private func header(of file: SampledDiffFile) -> some View {
        DiffFileHeaderView(
            file: file.file,
            isFolded: false,
            findings: [],
            blockingCategories: Policy.defaultBlockingCategories,
            toggle: {}
        )
    }

    /// Hrubá výška řádku pro ablaci — přesnost tady nehraje roli, měří se **počet prvků**.
    private static func reserved(for row: DiffRow) -> Double {
        switch row {
        case .block(_, let block): Double(block.lines.count) * 17
        case .pairBlock(_, let block): Double(block.count) * 17
        default: 22
        }
    }
}

/// Materiál pro měření diffu: **skutečná** fixture plus syntetický doplněk na požadovaný počet
/// řádků. Jedno místo, protože z něj měří víc sond — dvě kopie by se rozešly první úpravou.
enum DiffMaterial {
    /// Diff o zhruba `lines` řádcích obsahu.
    static func text(lines: Int) -> String {
        // Fixture z veřejného repa je malá (429 řádků), takže se počet dorovnává syntetickými
        // soubory — cena rozvržení roste s počtem řádků v seznamu, ne s jejich růzností.
        let real = (try? Fixture.text("gh/pr-diff-ordinary.diff")) ?? ""
        let missing = max(lines - TextLines.content(real).count, 0)
        guard missing > 0 else { return real }
        // Soubor po 240 řádcích (čtyři hunky po šedesáti), aby se seznam skládal z víc souborů
        // — jeden obří soubor by neměřil sekce ani ukotvené hlavičky.
        let files = max(missing / 240, 1)
        return real + synthetic(files: files, hunks: 4, lines: 60)
    }

    static func synthetic(files: Int, hunks: Int, lines: Int) -> String {
        var out = ""
        for file in 0..<files {
            let path = "src/Module\(file)/Handler\(file).swift"
            out += "diff --git a/\(path) b/\(path)\n"
            out += "index 1111111..2222222 100644\n"
            out += "--- a/\(path)\n"
            out += "+++ b/\(path)\n"
            for hunk in 0..<hunks {
                let start = 1 + hunk * (lines + 20)
                out += "@@ -\(start),\(lines) +\(start),\(lines) @@ func handle()\n"
                for line in 0..<lines {
                    switch line % 5 {
                    case 3: out += "-    return legacy(value, \(line))\n"
                    case 4: out += "+    return modern(value, \(line))\n"
                    default: out += "     let value = compute(\(line))\n"
                    }
                }
            }
        }
        return out
    }
}
