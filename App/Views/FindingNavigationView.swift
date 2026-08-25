import SwiftUI

/// Procházení nálezů v liště nad diffem (#187) — **jeden prvek v rámečku** (`.findnav`, #219).
///
/// Cesta k dalšímu nálezu vedla dosud přes panel — najít ho v seznamu a kliknout. U PR s dvaceti
/// nálezy to znamená, že seznam musí být pořád vidět; tohle ho z té role vyvazuje. Panel zůstává
/// **přehledem**, protože z procházení po jednom se poskládat nedá.
///
/// Do #219 to bylo pět samostatných věcí vedle sebe (puntík, číslo, dvě šipky, checkbox), takže
/// z lišty nešlo poznat, že patří k sobě — a `jen blokující` vypadalo jako přepínač celé lišty,
/// ne jako zúžení téhle jedné cesty. Rámeček z návrhu to spojuje, aniž by ubral akce.
struct FindingNavigationView: View {
    let navigation: FindingNavigation
    @Binding var onlyBlocking: Bool
    let step: (NavigationStep) -> Void

    var body: some View {
        HStack(spacing: 7) {
            dot
            label
            Rectangle()
                .fill(Palette.line)
                .frame(width: 1, height: 15)
            HStack(spacing: 1) {
                arrow(.backward, symbol: "chevron.up", enabled: navigation.hasPrevious)
                arrow(.forward, symbol: "chevron.down", enabled: navigation.hasNext)
            }
            onlyBlockingPill
        }
        .padding(.leading, 9)
        .padding(.trailing, 3)
        .padding(.vertical, 1)
        .background(Palette.surface, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1)
        }
        .help(explanation)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Procházení nálezů")
        .accessibilityValue(explanation)
    }

    /// Puntík z návrhu nese navíc **stav**: zelené odškrtnutí, když jsem prošel všechna místa.
    /// Návrh kreslí jen červené kolečko, ale „hotovo“ je jediné tvrzení, které tenhle prvek
    /// o odvedené práci dělá — a bez něj by se poznalo jen z toho, že šipka dopředu zhasla.
    private var dot: some View {
        Image(systemName: navigation.isComplete ? "checkmark.circle.fill" : "circle.fill")
            .font(.system(size: 7))
            .foregroundStyle(navigation.isComplete ? Palette.ok : Palette.crit)
    }

    /// `1 z 3 nálezů` — pozice tučně, jak to má návrh (`.lbl b`).
    ///
    /// **`monospacedDigit` je podmínka, ne ozdoba**: bez něj se při přeskoku z `9 z 12` na
    /// `10 z 12` změní šířka čísla a s ní celý rámeček — takže se šipky uhnou zpod myši zrovna
    /// ve chvíli, kdy se na ně kliká.
    private var label: some View {
        let counter = Self.counter(navigation)
        return (Text(verbatim: counter.position).fontWeight(.semibold)
            + Text(verbatim: counter.rest))
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    /// Šipka na kraji **zhasne, ne zmizí**: tlačítko, které se ztratí, vypadá jako porucha
    /// a ruší rozvržení lišty pod rukama. Živá svítí akcentem (`.arrow.hot`), zhaslá je
    /// tlumená na 35 % (`.arrow.off`).
    private func arrow(_ direction: NavigationStep, symbol: String, enabled: Bool) -> some View {
        Button { step(direction) } label: {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(enabled ? Palette.accent : Palette.ink3.opacity(0.35))
                .frame(width: 21, height: 20)
                .background(enabled ? Palette.accentWeak : .clear, in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(direction == .forward ? "Další nález (⌥↓)" : "Předchozí nález (⌥↑)")
        .accessibilityLabel(direction == .forward ? "Další nález" : "Předchozí nález")
    }

    /// Zúžení na blokující je **kapsle uvnitř rámečku**, ne checkbox vedle něj: platí jen pro
    /// tyhle šipky a nikde jinde v okně nic nefiltruje.
    private var onlyBlockingPill: some View {
        Button { onlyBlocking.toggle() } label: {
            Text(verbatim: "jen blokující")
                .font(.system(size: 10.5, weight: onlyBlocking ? .semibold : .regular))
                .foregroundStyle(onlyBlocking ? Palette.crit : Palette.ink2)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(
                    onlyBlocking ? AnyShapeStyle(Palette.crit.opacity(0.15)) : AnyShapeStyle(Palette.raised),
                    in: .capsule
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(onlyBlocking ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel("Skákat jen po blokujících nálezech")
        .help("Skákat jen po nálezech, kvůli kterým se PR nemerguje")
    }

    /// `1` + ` z 3 nálezů`, nebo `3` + ` nálezy` před prvním skokem.
    ///
    /// **Ne `0 z 3`** — nula by tvrdila, že stojím na nultém nálezu, kdežto pravda je, že nikde
    /// nestojím. Za předložkou `z` je druhý pád (`z 1 nálezu`, `z 5 nálezů`), samotný počet je
    /// první (`3 nálezy`) — proto dvě různé sady tvarů, ne jedna.
    ///
    /// Vrací se **rozdělené na dva kusy**, protože první z nich je v návrhu tučně a `Text`
    /// se dvěma řezy se jinak poskládat nedá.
    static func counter(_ navigation: FindingNavigation) -> (position: String, rest: String) {
        guard let position = navigation.position else {
            let word = Plural.word(navigation.total, one: "nález", few: "nálezy", many: "nálezů")
            return ("\(navigation.total)", " \(word)")
        }
        let word = Plural.word(navigation.total, one: "nálezu", few: "nálezů", many: "nálezů")
        return ("\(position)", " z \(navigation.total) \(word)")
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
