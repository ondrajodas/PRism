import SwiftUI

/// Zaškrtávátko `Prošlo` v hlavičce souboru (#500) — `.rv-viewed` z návrhu (sekce 40).
///
/// **Vlastní tlačítko vedle hlavičky, ne uvnitř ní.** Celá hlavička je od #219 tlačítko na
/// sbalení, a tlačítko v tlačítku je v SwiftUI přesně ten druh věci, u které se nedá spolehnout,
/// kdo klik dostane. Řádek se proto dělí: fold bere všechno až sem, zaškrtávátko svůj kousek
/// vpravo. Ztráta je jen ta, že klik na těch pár desítek bodů nesbaluje — což je správně, protože
/// tam se zaškrtává.
///
/// Kreslí se **jen v `Změněných souborech`**: diff commitu ani rozsahový diff „co od minule
/// přibylo“ značku nemají, protože jejich `index` řádky mluví o jiném rozsahu než hlava PR
/// (viz `DiffReadActions`).
struct DiffFileReadToggle: View {
    let state: FileReviewState
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                box
                Text(verbatim: Policy.readToggleTitle(of: state))
                // Kdy se zaškrtlo. **Patří sem, ne do kapsle**: značka bez času neodpoví na
                // otázku „bylo to před tím pushem, nebo po něm“, a u změněného souboru to říká
                // kapsle vedle cesty.
                if case .read(let at) = state {
                    Text(verbatim: "·").foregroundStyle(Palette.ink3)
                    Text(at, format: .relative(presentation: .named))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(state.isRead ? Palette.ok : Palette.ink2)
            .lineLimit(1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Policy.readToggleHelp(of: state))
        .accessibilityLabel(Text(verbatim: Policy.readToggleTitle(of: state)))
        .accessibilityAddTraits(state.isRead ? [.isSelected] : [])
    }

    /// Čtvereček 13 × 13 s poloměrem 3, jak ho má návrh. Prošlý je vyplněný `--ok` s fajfkou
    /// v barvě podkladu; **`changed` má prázdný**, protože tlačítko u něj neříká stav, ale co
    /// udělá (`Prošlo znovu`).
    private var box: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(state.isRead ? Palette.ok : Palette.surface)
            .frame(width: 13, height: 13)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(state.isRead ? Palette.ok : Palette.line, lineWidth: 1)
            }
            .overlay {
                if state.isRead {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.surface)
                }
            }
    }
}
