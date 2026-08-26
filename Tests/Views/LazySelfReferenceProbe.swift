import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda k #361: **odkud se v grafu ptá někdo na velikost líného seznamu — a jde to vypnout?**
///
/// Dvanáctý záchvat dal poprvé čistou signaturu: jeden kořen a jeden osmirámcový zásobník, který se
/// v každé hořící sekundě opakuje (`hang10-diag.log`, 8 z 8 vzorků každou sekundu):
///
/// ```
/// #7 LazySubviewPrefetcher<LazyVStackLayout>      ← kořen: kdo si o kolo řekl
/// #6 LazySubviewPlacements<LazyVStackLayout>
/// #5 ScrollViewChildTransform
/// #4 ScrollViewContentFrame
/// #3 ScrollViewContentFrameSize
/// #2 AnimatableFrameAttribute
/// #1 UnaryChildGeometry<_FrameLayout>
/// #0 LazyLayoutComputer<LazyVStackLayout>         ← vrchol: ptá se na velikost téhož seznamu
/// ```
///
/// Sonda měří čtyři věci, každou kvůli jiné otázce:
///
/// 1. **Odkud se ten dotaz na velikost bere** (`stacksOnTheTimeline`). Odpověď: pružný rámec si ho
///    odpovídá **jako kořen** (30 z 30 vzorků), `fillingSlot()` i `GeometryReader` bez rámce
///    **vnořeně** (18 z 18) — tedy uvnitř cizí aktualizace. `VStack` místo `LazyVStack`u nemá
///    v grafu ani jeden `LazySubview*` atribut, takže se ta vazba nemá kde utvořit.
/// 2. **Hoří to i offscreen** (`burnsAfterThePumpStops` a `burnsAfterTheDataStops`). Odpověď:
///    **ne** — po zastavení pumpy 0,000 s CPU ze 4 s, a to jak když pumpa špinila **rozvržení**,
///    tak když **přidávala řádky** (druhé je napodobení toho, co je v záznamu vidět těsně před
///    zdí). Jsou to pokusy **třináctý a čtrnáctý**, takže „už to netuhne“ se pořád tvrdit nedá.
/// 3. **Co by stálo vzdát se líného seznamu** (`eagerLayoutCost`) — jediná varianta, u které kolo
///    z #361 nemá z čeho vzniknout. Odpověď: první rozvržení 300 uzlů **2,2–3,4 ms proti
///    32–35 ms** (a to s obyčejným `Text`em, ne s markdownem), dotazů na identitu 7,6×.
///
/// **Kdo je ten vnořený kořen, se mezi běhy mění** (`LazySubviewPrefetcher`,
/// `AnimatableAttribute<EdgeInsets>`, `ScrollViewChildSafeArea`) a mění se i s tvarem scény —
/// naměřeno na dvou podobách téhle sondy. Tvrdit se proto dá jedině to slabší: **kořen, nebo
/// vnořeně.** Kdyby se jmenoval, byl by to údaj, který jednou vyjde a jednou ne.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Odkud se ptá na velikost líného seznamu (#361)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct LazySelfReferenceProbe {
    @Test("Zásobníky grafu na ose konverzace")
    func stacksOnTheTimeline() throws {
        #expect(GraphProbe.prepare(), "AttributeGraph nejde otevřít, sonda nemá čím měřit")
        for shape in SelfRefShape.allCases {
            let collector = GraphStackCollector()
            let window = show(rootView: SelfReferenceList(collector: collector, shape: shape))
            defer {
                collector.pump?.invalidate()
                window.orderOut(nil)
            }
            _ = spinMainRunLoop(seconds: 1.0)
            collector.reset()
            let cpu = spinMainRunLoop(seconds: 3)
            print("SONDA \(shape.rawValue): \(collector.dirty)× zašpiněný graf,"
                + " \(collector.identity) dotazů na identitu, \(collector.stacks.count) vzorků,"
                + " CPU \(String(format: "%.3f", cpu)) s ze 3 s")
            print("SONDA \(shape.rawValue): dotazů na velikost seznamu"
                + " \(collector.rootSizeQueries) jako kořen, \(collector.nestedSizeQueries) vnořených"
                + " z \(collector.stacks.count) vzorků, líných atributů \(collector.lazyAttributes)")
            for line in collector.digest { print("SONDA \(shape.rawValue): \(line)") }
            if let first = collector.stacks.first {
                for line in TextLines.nonEmpty(first).prefix(40) {
                    print("SONDA \(shape.rawValue) rámec: \(line.trimmingCharacters(in: .whitespaces).prefix(160))")
                }
            }
        }
    }

    /// Druhá polovina sondy: **hoří to i tady?** Scéna má tvar celého tabu — `GeometryReader`
    /// a `frame(width:height:)` na hranici obsahu (#220), pod ním `VStack` s lištou, osou
    /// a composerem, a v ose uzly tvaru `ConversationNodeView` (`HStack`, puntík, `filling()`,
    /// `narrowingWidth`, linka v `background`).
    ///
    /// Měří se **po zastavení pumpy**: v záchvatu nekrmí kolo nic zvenčí (nula vzorků na timeru
    /// i na hlavní frontě), takže reprodukce znamená CPU, které hoří dál, když se přestalo špinit.
    @Test("Hoří osa dál, když se přestane špinit?")
    func burnsAfterThePumpStops() throws {
        #expect(GraphProbe.prepare(), "AttributeGraph nejde otevřít, sonda nemá čím měřit")
        for shape in SelfRefShape.allCases {
            let collector = GraphStackCollector()
            let window = show(
                rootView: TabShapedTimeline(collector: collector, shape: shape),
                width: 900,
                height: 700
            )
            defer {
                collector.pump?.invalidate()
                window.orderOut(nil)
            }
            _ = spinMainRunLoop(seconds: 1.5)
            collector.pump?.invalidate()
            collector.pump = nil
            collector.reset()
            let cpu = spinMainRunLoop(seconds: 4)
            print("SONDA TAB \(shape.rawValue): pumpa zastavená, CPU"
                + " \(String(format: "%.3f", cpu)) s ze 4 s,"
                + " \(collector.identity) dotazů na identitu, \(collector.stacks.count) vzorků,"
                + " vnořených dotazů na velikost \(collector.nestedSizeQueries)")
            for line in collector.digest { print("SONDA TAB \(shape.rawValue): \(line)") }
        }
    }

    /// Poslední tři sekundy před zdí (dvanáctý záchvat, `hang10-diag.log`) mají tvar, který doteď
    /// nikdo nezkusil napodobit — **není to zašpiněné rozvržení, je to průchod tělem odshora**:
    ///
    /// ```
    /// 15:37:35  39 kol, 0,440 s CPU, body: ConversationNodeView=10 ConversationEntryView=8
    ///                                      PullRequestDetailView=3 ContentView=2 ConversationView=2
    ///                                      MarkdownText=2 ActivityFeedView=1
    ///           graf: ConversationRow.id=60          ← ještě normální
    /// 15:37:37  33 kol, 0,573 s CPU, body: ConversationNodeView=4 …
    ///           graf: ConversationRow.id=18069       ← a tady to ujede
    /// 15:37:38   0 kol, 1,054 s CPU — zeď
    /// ```
    ///
    /// Sonda proto zkouší to samé: pumpa **mění data**, ne odsazení lišty — přidává řádky, takže se
    /// `ForEach` přeskládá a projde se tělem odshora. Pak se pumpa zastaví a měří se, jestli to hoří
    /// dál. Kdyby ano, je kolo z #361 poprvé v harnessu.
    @Test("Hoří osa dál, když se přestanou přidávat řádky?")
    func burnsAfterTheDataStops() throws {
        for shape in [SelfRefShape.flexible, .measured] {
            let collector = GraphStackCollector()
            let window = show(
                rootView: GrowingTimeline(collector: collector, shape: shape),
                width: 900,
                height: 700
            )
            defer {
                collector.pump?.invalidate()
                window.orderOut(nil)
            }
            _ = spinMainRunLoop(seconds: 3)
            collector.pump?.invalidate()
            collector.pump = nil
            collector.reset()
            let cpu = spinMainRunLoop(seconds: 4)
            print("SONDA DATA \(shape.rawValue): pumpa zastavená, CPU"
                + " \(String(format: "%.3f", cpu)) s ze 4 s,"
                + " \(collector.identity) dotazů na identitu, \(collector.stacks.count) vzorků")
            for line in collector.digest { print("SONDA DATA \(shape.rawValue): \(line)") }
        }
    }

    /// Co by stálo se líného seznamu na ose vzdát. Měří se **první rozvržení** scény tvaru tabu
    /// se 300 uzly, střídavě (A/B/A/B) — drift sezení je větší než hledaný rozdíl (#274).
    @Test("Kolik stojí první rozvržení osy bez líného seznamu")
    func eagerLayoutCost() throws {
        var times: [SelfRefShape: [Double]] = [:]
        for _ in 0..<3 {
            for shape in [SelfRefShape.measured, .eager] {
                let collector = GraphStackCollector()
                let hosting = NSHostingView(rootView: TabShapedTimeline(collector: collector, shape: shape))
                hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hosting
                // Monotónní hodiny, ne `Date` — viz `ConversationAxisShapeProbe`.
                let duration = ContinuousClock().measure { hosting.layoutSubtreeIfNeeded() }
                times[shape, default: []].append(
                    Double(duration.components.seconds) * 1000
                        + Double(duration.components.attoseconds) / 1e15
                )
                collector.pump?.invalidate()
                window.orderOut(nil)
            }
        }
        for shape in [SelfRefShape.measured, .eager] {
            let values = times[shape] ?? []
            print("SONDA CENA \(shape.rawValue): první rozvržení 300 uzlů "
                + values.map { String(format: "%.1f", $0) }.joined(separator: " / ") + " ms")
        }
    }

    private func show(rootView: some View, width: Double = 520, height: Double = 380) -> NSWindow {
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        // Velikost až za kontrolérem — `contentViewController` přebije `contentRect` (past z #350).
        window.setContentSize(NSSize(width: width, height: height))
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.level = .floating
        window.orderFrontRegardless()
        return window
    }
}

