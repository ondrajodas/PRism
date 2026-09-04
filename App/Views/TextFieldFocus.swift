import SwiftUI

/// Píše se někde v okně do pole? (#507)
///
/// Vzniklo kvůli mezerníku: `Policy.itineraryStep` si klávesu bere jedině tehdy, když se jí nic
/// nesebere, a **mezera v textu je to první, co by sebrala**. Odpověď „podle tabu“ (jako
/// `Policy.claimsReturnShortcut`, #452) tady nestačí — composer rozdělaného review stojí
/// v panelu vedle `Přehledu` i `Změněných souborů`, takže by byla vedle právě v těch dvou
/// tabech, o kterých itinerář mluví nejvíc.
///
/// **Sada, ne `Bool`.** Fokus přeskakuje z pole do pole a pořadí, ve kterém přijdou dvě hlášení
/// (staré pole ztratilo, nové získalo), není zaručené — s jedním příznakem by se dalo skončit
/// v `false` uprostřed psaní. Množina identit odpovídá správně v obou pořadích a `isEditing` je
/// z ní odvozené.
///
/// **Vlastnost je jedna a mění se zřídka** — čte ji jediné view (`ItineraryStepShortcut`), takže
/// se za sledování platí překreslením jednoho průhledného tlačítka (tatáž úvaha jako
/// u `DiffViewport`, #469).
@Observable final class TextFieldFocus {
    /// Píše se do některého z polí?
    private(set) var isEditing = false

    /// Pole, která hlásí fokus. Identita je `UUID` view, ne jméno — dvě bubliny vlákna vedle sebe
    /// jsou dvě pole se stejným účelem.
    private var fields: Set<UUID> = []

    func note(_ field: UUID, isFocused: Bool) {
        if isFocused {
            fields.insert(field)
        } else {
            fields.remove(field)
        }
        // Zápis téže hodnoty toolchain nehlásí (`PollObservationTests`), takže stráž na rovnost
        // tu není potřeba — a `Bool` je porovnatelný, takže ani nejde o případ #421.
        isEditing = !fields.isEmpty
    }
}

extension EnvironmentValues {
    /// Kam pole hlásí fokus. `nil` = **nikdo neposlouchá** (náhledy, sondy, testy jednotlivých
    /// view) — tentýž zápis jako `reportReadToEnd` v `OverviewView`.
    ///
    /// **Prostředím, ne parametrem**, a ze stejného důvodu jako `terminalFocused` (#459): polí je
    /// v okně sedm na čtyřech úrovních zanoření, takže předávat je argumentem znamená na jedno
    /// z nich zapomenout — a projevilo by se to mezerníkem, který uprostřed psaní přeskočí
    /// na jinou zastávku.
    @Entry var textFieldFocus: TextFieldFocus?
}

extension View {
    /// Hlásí fokus pole do okna (#507).
    ///
    /// Vlastní modifikátor, ne `onChange` u každého pole: musí se hlásit **i zmizení** pole,
    /// které fokus zrovna má (bublina vlákna je buňka seznamu a odscrollováním se zahodí),
    /// a to je přesně ta polovina, na kterou se u čtyř volajících zapomene.
    func reportsTextFieldFocus(_ isFocused: Bool) -> some View {
        modifier(TextFieldFocusReporter(isFocused: isFocused))
    }
}

/// Hlášení fokusu jednoho pole. `ViewModifier`, protože `View` extension se na prostředí zeptat
/// nemůže.
private struct TextFieldFocusReporter: ViewModifier {
    let isFocused: Bool

    /// Identita **tohohle** pole. `@State`, takže přežije průchody tělem a zanikne s polem.
    @State private var id = UUID()
    @Environment(\.textFieldFocus) private var focus

    func body(content: Content) -> some View {
        content
            .onChange(of: isFocused) { _, focused in focus?.note(id, isFocused: focused) }
            // Pole, které zmizí s fokusem, by v sadě zůstalo ležet — a okno by si do konce
            // života myslelo, že se do něj píše.
            .onDisappear { focus?.note(id, isFocused: false) }
    }
}
