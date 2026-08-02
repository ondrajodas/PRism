import SwiftUI

/// Chipy reviewerů: co který udělal a jestli jsou jeho nálezy vidět.
///
/// Dvě věci naráz — stav a filtr. Vypnutý chip je ztlumený a jeho nálezy zmizí z bublin
/// i z tabulky.
struct ReviewerChipsView: View {
    let chips: [ReviewerChip]
    /// Reviewery, jejichž nálezy jsou schované.
    @Binding var muted: Set<String>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                button(chip)
            }
        }
    }

    private func button(_ chip: ReviewerChip) -> some View {
        let isMuted = muted.contains(chip.skill)
        return Button {
            if isMuted { muted.remove(chip.skill) } else { muted.insert(chip.skill) }
        } label: {
            HStack(spacing: 5) {
                icon(chip.state)
                Text(verbatim: chip.skill).font(.callout)
                Text(verbatim: label(chip.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background(chip.state), in: .capsule)
            .overlay(Capsule().strokeBorder(.quaternary))
            .opacity(isMuted ? 0.4 : 1)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // Podrobnost (stderr, důvod nejistoty) visí na nápovědě: kliknutí patří filtru,
        // který se používá mnohem častěji.
        .help(help(chip, isMuted: isMuted))
    }

    @ViewBuilder private func icon(_ state: ReviewerChip.State) -> some View {
        switch state {
        case .running:
            ProgressView().controlSize(.mini)
        default:
            Image(systemName: symbol(state))
                .font(.caption)
                .foregroundStyle(color(state))
        }
    }

    private func symbol(_ state: ReviewerChip.State) -> String {
        switch state {
        case .notStarted: "circle.dashed"
        case .running: "circle.dotted"
        case .clean: "checkmark.circle"
        case .findings: "exclamationmark.bubble"
        case .inconclusive: "questionmark.circle"
        case .failed: "xmark.circle"
        case .timedOut: "clock.badge.exclamationmark"
        }
    }

    private func label(_ state: ReviewerChip.State) -> String {
        switch state {
        case .notStarted: "neběželo"
        case .running: "běží"
        case .clean: "čisté"
        case .findings(let count): Plural.czech(count, one: "nález", few: "nálezy", many: "nálezů")
        case .inconclusive: "nejisté"
        case .failed: "selhalo"
        case .timedOut(let count): count > 0 ? "timeout · \(count)" : "timeout"
        }
    }

    private func color(_ state: ReviewerChip.State) -> Color {
        switch state {
        case .clean: .green
        case .findings: .orange
        case .failed: .red
        case .inconclusive, .timedOut: .orange
        case .notStarted, .running: .secondary
        }
    }

    private func background(_ state: ReviewerChip.State) -> Color {
        switch state {
        case .failed: .red.opacity(0.08)
        case .findings, .inconclusive, .timedOut: .orange.opacity(0.08)
        default: .gray.opacity(0.08)
        }
    }

    private func help(_ chip: ReviewerChip, isMuted: Bool) -> String {
        let action = isMuted ? "Zobrazit nálezy tohohle revieweera" : "Skrýt nálezy tohohle revieweera"
        switch chip.state {
        case .failed(let detail): return "\(detail)\n\n\(action)"
        case .inconclusive(let reason): return "\(reason)\n\n\(action)"
        case .timedOut: return "Session nedoběhla v limitu; co stihla nahlásit, je vidět.\n\n\(action)"
        default: return action
        }
    }
}