/// Odebrané zásobníky **mimo observable stav** — kdyby to byl `@State`, sonda by měřila sebe.
@MainActor final class GraphStackCollector {
    /// Strop na počet vzorků: `GraphProbe.stack()` stojí 0,0063 ms a dotazů na identitu je desítky
    /// tisíc za sekundu, takže bez stropu by sonda zapisovala víc, než měří.
    static let limit = 60

    var stacks: [String] = []
    var identity = 0
    var dirty = 0
    var pump: Timer?

    func reset() {
        stacks.removeAll()
        identity = 0
        dirty = 0
    }

    func note() {
        identity += 1
        // Každý dvoustý dotaz, ať jsou vzorky z různých kol, ne šedesát z jedné milisekundy.
        guard stacks.count < Self.limit, identity % 200 == 0 else { return }
        guard let stack = GraphProbe.stack() else { return }
        stacks.append(stack)
    }

    /// Kolikrát se na velikost líného seznamu ptá **někdo jiný**, tedy `LazyLayoutComputer` je
    /// vrchol zásobníku a kořen je něco nad ním.
    ///
    /// **Kdo přesně ten kořen je, se mezi běhy mění** (naměřeno: `LazySubviewPrefetcher`,
    /// `AnimatableAttribute<EdgeInsets>`, `ScrollViewChildSafeArea`) a záleží i na tvaru scény,
    /// takže jmenovat ho by bylo tvrzení, které jednou vyjde a jednou ne. Stabilní je právě tohle:
    /// **je ten dotaz vlastní kořen, nebo je vnořený?** Pružný rámec ho má vždycky jako kořen
    /// (30 z 30), `fillingSlot()` vždycky vnořený (18 z 18).
    var nestedSizeQueries: Int {
        stacks.count { stack in
            let frames = Policy.graphStack(from: stack)
            guard frames.top?.hasPrefix("LazyLayoutComputer") == true else { return false }
            return frames.root?.hasPrefix("LazyLayoutComputer") == false
        }
    }

