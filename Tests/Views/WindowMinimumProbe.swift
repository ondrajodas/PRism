import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda k #472: **kolikrát a s jakou nabídkou se okno ptá kořene na rozměr.**
///
/// `.windowResizability(.contentMinSize)` znamená, že si AppKit při každém průchodu
/// `updateConstraints` řekne o **minimum obsahu** — a hostující vrstva na to spustí druhou
/// aktualizaci grafu, tedy rozvrhne celé okno ještě jednou. Ve `sample`u z měření #472 drží
/// `updateWindowContentSizeExtremaIfNecessary` 15–50 % rozvržení podle fáze.
///
/// Aby se to dalo zlevnit, musí se vědět **čím se ten dotaz pozná**. Tahle sonda si posadí do
/// kořene `Layout`, který si zapisuje každou nabídku, a vypíše je: dotaz na minimum je nabídka
/// **`0×0`** a objeví se **jedině** se `sizingOptions = [.minSize]`.
///
/// **Zlevnit to tudy nešlo, a je to změřené** (#472). `Layout`, který na `0×0` odpoví konstantou
/// místo aby se zanořil, ten sestup doopravdy zastaví (ověřeno druhou podobou téhle sondy:
/// pod kořenem zbyla jedna nabídka místo dvou) — a **na ceně nezměnil nic**: 94 ms proti 98 ms
/// na přerovnání okna, tedy uvnitř rozptylu. Cena té druhé aktualizace grafu není v tom
/// sestupu. Sonda proto zůstává jako **doklad, ne jako příprava opravy**.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Na co se okno ptá kořene (#472)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct WindowMinimumProbe {
    @Test("Jaké nabídky dostane kořen okna")
    func proposalsAtTheRoot() throws {
        for options in [NSHostingSizingOptions([.minSize]), NSHostingSizingOptions()] {
            let log = ProposalLog()
            let host = NSHostingView(
                rootView: RecordingLayout(log: log) {
                    Color.blue.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            )
            host.sizingOptions = options
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFrontUnanimated()
            defer { window.orderOut(nil) }
            _ = spinMainRunLoop(seconds: 1)
            log.mark()
            window.setContentSize(NSSize(width: 880, height: 580))
            _ = spinMainRunLoop(seconds: 0.5)

            print("SONDA sizingOptions \(options.contains(.minSize) ? "[.minSize]" : "[]"):"
                + " \(log.all.count) nabídek celkem, po změně velikosti \(log.sinceMark.count)")
            for entry in log.digest { print("SONDA   \(entry)") }
            print("SONDA   contentMinSize okna: \(window.contentMinSize)")
        }
    }
}

/// Zapisovač nabídek. Třída, aby do něj šlo psát z `Layout`u, který je hodnota.
@MainActor final class ProposalLog {
    private(set) var all: [ProposedViewSize] = []
    private var marked = 0

    func note(_ proposal: ProposedViewSize) { all.append(proposal) }
    func mark() { marked = all.count }
    var sinceMark: [ProposedViewSize] { Array(all.dropFirst(marked)) }

    /// Histogram nabídek — o tom, které se opakují, řekne víc než jejich výpis.
    var digest: [String] {
        var counts: [String: Int] = [:]
        for proposal in all {
            let width = proposal.width.map { String(format: "%.0f", $0) } ?? "nil"
            let height = proposal.height.map { String(format: "%.0f", $0) } ?? "nil"
            counts["\(width)×\(height)", default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map { "nabídka \($0.key): \($0.value)×" }
    }
}

/// Kořen, který si každou nabídku zapíše a jinak jen umístí své dítě přes celou plochu.
struct RecordingLayout<Content: View>: View {
    let log: ProposalLog
    @ViewBuilder let content: Content

    var body: some View {
        RecordingLayoutImplementation(log: log) { content }
    }
}

struct RecordingLayoutImplementation: Layout {
    let log: ProposalLog

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        MainActor.assumeIsolated { log.note(proposal) }
        return subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}
