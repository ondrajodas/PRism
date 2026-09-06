import Foundation
import Observation

/// Text, který do rozepsaného pole vloží **někdo jiný než klávesnice** (#528) — tlačítko
/// `Návrh změny` nad polem komentáře.
///
/// **Proč vůbec box, a ne prostě zápis do storu.** `DraftTextEditor` drží rozepsaný text u sebe
/// a dolů ho posílá až po odmlce (400 ms), takže „vlož blok“ vedený přes store by se s tou
/// odmlkou potkal: store zná starší text, blok by se přilepil k němu — a rozepsaná věta by se
/// při návratu hodnoty přepsala. Tudy jde vložení do **živého** textu pole, tedy do toho, co je
/// vidět. Tentýž vzor jako `EmojiSuggestionBox`: stav, kterým si pole a jeho okolí podávají
/// jednu věc, a nic víc.
///
/// `@Observable`, ne hodnota v `@State` majitele: majitelem je bublina komentáře v diffu, takže
/// hodnota by ji při každém vložení překreslila celou.
@Observable final class TextInsertionBox {
    /// Co se má vložit. `nil` = nic nečeká; pole si ho po vložení samo vynuluje, aby se tentýž
    /// blok nevložil při každém překreslení podruhé.
    var pending: String?

    func insert(_ text: String) {
        pending = text
    }
}
