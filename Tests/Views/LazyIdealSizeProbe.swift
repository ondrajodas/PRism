import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda k #361: **kolikrát se někdo zeptá líného seznamu na ideální velikost — a co to stojí.**
///
/// Devátý záchvat dal poprvé celý zásobník hořícího kola a v něm tuhle řadu (1524 z 13 479 vzorků
/// hlavního vlákna):
///
/// ```
/// StackLayout.UnmanagedImplementation.prioritize(_:proposedSize:)
///   _FlexFrameLayout.sizeThatFits(in:context:child:)
///     ScrollViewLayoutComputer.Engine.sizeThatFits(_:)
///       _PaddingLayout.sizeThatFits(in:context:child:)
///         LazyVStackLayout.sizeThatFits(proposedSize:subviews:context:cache:)
///           LazyStack<>.measureEstimates(updatingPosition:index:minor:subviews:cache:)
///             _LazyLayout_Subviews.apply(from:style:to:) → ForEachList.applyNodes → …
/// ```
///
/// Přeloženo do kódu je to jedna cesta v `ConversationView`: `VStack` rozděluje výšku, takže se
/// zeptá pružného rámce nad osou (`timeline.frame(maxHeight: .infinity)`) na **ideální** výšku,
/// ten se zeptá `ScrollView`u a ten svého obsahu, tedy `LazyVStack`u. Líný seznam na to odpoví
/// jedině průchodem **celého** `ForEach`e — odtud 7,1 milionu dotazů na `ConversationRow.id`.
/// A ta funkce se jmenuje `measureEstimates(**updatingPosition**:…)`, takže ten dotaz do stavu
/// líného seznamu **zapisuje**; ve stejném kole ho čte a přepisuje `placeSubviews`.
///
/// Sonda proto počítá tři čísla: dotazy na **ideální** výšku, dotazy s **danou** výškou a dotazy
/// na identitu řádku. Scénáře jsou dva a druhý je zároveň kontrola měřidla:
///
/// - `pružná výška` — `.frame(maxHeight: .infinity)` nad `ScrollView`em uvnitř `VStack`u, tedy
///   podoba, kterou aplikace měla do #361;
/// - `změřená výška` — tentýž strom, jen `ScrollView` dostane výšku **změřenou**
///   (`GeometryReader`), takže se dotaz na ideální velikost k němu nedostane vůbec.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`. Tvrzení, které z toho zbylo do každodenního
/// běhu, je `LazyIdealSizeTests`.
@MainActor
@Suite(
    "Ideální velikost líného seznamu (#361)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct LazyIdealSizeProbe {
    @Test("Kolik dotazů na velikost dostane líný seznam")
    func idealSizeQuestions() throws {
        for shape in TimelineShape.allCases {
            let counter = LazySizeCounter()
            let window = show(rootView: TimelineShapedList(counter: counter, shape: shape))
            defer { window.orderOut(nil) }
            _ = spinMainRunLoop(seconds: 1.5)
            print("SONDA \(shape.rawValue), rozvržení:"
                + " ideální výška \(counter.idealHeight)×, ideální šířka \(counter.idealWidth)×,"
                + " daná \(counter.definite)×, identita řádku \(counter.identity)×,"
                + " návrhy \(counter.proposalSummary)")
            counter.reset()
            let cpu = spinMainRunLoop(seconds: 4)
            print("SONDA \(shape.rawValue), nečinné okno:"
                + " ideální výška \(counter.idealHeight)×, daná \(counter.definite)×,"
                + " identita řádku \(counter.identity)×,"
                + " CPU hlavního vlákna \(String(format: "%.3f", cpu)) s ze 4 s")
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

/// Počty mimo observable stav — kdyby to byl `@State`, počítadlo by špinilo graf a sonda by měřila
/// sebe (tatáž úvaha jako u `LayoutCallbackProbe.Counter`).
@MainActor final class LazySizeCounter {
    /// Dotazy, ve kterých výška **není** navržená — tedy „jak vysoký bys chtěl být“.
    var idealHeight = 0
    var idealWidth = 0
    var definite = 0
    var identity = 0
    /// Navržené velikosti, jak přišly — bez nich se nepozná, jestli se dotaz na ideál jen
    /// nepřevlékl za dotaz s nulovou výškou.
    var proposals: [String] = []

    func reset() {
        idealHeight = 0
        idealWidth = 0
        definite = 0
        identity = 0
        proposals = []
    }

    /// Histogram navržených velikostí, od nejčastější.
    var proposalSummary: String {
        let counts = proposals.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}

/// Které podoby toho jednoho místa se poměřují.
enum TimelineShape: String, CaseIterable {
    /// `.frame(maxHeight: .infinity)` — podoba, kterou aplikace měla do #361.
    case flexible = "pružná výška"
    /// `fillingSlot()` z aplikace — týž pružný rámec, jen s vyplněným ideálem, takže na „jak
    /// velký bys chtěl být“ odpovídá rámec sám, bez dotazu dolů.
    case declaredIdeal = "vyplněný ideál"
    /// Výška změřená `GeometryReader`em.
    case measured = "změřená výška"
}

/// Strom **stejného tvaru jako osa konverzace**: lišta, seznam a composer v jednom `VStack`u.
/// `shape` přepíná právě to jedno místo, o které jde — jak seznam dostane výšku.
struct TimelineShapedList: View {
    let counter: LazySizeCounter
    let shape: TimelineShape
    /// Kolik řádků seznam má. Musí jich být **výrazně víc, než se vejde do okna** — právě rozdíl
    /// mezi „viditelné“ a „všechny“ je to, co se měří.
    var rowCount = 300

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "lišta").padding(9).frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.gray).frame(height: 1)
            switch shape {
            case .flexible:
                list.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .declaredIdeal:
                list.fillingSlot()
            case .measured:
                // `GeometryReader` si ideální velikost dítěte **nezjišťuje** — vrací, co se mu
                // navrhlo —, takže se dotaz na ideální výšku k `ScrollView`u nedostane.
                GeometryReader { proxy in
                    list.frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            Text(verbatim: "composer").padding(9).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var list: some View {
        SizeQuestionReport(counter: counter) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.countedID) { row in
                        // Výšky se schválně hodně liší — u osy konverzace stojí vedle sebe
                        // jednořádková událost a komentář na půl obrazovky, a právě na rozptylu
                        // výšek stojí to, jak líný seznam odhaduje. A **zalomený** text je na tom
                        // to podstatné: na nenavržené šířce se nezalomí vůbec, takže dotaz na
                        // ideální velikost vrátí jinou výšku než rozvržení na skutečné šířce.
                        Text(verbatim: row.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(16)
            }
        }
    }

    private var rows: [CountedRow] {
        (0..<rowCount).map { CountedRow(index: $0, counter: counter) }
    }
}

/// Řádek, který si hlásí dotaz na identitu — tedy tu cestu, na které v hořícím kole leželo
/// 7,1 milionu zásahů `ConversationRow.id`.
private struct CountedRow {
    let index: Int
    let counter: LazySizeCounter

    var countedID: Int {
        MainActor.assumeIsolated { counter.identity += 1 }
        return index
    }

    /// Krátká událost, nebo dlouhý komentář — jako na ose konverzace.
    var text: String {
        guard index % 7 == 0 else { return "Řádek \(index) — krátká událost" }
        return String(
            repeating: "Řádek \(index): dlouhý komentář, který se na skutečné šířce zalomí. ",
            count: 6
        )
    }
}

/// Rozvržení o jednom dítěti, které jen **počítá dotazy na velikost** a rozlišuje, jestli v nich
/// byla výška navržená. Jiná cesta, jak se ze SwiftUI dozvědět „na tohle se někdo ptal jako na
/// ideální rozměr“, nevede.
struct SizeQuestionReport<Content: View>: View {
    let counter: LazySizeCounter
    @ViewBuilder var content: Content

    var body: some View {
        SizeQuestionLayout(counter: counter) { content }
    }
}

private struct SizeQuestionLayout: Layout {
    let counter: LazySizeCounter

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Rozvržení běží na hlavním vlákně, ale protokol to netvrdí — `assumeIsolated` je proto
        // tady, ne `nonisolated(unsafe)` u počitadla.
        MainActor.assumeIsolated {
            if proposal.height == nil { counter.idealHeight += 1 }
            if proposal.width == nil { counter.idealWidth += 1 }
            if proposal.height != nil && proposal.width != nil { counter.definite += 1 }
            counter.proposals.append("\(proposal.width.map { "\($0)" } ?? "nil")×"
                + (proposal.height.map { "\($0)" } ?? "nil"))
        }
        return subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}