    /// Totéž, ale dotazy, které si líný seznam **odpovídá sám jako kořen**.
    var rootSizeQueries: Int {
        stacks.count { stack in
            let frames = Policy.graphStack(from: stack)
            guard frames.top?.hasPrefix("LazyLayoutComputer") == true else { return false }
            return frames.root?.hasPrefix("LazyLayoutComputer") == true
        }
    }

    /// Kolik vzorků má v zásobníku vůbec nějaký `LazySubview*` atribut. U `VStack`u musí být nula
    /// — jinak by číslo z té varianty netvrdilo nic.
    var lazyAttributes: Int {
        stacks.count { $0.contains("LazySubview") }
    }

    var digest: [String] {
        let parsed = stacks.map(Policy.graphStack(from:))
        return [
            "kořeny " + histogram(parsed.compactMap(\.root)),
            "vrcholy " + histogram(parsed.compactMap(\.top)),
            "změněné vstupy " + histogram(parsed.flatMap(\.changed)),
        ]
    }

    private func histogram(_ values: [String]) -> String {
        let counts = values.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(8)
            .map { "\($0.key.prefix(60))=\($0.value)" }
            .joined(separator: " ")
    }
}

/// Které podoby toho jednoho místa se poměřují.
enum SelfRefShape: String, CaseIterable {
    /// Pružný rámec — podoba do #435.
    case flexible = "pružná výška"
    /// `fillingSlot()` z aplikace, tedy stav po #435.
    case measured = "fillingSlot"
    /// `GeometryReader` **bez** vnitřního rámce, tedy bez centrování. Byla to hypotéza, že se
    /// `_FrameLayout` ptá na velikost jen kvůli zarovnání — **změřeno a vyloučeno**: dotazů je
    /// přesně tolik jako u `fillingSlot()`. Zůstává jako měřený důvod, proč to nestačí.
    case readerOnly = "GeometryReader bez rámce"
    /// `VStack` místo `LazyVStack`u — tedy **žádná** líná krabice, žádné fáze položek a žádný
    /// prefetcher. Jediná podoba, u které se ta vazba nemá kde utvořit; v repu není a je tady
    /// proto, aby se cena té varianty dala číst z čísla, ne z dohadu.
    case eager = "VStack místo LazyVStacku"

