import SwiftUI

/// Odznak se stavem review v řádku seznamu.
///
/// Každý stav má vlastní text i barvu — `clean` a `failed` se nesmí slít, protože říkají
/// opak jedno o druhém. Kolik nálezů blokuje, tenhle typ nepočítá; to je `Policy` (#16),
/// takže `completed` zatím ukazuje jen počet.
struct ReviewStateBadge: View {
    let state: ReviewState

    var body: some View {
        Text(label)
            .font(.caption)
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }

    private var label: String {
        switch state {
        case .notStarted: "neběželo"
        case .queued: "ve frontě"
        case .cloning: "ve frontě · clone"
        case .checkoutFailed: "clone selhal"
        case .running(let finished, let total): "běží \(finished)/\(total)"
        case .clean: "čisté"
        case .completed(let findings): Plural.czech(findings, one: "nález", few: "nálezy", many: "nálezů")
        // Ne „čisté“: reviewer našel a já to zamítl, což je jiné tvrzení. Počet zůstává, ať
        // je z řádku poznat, kolik jsem toho přeskočil.
        case .dismissed(let findings): "odmítnuto · \(findings)"
        case .failed: "selhalo"
        case .timedOut: "timeout"
        // Ne „timeout“: běh neskončil limitem, ale s aplikací — a dělá se s tím něco jiného.
        case .interrupted: "přerušeno"
        case .stale: "zastaralé"
        }
    }

    private var color: Color {
        switch state {
        case .notStarted, .queued, .cloning: .secondary
        case .running: .accentColor
        case .clean: .green
        // Vlastní barva, ne zelená ani oranžová: vyřízeno to je, ale ne tím, že by bylo
        // čisto — a od nálezů, které čekají, se to musí poznat i bez čtení textu.
        case .dismissed: .mint
        case .completed: .orange
        case .checkoutFailed, .failed, .timedOut, .interrupted: .red
        case .stale: .yellow
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        ReviewStateBadge(state: .notStarted)
        ReviewStateBadge(state: .running(finished: 2, total: 3))
        ReviewStateBadge(state: .clean)
        ReviewStateBadge(state: .completed(findings: 9))
        ReviewStateBadge(state: .dismissed(findings: 3))
        ReviewStateBadge(state: .failed(detail: "boom"))
        ReviewStateBadge(state: .stale)
    }
    .padding()
}
