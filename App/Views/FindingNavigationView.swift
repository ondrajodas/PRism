import SwiftUI

/// Procházení nálezů v liště nad diffem (#187).
///
/// Cesta k dalšímu nálezu vedla dosud přes panel — najít ho v seznamu a kliknout. U PR s dvaceti
/// nálezy to znamená, že seznam musí být pořád vidět; tohle ho z té role vyvazuje. Panel zůstává
/// **přehledem**, protože z procházení po jednom se poskládat nedá.
struct FindingNavigationView: View {
    let navigation: FindingNavigation
    @Binding var onlyBlocking: Bool
    let step: (NavigationStep) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: navigation.isComplete ? "checkmark.circle.fill" : "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(navigation.isComplete ? .green : .orange)
            Text(verbatim: counter)
                .font(.callout)
                .monospacedDigit()
            Divider().frame(height: 14)
            arrow(.backward, symbol: "chevron.up", enabled: navigation.hasPrevious)
            arrow(.forward, symbol: "chevron.down", enabled: navigation.hasNext)
            Toggle("jen blokující", isOn: $onlyBlocking)
                .toggleStyle(.checkbox)
                .font(.callout)
                .help("Skákat jen po nálezech, kvůli kterým se PR nemerguje")
        }
        .help(explanation)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Procházení nálezů")
        .accessibilityValue(explanation)
    }

    /// Šipka na kraji **zhasne, ne zmizí**: tlačítko, které se ztratí, vypadá jako porucha
    /// a ruší rozvržení lišty pod rukama.
    private func arrow(_ direction: NavigationStep, symbol: String, enabled: Bool) -> some View {
        Button { step(direction) } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(direction == .forward ? "Další nález (⌥↓)" : "Předchozí nález (⌥↑)")
        .accessibilityLabel(direction == .forward ? "Další nález" : "Předchozí nález")
    }

    /// `2/3`, nebo jen `3` před prvním skokem. **Ne `0/3`** — nula by tvrdila, že stojím na
    /// nultém nálezu, kdežto pravda je, že nikde nestojím.
    private var counter: String {
        guard let position = navigation.position else { return "\(navigation.total)" }
        return "\(position)/\(navigation.total)"
    }

    /// Celá věta patří do nápovědy, ne do lišty — ta je úzká a soutěží o místo s diffem.
    /// Musí být poctivá ve dvou věcech: kolik zbývá a co se do procházení **nevešlo**.
    private var explanation: String {
        var lines: [String] = []
        if navigation.total == 0 {
            lines.append("Žádný nález se neváže k místu v diffu.")
        } else if navigation.isComplete {
            lines.append("Prošel jsi všechna místa (\(navigation.total)).")
        } else if let position = navigation.position {
            lines.append("Stojíš na \(position). z \(navigation.total) míst s nálezem.")
        } else {
            lines.append("\(navigation.total) míst s nálezem; zatím jsi nikam neskočil.")
        }
        if navigation.withoutPlace > 0 {
            // Bez tohohle by „3 ze 3“ tvrdilo hotovo nad PR, kde zbývají nálezy v panelu.
            lines.append(
                "\(Plural.czech(navigation.withoutPlace, one: "Nález", few: "Nálezy", many: "Nálezů")) "
                    + "bez místa v kódu se prochází v panelu — sem se skočit nedá."
            )
        }
        if onlyBlocking {
            lines.append("Šipky přeskakují všechno, co neblokuje.")
        }
        lines.append("Odmítnuté nálezy se přeskakují.")
        return lines.joined(separator: "\n")
    }
}

#Preview {
    @Previewable @State var onlyBlocking = false
    return VStack(alignment: .leading, spacing: 14) {
        FindingNavigationView(
            navigation: FindingNavigation(
                position: nil, total: 3, hasPrevious: false, hasNext: true,
                isComplete: false, withoutPlace: 1
            ),
            onlyBlocking: $onlyBlocking,
            step: { _ in }
        )
        FindingNavigationView(
            navigation: FindingNavigation(
                position: 2, total: 3, hasPrevious: true, hasNext: true,
                isComplete: false, withoutPlace: 0
            ),
            onlyBlocking: $onlyBlocking,
            step: { _ in }
        )
        FindingNavigationView(
            navigation: FindingNavigation(
                position: 3, total: 3, hasPrevious: true, hasNext: false,
                isComplete: true, withoutPlace: 0
            ),
            onlyBlocking: $onlyBlocking,
            step: { _ in }
        )
    }
    .padding()
}