    /// Je v té podobě líný seznam? U `eager` se neměří, odkud se ptá — měří se to, že se
    /// `LazySubview*` atributy v grafu **vůbec neobjeví**.
    var isLazy: Bool { self != .eager }
}

/// Strom tvaru osy konverzace, který si u každého dotazu na identitu bere vzorek zásobníku.
///
/// **Dvě scény, ne jedna** (`TabShapedTimeline` je ta druhá) a je to schválně: tady jsou řádky
/// obyčejný `Text` v malém okně, tedy nejmenší scéna, ve které se ta vazba ještě ukáže — čísla
/// z ní se proto dají přičíst tvaru štěrbiny, ne tvaru řádku. Ta druhá je naopak co nejblíž
/// aplikaci (hranice obsahu, uzly s puntíkem a linkou, okno 900×700) a slouží k pokusu scénu
/// rozhořet.
struct SelfReferenceList: View {
    let collector: GraphStackCollector
    let shape: SelfRefShape
    var rowCount = 300

    /// Výška lišty, kterou pumpa mění o bod. **Musí být rozvržení, ne kresba**: se změnou krytí se
    /// líný seznam nepřerovná vůbec (změřeno — 0 dotazů na identitu za 3 s), takže by sonda neměla
    /// co vzorkovat.
    @State private var wobble = 0.0

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "lišta")
                .padding(9)
                .padding(.top, wobble)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.gray).frame(height: 1)
            switch shape {
            case .flexible:
                list.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .readerOnly:
                GeometryReader { _ in list }
            // `eager` má **tutéž** štěrbinu jako `measured` schválně: liší se jedině ten stack, aby
            // se čísla těch dvou dala srovnat.
            case .measured, .eager:
                list.fillingSlot()
            }
            Text(verbatim: "composer").padding(9).frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(SelfRefPump(collector: collector) { wobble = wobble == 0 ? 1 : 0 })
    }

    private var list: some View {
        ScrollView {
            stack
                .padding(16)
        }
    }

    @ViewBuilder private var stack: some View {
        if shape.isLazy {
            LazyVStack(alignment: .leading, spacing: 0) { content }
        } else {
            VStack(alignment: .leading, spacing: 0) { content }
        }
    }

    private var content: some View {
        ForEach(rows, id: \.sampledID) { row in
            Text(verbatim: row.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var rows: [SampledRow] {
        (0..<rowCount).map { SampledRow(index: $0, collector: collector) }
    }
}

/// Scéna tvaru **celého tabu**: hranice obsahu s `GeometryReader`em a předanou šířkou (#220),
/// pod ní osa a v ní uzly tvaru `ConversationNodeView`.
struct TabShapedTimeline: View {
    let collector: GraphStackCollector
    let shape: SelfRefShape
    var rowCount = 300

    @State private var wobble = 0.0

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { proxy in
                axis
                    .availableWidth(proxy.size.width)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .modifier(SelfRefPump(collector: collector) { wobble = wobble == 0 ? 1 : 0 })
    }

    private var axis: some View {
        VStack(spacing: 0) {
            Text(verbatim: "lišta")
                .padding(9)
                .padding(.top, wobble)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.gray).frame(height: 1)
            switch shape {
            case .flexible:
                timeline.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .readerOnly:
                GeometryReader { _ in timeline }
            // Tatáž štěrbina jako u `measured`, viz `SelfReferenceList`.
            case .measured, .eager:
                timeline.fillingSlot()
            }
            Text(verbatim: "composer").padding(9).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var timeline: some View {
        ScrollView {
            stack
                .padding(16)
                .narrowingWidth(by: 32)
        }
    }

    @ViewBuilder private var stack: some View {
        if shape.isLazy {
            LazyVStack(alignment: .leading, spacing: 0) { nodes }
        } else {
            VStack(alignment: .leading, spacing: 0) { nodes }
        }
    }

    private var nodes: some View {
        ForEach(rows, id: \.sampledID) { row in
            NodeShapedRow(row: row)
        }
    }

    private var rows: [SampledRow] {
        (0..<rowCount).map { SampledRow(index: $0, collector: collector) }
    }
}

/// Tentýž tvar jako `TabShapedTimeline`, ale pumpa **mění data**: každý tik přidá řádek, takže se
/// `ForEach` přeskládá a projde se tělem odshora — jako když na ose přistane tik pollingu.
struct GrowingTimeline: View {
    let collector: GraphStackCollector
    let shape: SelfRefShape

    @State private var rowCount = 200

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { proxy in
                axis
                    .availableWidth(proxy.size.width)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .modifier(SelfRefPump(collector: collector) { rowCount += 1 })
    }

    private var axis: some View {
        VStack(spacing: 0) {
            Text(verbatim: "lišta").padding(9).frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.gray).frame(height: 1)
            switch shape {
            case .flexible:
                timeline.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .readerOnly:
                GeometryReader { _ in timeline }
            case .measured, .eager:
                timeline.fillingSlot()
            }
            Text(verbatim: "composer").padding(9).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.sampledID) { row in
                    NodeShapedRow(row: row)
                }
            }
            .padding(16)
            .narrowingWidth(by: 32)
        }
    }

    private var rows: [SampledRow] {
        (0..<rowCount).map { SampledRow(index: $0, collector: collector) }
    }
}

