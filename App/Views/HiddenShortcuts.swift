import SwiftUI

/// Klávesové zkratky, které nemají viditelné tlačítko.
///
/// Existuje kvůli jedné znalosti, která se v repu opakuje a snadno se poruší: zkratka musí
/// zůstat **v hierarchii view**, jinak nechodí. `hidden()` view z hierarchie vyřadí i se
/// zkratkou, takže se schovává `opacity(0)` a nulovým rámcem.
///
/// Proč vůbec tlačítko, a ne `onExitCommand` nebo `onKeyPress`: ty se vážou na **fokus**
/// a `List` v okně je spolkne dřív, než se k nim něco dostane (ověřeno u #127 na běžící
/// aplikaci — okno hlásilo `AXFocused` a Esc nezavřel nic). Zkratka na tlačítku se naproti
/// tomu registruje na celé okno.
///
/// Do #151 to byly tři opisy téhož ve třech souborech; teď je to jedno místo, které se použije
/// z okna novinek, z nastavení i z detailu PR.
extension View {
    /// - Parameter content: tlačítka se zkratkami. Titulek se nikde nekreslí, ale píše se
    ///   poctivě — je to jediné, z čeho se v kódu pozná, co ta zkratka dělá.
    func hiddenShortcuts<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        background {
            VStack(spacing: 0) { content() }
                .opacity(0)
                .frame(width: 0, height: 0)
                // Zkratky ano, kliknutí ne: neviditelné tlačítko nesmí brát klik obsahu pod
                // sebou a ve VoiceOveru nemá co dělat — přečetlo by se jako prvek bez místa.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
