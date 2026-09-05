import SwiftUI

/// Jedna kapsle fáze na dráze (`.ph` z návrhu).
///
/// **Vlastní typ od #508, protože dráhy jsou dvě.** Do té doby to byla privátní metoda uvnitř
/// `ReviewerLaneView` a nikomu to nevadilo — smyčka vlastního PR (#508) je ale tentýž proces
/// kreslený tímtéž jazykem, a druhá kopie mapování `PhaseState → barva` by znamenala, že se
/// `hotovo` v jedné dráze časem obarví jinak než ve druhé. Že je to **jedno místo**, je tvrzení
/// testu (`LanePhaseChipTests`), ne jen tenhle komentář.
///
/// Chip **vyplní svůj podíl** (`.ph { flex }`), jinak jsou mezi fázemi mezery a dráhy se nedají
/// porovnat — a porovnání je jediný důvod, proč fáze stojí vedle sebe. `.infinity` je tady
/// bezpečné (a #220 to nezakazuje): `ProportionalColumns` navrhuje **konkrétní** šířku, takže se
/// nevyjednává, jen se roztáhne na to, co dostal.
struct LanePhaseChip: View {
    let title: String
    /// Co se v té fázi stalo — počet kroků, počet nálezů, `o 4 vzadu`. `nil` = není co dodat.
    let detail: String?
    let state: ReviewerLane.PhaseState

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: title)
                .lineLimit(1)
            if let detail {
                Text(verbatim: detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let mark = Self.mark(of: state) {
                Image(systemName: mark).font(.system(size: 8))
            }
        }
        .font(.system(size: 10.5, weight: state == .running ? .semibold : .regular))
        .foregroundStyle(Self.tint(of: state))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 23)
        .background(Self.background(of: state), in: .rect(cornerRadius: 5))
        .accessibilityElement(children: .combine)
        // Stav **té fáze**, ne celé dráhy: ten by u všech fází přečetl totéž.
        .accessibilityValue(ReviewerLaneText.phase(state))
    }

    /// Značka za popiskem. **`idle` nemá žádnou** — fáze, na kterou nedošlo, není ani hotová,
    /// ani rozbitá, a jakýkoli symbol by o ní tvrdil, že se něco stalo. Totéž platí o `unknown`:
    /// tam se neví, jak dopadla, takže značka by si vybírala za nás.
    static func mark(of state: ReviewerLane.PhaseState) -> String? {
        switch state {
        case .done: "checkmark"
        case .failed: "xmark"
        case .stopped: "minus"
        case .running, .idle, .unknown: nil
        }
    }

    static func tint(of state: ReviewerLane.PhaseState) -> Color {
        switch state {
        case .done: Palette.ok
        case .running: Palette.find
        case .failed: Palette.crit
        case .stopped: Palette.stale
        case .idle, .unknown: Palette.ink3
        }
    }

    static func background(of state: ReviewerLane.PhaseState) -> Color {
        switch state {
        case .idle, .unknown: Palette.raised
        default: tint(of: state).opacity(0.16)
        }
    }
}
