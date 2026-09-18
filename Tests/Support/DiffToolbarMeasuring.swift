import AppKit
import SwiftUI

@testable import PRism

/// Změří prvek lišty nad diffem **tou cestou, kterou ho měří aplikace** (#593).
///
/// Lišta je vlastní `Layout` a měření podviews je v `Layout`u jediná cesta, jak se dozvědět, oč
/// si prvek říká celý (`.unspecified`) a na co se srazí (`full - 1`). Druhá kopie toho měření
/// v `Tests/` by měřila něco jiného než aplikace, takže se tady volá **`DiffToolbarLayout.measures(of:)`**
/// doslova — jen se výsledek zachytí.
///
/// `NSHostingView` je offscreen, což u šířky stačí: accessibility tree se offscreen nenaplní
/// (#269), ale `sizeThatFits` odpoví.
@MainActor
enum DiffToolbarMeasuring {
    /// Změřené prvky v pořadí, v jakém se kreslí.
    ///
    /// Bere **`@ViewBuilder`**, ne jednu hodnotu: `Layout` rozloží `TupleView` na samostatné
    /// podviews, kdežto `VStack` by byl jeden prvek — a měřilo by se něco jiného, než co lišta
    /// rozvrhuje.
    static func entries<Content: View>(
        @ViewBuilder of content: () -> Content
    ) -> [DiffToolbarLayout.Entry] {
        let sink = Sink()
        let layout = MeasuringLayout(sink: sink)
        let host = NSHostingView(rootView: layout { content() })
        host.layoutSubtreeIfNeeded()
        _ = host.fittingSize
        return sink.entries
    }

    /// Změřený prvek podle jeho identity. `nil` = ten prvek se v téhle liště nekreslí.
    static func entry<Content: View>(
        _ item: Policy.DiffToolbarItem,
        @ViewBuilder of content: () -> Content
    ) -> DiffToolbarLayout.Entry? {
        entries(of: content).first { $0.item == item }
    }

    @MainActor
    private final class Sink {
        var entries: [DiffToolbarLayout.Entry] = []
    }

    /// Rozvržení, které nic nepokládá — jen se zeptá týmiž dotazy jako `DiffToolbarLayout`.
    private struct MeasuringLayout: Layout {
        let sink: Sink

        func sizeThatFits(
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) -> CGSize {
            let measured = DiffToolbarLayout.measures(of: subviews)
            MainActor.assumeIsolated { sink.entries = measured }
            return CGSize(
                width: measured.map(\.full).reduce(0, +),
                height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            )
        }

        func placeSubviews(
            in bounds: CGRect,
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) {
            for subview in subviews {
                subview.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
            }
        }
    }
}
