import SwiftUI

/// Odznak se stavem review v řádku seznamu.
///
/// Text i barvu drží `ReviewStateAppearance` — od #172 je potřebuje i proužek na hraně řádku
/// a dvě kopie téhož `switch`e by se rozešly.
struct ReviewStateBadge: View {
    let state: ReviewState
    /// Kolik nálezů blokuje. Mění text i barvu: „3 nálezy“ oranžově je práce,
    /// „3 nálezy · 1 blokuje“ červeně je zastavený merge.
    var blocking = 0

    var body: some View {
        Text(verbatim: ReviewStateAppearance.label(of: state, blocking: blocking))
            .font(.caption)
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }

    private var color: Color {
        ReviewStateAppearance.color(of: state, blocking: blocking)
    }
}

#Preview {
    VStack(alignment: .leading) {
        ReviewStateBadge(state: .notStarted)
        ReviewStateBadge(state: .running(finished: 2, total: 3))
        ReviewStateBadge(state: .clean)
        ReviewStateBadge(state: .completed(findings: 9))
        ReviewStateBadge(state: .completed(findings: 3), blocking: 1)
        ReviewStateBadge(state: .dismissed(findings: 3))
        ReviewStateBadge(state: .timedOut(findings: 2), blocking: 1)
        ReviewStateBadge(state: .failed(detail: "boom"))
        ReviewStateBadge(state: .inconclusive(reason: .unreadCode))
        ReviewStateBadge(state: .inconclusive(reason: .noReport))
        ReviewStateBadge(state: .inconclusive(reason: .droppedFindings))
        ReviewStateBadge(state: .stale)
    }
    .padding()
}