/// Řádek tvaru `ConversationNodeView`: puntík pevné výšky, obsah s předanou šířkou, linka
/// v `background` (tedy `SecondaryLayerGeometryQuery`, který má v hořícím vzorku 13 %).
private struct NodeShapedRow: View {
    let row: SampledRow

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle().strokeBorder(.gray, lineWidth: 1).frame(width: 24, height: 24)
                Image(systemName: "circle").font(.system(size: 11, weight: .medium))
            }
            .frame(width: 24, height: 34, alignment: .top)
            Text(verbatim: row.text)
                .fixedSize(horizontal: false, vertical: true)
                .filling(alignment: .leading)
                .narrowingWidth(by: 32)
                .padding(.bottom, 11)
        }
        .background(alignment: .topLeading) {
            Rectangle().fill(.gray).frame(width: 2).padding(.top, 24).frame(width: 24)
        }
    }
}

/// Pumpa, která graf špiní zvenčí — `Timer` na runloopu, ne `Task.sleep` (důvod je
/// u `LayoutCallbackProbe`).
private struct SelfRefPump: ViewModifier {
    let collector: GraphStackCollector
    let tick: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                let timer = Timer(timeInterval: 0.02, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        tick()
                        collector.dirty += 1
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                collector.pump = timer
            }
    }
}

private struct SampledRow {
    let index: Int
    let collector: GraphStackCollector

    var sampledID: Int {
        MainActor.assumeIsolated { collector.note() }
        return index
    }

    var text: String {
        guard index % 7 == 0 else { return "Řádek \(index) — krátká událost" }
        return String(
            repeating: "Řádek \(index): dlouhý komentář, který se na skutečné šířce zalomí. ",
            count: 6
        )
    }
}
