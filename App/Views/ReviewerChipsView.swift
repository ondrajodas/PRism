import SwiftUI

/// Chipy reviewerů: co který udělal a jestli jsou jeho nálezy vidět.
///
/// Dvě věci naráz — stav a filtr. Vypnutý chip je ztlumený a jeho nálezy zmizí z bublin
/// i z tabulky.
struct ReviewerChipsView: View {
    let chips: [ReviewerChip]
    /// Reviewery, jejichž nálezy jsou schované.
    @Binding var muted: Set<String>
    /// Pustit znovu jen tohohle revieweera (#149). `nil` = odsud se nespouští (náhledy, testy).
    var rerun: ((String) -> Void)?
    /// Běží nad tímhle PR review? Dokud běží, nejde spustit nic dalšího — je to jedna úloha
    /// na PR, viz `AppStore.RunningReview`.
    var isReviewing = false

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
                // Nálezy dorazily, ale ne všechny — bez tohohle vypadá neúplný výsledek
                // jako úplný.
                if chip.warning != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
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
        .contextMenu { rerunItem(chip) }
    }

    /// Opakování jednoho revieweera (#149).
    ///
    /// **Kontextové menu, ne druhé tlačítko v chipu.** Chip je malý a jeho kliknutí už patří
    /// filtru, který se používá mnohem častěji; ikonka navíc by se do něj mačkala a trefovala
    /// by se hůř než ta, kterou by nahradila. Že tam menu je, říká nápověda.
    ///
    /// Dokud nad PR běží review, je položka **zakázaná, ne schovaná**: důvod je vidět
    /// o kousek vedle (chip se spinnerem) a za chvíli sám zmizí — kdežto menu, které se občas
    /// neobjeví, vypadá jako závada. Tatáž úvaha jako u tlačítka `Odpovědět` ve vlákně.
    @ViewBuilder private func rerunItem(_ chip: ReviewerChip) -> some View {
        if let rerun {
            Button(chip.state == .notStarted ? "Pustit jen tohohle revieweera" : "Pustit znovu jen tohohle revieweera") {
                rerun(chip.skill)
            }
            .disabled(isReviewing)
        }
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
        case .interrupted: "bolt.horizontal.circle"
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
        case .interrupted(let count): count > 0 ? "přerušeno · \(count)" : "přerušeno"
        }
    }

    private func color(_ state: ReviewerChip.State) -> Color {
        switch state {
        case .clean: .green
        case .findings: .orange
        case .failed: .red
        case .inconclusive, .timedOut, .interrupted: .orange
        case .notStarted, .running: .secondary
        }
    }

    private func background(_ state: ReviewerChip.State) -> Color {
        switch state {
        case .failed: .red.opacity(0.08)
        case .findings, .inconclusive, .timedOut, .interrupted: .orange.opacity(0.08)
        default: .gray.opacity(0.08)
        }
    }

    /// Nápověda chipu: co se stalo, **co to stálo** a co udělá kliknutí.
    ///
    /// Cena (#148) se bere z uloženého záznamu, takže je tady i po restartu — osa v tabu
    /// `Průběh` je jen v paměti, takže po něm ukáže „zatím se nic nedělo“ a uložená cena by
    /// jinak neměla čtenáře.
    private func help(_ chip: ReviewerChip, isMuted: Bool) -> String {
        var action = isMuted ? "Zobrazit nálezy tohohle revieweera" : "Skrýt nálezy tohohle revieweera"
        // Bez téhle věty se o opakování nikdo nedozví: kontextové menu na chipu není nic,
        // co by šlo uhodnout.
        if rerun != nil {
            action += "\nPravým tlačítkem: pustit znovu jen jeho, bez ostatních."
        }
        let usage = chip.usage.flatMap(RunUsageText.summary(of:))
        return [state(of: chip), usage, action].compactMap { $0 }.joined(separator: "\n\n")
    }

    /// Věta o tom, jak běh dopadl. `nil` u stavů, ke kterým není co dodat — samotné „čisté“
    /// říká chip sám a druhá věta o tomtéž je šum.
    private func state(of chip: ReviewerChip) -> String? {
        if let warning = chip.warning { return warning }
        switch chip.state {
        case .failed(let detail): return detail
        case .inconclusive(let reason): return reason
        case .timedOut: return "Session nedoběhla v limitu; co stihla nahlásit, je vidět."
        case .interrupted:
            return "Session skončila s aplikací (pád nebo zabití). Nálezy jsou dotažené "
                + "z transcriptu, takže je jich tolik, kolik jich do té chvíle dorazilo."
        default: return nil
        }
    }
}
