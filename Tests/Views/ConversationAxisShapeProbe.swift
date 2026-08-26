import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda k #361, patnácté kolo: **co stojí osa konverzace bez líného seznamu — a zmizí z ní to,
/// co kolo drží.**
///
/// Čtrnáctý záchvat (dva `sample`y ze **živého** hoření, shodné signatury) dal poprvé celý kruh
/// a je celý uvnitř SwiftUI:
///
/// ```
/// 533 GraphHost.runTransaction
///   533 protocol witness for GraphMutation.apply() in conformance LazyLayoutCache…
///     531 LazyLayoutViewCache.updateItemPhases()
///       263 LazyLayoutViewCache.updateItemPhase(_:)
///         258 AG::Graph::value_set(…)
///           248 AG::Graph::propagate_dirty(AG::AttributeID)
/// ```
///
/// Tedy: `LazySubviewPlacements.placeSubviews` (60 % vzorků hlavního vlákna) umístí položky, ten
/// zápis zašpiní graf, graf si vyžádá další update a umisťuje se znovu. **Naše tělo v tom kole
/// neběží ani jednou** — ze 101, resp. 158 rámců aplikace jsou všechny kromě dvou vstupních bodů
/// jen value-witness kopie `ConversationRow`. Zlevňovat obsah kola tedy nemá co zastavit; jediná
/// podoba, u které se ta vazba nemá kde utvořit, je **osa bez `LazyVStack`u** (třinácté kolo:
/// v grafu ani jeden `LazySubview*` atribut).
///
/// Sonda poměřuje **tři podoby toho jednoho místa** a měří obě strany rozhodnutí:
///
/// 1. `firstLayoutCost` — co se za to platí. Cena je **první rozvržení**, a to je celá nevýhoda
///    pevného stacku: vyrobí se všechny uzly, ne jen viditelné.
/// 2. `scrollingCost` — co se za to dostane při projíždění, tedy v tom, co uživatel dělá
///    nejčastěji. Série se **střídají** (A/B/A/B), protože drift sezení je větší než hledaný
///    rozdíl (#274).
/// 3. `graphUnderTheAxis` — **strukturální** doklad: kolik `LazySubview*` atributů je
///    v evaluačním zásobníku pod řádkem osy. U pevného stacku musí být nula — jinak by ta změna
///    netvrdila nic.
/// 4. `burnAfterScrolling` — hoří osa po gestu? Kolo se v harnessu za čtrnáct pokusů vyrobit
///    nepodařilo, takže **tohle nic nedokazuje** a je tady jen proto, aby se poznalo, kdyby se
///    pevný stack choval hůř.
///
/// Řádky jsou **skutečné `ConversationNodeView`** nad skutečnými `ConversationRow` — ne tvar uzlu
/// jako v `LazySelfReferenceProbe`. Bez markdownu, avatarů a bublin vláken by cena pevného stacku
/// vyšla nižší, než jaká v aplikaci je, a rozhodovalo by se podle podhodnoceného čísla.
///
/// ## Co z toho vyšlo (Debug, okno 1000×800, 2026-08-26)
///
/// | Uzlů | `LazyVStack` | `VStack` | `List` |
/// |---|---|---|---|
/// | 44 | 5,4 ms | **55 ms** | 78 ms |
/// | 150 | 5,0 | **187** | 78 |
/// | 300 | 5,4 | **413** | 95 |
/// | 400 | 5,8 | **614** | 112 |
/// | projíždění 150 × 40 pt (300 uzlů) | 0,31 / 0,29 s | **0,86 / 0,85 s** | neměřitelné |
/// | `LazySubview*` v zásobníku | 2 ze 2 vzorků | **0** | 0 |
///
/// **`List` je zamítnutý, i když čísla vypadají líp**, a jsou k tomu tři měřené důvody: výška
/// obsahu je **odhad** (44 uzlů = 4 876 pt proti 6 745 u `VStack`u, 300 uzlů 11 020 proti 45 432),
/// takže posuvník lže a poloha při projíždění skáče; **syntetické gesto s ním nepohne vůbec**
/// (`dojelo na 0`), takže se cena projíždění naší sondou změřit nedá a „je levnější“ se tvrdit
/// nemůže; a řádek `List`u nese vlastní chrome (výběr, oddělovače, pozadí), tedy **změnu vzhledu**,
/// která by patřila napřed do mockupu. Zůstává tady jako měřená varianta pro případ, že by cena
/// prvního rozvržení začala vadit.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Osa konverzace: líný seznam proti pevnému (#361)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct ConversationAxisShapeProbe {
    /// Kolik uzlů se poměřuje. Horní hranice je z **dotazu**, ne z odhadu: `ConversationQuery`
    /// bere `first: 100` z každého seznamu (review, vlákna, komentáře, události), takže osa má
    /// nejvýš čtyři stovky uzlů — a právě proto se dá rozvrhnout celá.
    static let sizes = [44, 150, 300, 400]

    /// Co stojí **první rozvržení**, tedy přepnutí na záložku `Konverzace`.
    ///
    /// Měří se `layoutSubtreeIfNeeded()` nad čerstvě postaveným oknem, střídavě (A/B/A/B). Vedle
    /// času se vypisuje **výška obsahu a počet prvků** — bez nich by číslo netvrdilo nic: pevný
    /// stack má vyrobit všechny uzly, líný jen viditelné, a kdyby se to obrátilo, měří se něco
    /// jiného, než co se hledá.
    @Test("Kolik stojí první rozvržení osy")
    func firstLayoutCost() throws {
        for count in Self.sizes {
            var times: [ConversationAxisShape: [Double]] = [:]
            var facts: [ConversationAxisShape: String] = [:]
            for _ in 0..<3 {
                for shape in ConversationAxisShape.allCases {
                    let (elapsed, fact) = measureFirstLayout(shape: shape, count: count)
                    times[shape, default: []].append(elapsed)
                    facts[shape] = fact
                }
            }
            for shape in ConversationAxisShape.allCases {
                let values = times[shape] ?? []
                print("MĚŘENÍ první rozvržení \(count) uzlů, \(shape.rawValue): "
                    + values.map { String(format: "%.1f", $0) }.joined(separator: " / ")
                    + " ms — \(facts[shape] ?? "")")
            }
        }
    }

    /// Co stojí **projíždění**, tedy to, co uživatel na ose dělá nejčastěji.
    ///
    /// Gesto je skutečné (`WheelGesture`), protože programový posun živé scrollování nespustí
    /// a `LazyLayoutViewCache` si právě při něm říká o předběžné načtení. Střídá se A/B/A/B.
    @Test("Kolik stojí projíždění osy")
    func scrollingCost() throws {
        var costs: [ConversationAxisShape: [Double]] = [:]
        for _ in 0..<2 {
            for shape in ConversationAxisShape.allCases {
                let rows = Self.rows(count: 300)
                let window = show(rows: rows, shape: shape)
                defer { window.orderOut(nil) }
                _ = spinMainRunLoop(seconds: 2)
                // `#require`, ne `try?` — sonda bez scrolleru měří prázdno a to se nesmí
                // schovat do `continue`.
                let root = try #require(window.contentView)
                let scroller = try #require(Self.tallestScroller(in: root))
                let started = mainThreadCPUSeconds()
                let landed = WheelGesture.scroll(over: scroller, in: window, steps: 150, step: 40)
                let cost = mainThreadCPUSeconds() - started
                costs[shape, default: []].append(cost)
                print(String(
                    format: "MĚŘENÍ projíždění, %@: %.2f s CPU, dojelo na %.0f z obsahu %.0f",
                    shape.rawValue,
                    cost,
                    landed,
                    scroller.documentView?.frame.height ?? 0
                ))
            }
        }
        for shape in ConversationAxisShape.allCases {
            let values = costs[shape] ?? []
            print("MĚŘENÍ projíždění 300 uzlů, \(shape.rawValue): "
                + values.map { String(format: "%.2f", $0) }.joined(separator: " / ") + " s CPU")
        }
    }

    /// **Strukturální doklad**: co je v evaluačním zásobníku, když se `ForEach` ptá na identitu
    /// řádku osy.
    ///
    /// U líného seznamu tam `LazySubview*` atributy jsou — a jeden z nich je `LazySubviewPlacements`,
    /// tedy ten, jehož `placeSubviews` drží 60 % hořícího kola. U pevného stacku tam nemají jak
    /// vzniknout; nula je to jediné, co se o té změně dá tvrdit **bez** vyrobeného záchvatu.
    @Test("Co je v grafu pod osou")
    func graphUnderTheAxis() throws {
        #expect(GraphProbe.prepare(), "AttributeGraph nejde otevřít, sonda nemá čím měřit")
        for shape in ConversationAxisShape.allCases {
            let collector = GraphStackCollector()
            let rows = Self.rows(count: 300, collector: collector)
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

    /// Hoří osa dál, když se dojezdí? **Nedokazuje to nic** (kolo se v harnessu nepovedlo vyrobit
    /// ani počtrnácté) — je to kontrola, že se pevný stack nechová hůř než líný.
    @Test("Hoří osa po projetí?")
    func burnAfterScrolling() throws {
        for shape in ConversationAxisShape.allCases {
            let rows = Self.rows(count: 300)
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

    /// Jedno postavení okna a jeho první rozvržení. Vrací čas v milisekundách a to, co v okně
    /// doopravdy vzniklo.
    private func measureFirstLayout(shape: ConversationAxisShape, count: Int) -> (Double, String) {
        let rows = Self.rows(count: count)
        let host = NSHostingView(rootView: ShapedConversationAxis(rows: rows, shape: shape))
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        let started = Date()
        host.layoutSubtreeIfNeeded()
        let elapsed = Date().timeIntervalSince(started) * 1000
        let content = Self.tallestScroller(in: host)?.documentView?.frame.height ?? 0
        let fact = "obsah \(Int(content)) pt, \(Self.descendants(of: host)) prvků"
        window.orderOut(nil)
        return (elapsed, fact)
    }

    private static func rows(count: Int, collector: GraphStackCollector? = nil) -> [SampledConversationRow] {
        let entries = ConversationFixture.entries(comments: count)
        return Policy.conversationRows(of: entries, since: nil)
            .map { SampledConversationRow(row: $0, collector: collector) }
    }

    /// Okno **na obrazovce** — zakryté okno nedostává takt překreslování (#350), takže by se
    /// měřilo něco jiného, než co je v aplikaci vidět.
    private func show(rows: [SampledConversationRow], shape: ConversationAxisShape) -> NSWindow {
        let host = NSHostingView(
            rootView: ShapedConversationAxis(rows: rows, shape: shape).background(Palette.background)
        )
        host.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.setContentSize(NSSize(width: 1000, height: 800))
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        // Nad ostatními okny, ale bez aktivace — fokus si sonda brát nesmí (#350).
        window.level = .floating
        window.orderFrontRegardless()
        return window
    }

    private static func descendants(of view: NSView) -> Int {
        view.subviews.reduce(1) { $0 + descendants(of: $1) }
    }

    private static func tallestScroller(in view: NSView) -> NSScrollView? {
        var best = view as? NSScrollView
        for child in view.subviews {
            guard let found = tallestScroller(in: child) else { continue }
            let height = found.documentView?.frame.height ?? 0
            if height > (best?.documentView?.frame.height ?? 0) { best = found }
        }
        return best
    }
}

/// Které podoby toho jednoho místa se poměřují. **Jen dvě** — cokoli mezi tím (líný seznam až nad
/// N uzly) má tu vazbu pořád, jen v méně případech, a rozhodnutí by pak stálo na tom, jak často
/// jsou osy dlouhé, místo na tom, jestli kolo může vzniknout.
enum ConversationAxisShape: String, CaseIterable {
    /// `LazyVStack` — podoba do patnáctého kola #361.
    case lazyStack = "LazyVStack"
    /// `VStack` — podoba, kterou má aplikace od patnáctého kola.
    case eager = "VStack"
    /// `List` — líné vykreslování **v AppKitu** (`NSTableView`), tedy laznost mimo lazy layout
    /// SwiftUI. Měřená alternativa: kdyby v grafu neměla `LazySubview*` a přitom držela levné
    /// první rozvržení, byla by lepší než obě.
    case list = "List"
}

/// Řádek osy plus **hák sondy**: přečtení identity odebere vzorek evaluačního zásobníku.
///
/// V aplikaci tuhle roli hraje `ConversationRow.diagnosedID` (`GraphSite`), ale ten píše do
/// `RenderDiagnostics` a má rozpočet osmi vzorků na úsek. Sonda potřebuje histogram, takže si
/// bere vlastní počítadlo — a **mimo observable stav**, jinak by měřila sebe.
struct SampledConversationRow: Identifiable {
    let row: ConversationRow
    let collector: GraphStackCollector?

    var id: String {
        // `MainActor.assumeIsolated`, protože getter identity je `nonisolated` a `ForEach` si ho
        // čte z hlavního vlákna uvnitř aktualizace grafu — tatáž konstrukce jako `SampledRow`.
        if let collector { MainActor.assumeIsolated { collector.note() } }
        return row.id
    }
}

/// Osa konverzace ve **dvou podobách**: tvar je opsaný z `ConversationView` (lišta, seznam
/// v `fillingSlot()`, composer pod ním, odsazení 16 a `narrowingWidth(by: 32)`), řádky jsou
/// **skutečné** `ConversationNodeView`.
///
/// Proč kopie a ne přepínač v aplikaci: podoba s `LazyVStack`em je **zamítnutá varianta**, takže
/// patří do sondy, ne do `App/` — tatáž úvaha jako u `TimelineShape.declaredIdeal`. Kdyby ji
/// aplikace nesla jako pole, které nastavuje jedině test, byl by to stav, který nikdo nečte.
struct ShapedConversationAxis: View {
    let rows: [SampledConversationRow]
    let shape: ConversationAxisShape

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { proxy in
                axis
                    .availableWidth(proxy.size.width)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var axis: some View {
        VStack(spacing: 0) {
            Text(verbatim: "lišta").padding(9).frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Palette.lineSoft).frame(height: 1)
            timeline.fillingSlot()
            Text(verbatim: "composer").padding(9).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var timeline: some View {
        if shape == .list {
            List(rows) { row in
                ConversationNodeView(node: row.row.node, viewer: "octocat")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(16)
            .narrowingWidth(by: 32)
        } else {
            ScrollView {
                stack
                    .padding(16)
                    .narrowingWidth(by: 32)
            }
        }
    }

    @ViewBuilder private var stack: some View {
        switch shape {
        case .lazyStack:
            LazyVStack(alignment: .leading, spacing: 0) { nodes }
        case .eager:
            VStack(alignment: .leading, spacing: 0) { nodes }
        case .list:
            EmptyView()
        }
    }

    private var nodes: some View {
        ForEach(rows) { row in
            ConversationNodeView(node: row.row.node, viewer: "octocat")
        }
    }
}
