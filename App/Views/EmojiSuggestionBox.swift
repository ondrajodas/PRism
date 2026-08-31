import Foundation
import Observation

/// Otevřená nabídka emotikonů — **to, co pole napsalo a co nakreslí někdo jiný** (#483).
///
/// **Proč vůbec sdílený stav, a ne `@State` uvnitř pole.** Nabídka se kreslí `overlay`em, a ten
/// **ořízne každý předek, který ořezává** — změřeno na skutečné hierarchii (`NSHostingView`
/// v okně, `cacheDisplay`): ve `ScrollView`u zmizela nabídce horní hrana i vybraný řádek, v ploše
/// s `clipShape` totéž. A zrovna dvě ze tří polí v takovém předkovi sedí: tělo review je ve
/// `ScrollView`u panelu, odpověď do vlákna v bublině s `clipShape`. Kdyby si nabídku kreslilo
/// pole samo, vypadala by v obou uříznutá.
///
/// Nabídku proto kreslí **volající** — na tom předkovi, který neořezává (`emojiMenuAbove`), a stav
/// mu k tomu podá tenhle box. Pole ho jen plní.
///
/// **`@Observable`, ne `Equatable` struktura, a je to výkonové rozhodnutí** (#472). Kdyby to byla
/// hodnota v `@State` majitele, přepsala by se při **každém úhozu** — a majitelem je composer
/// v tabu `Konverzace`, panel a bublina, tedy těla, ve kterých visí osa konverzace a seznam
/// komentářů. `@Observable` sleduje po vlastnostech a čte je **jedině** `EmojiSuggestionMenu`,
/// takže úhoz překreslí nabídku, ne tab.
@Observable final class EmojiSuggestionBox {
    /// Řádky k dotazu, který je zrovna otevřený. Prázdné = nabídka se nekreslí, což je totéž jako
    /// „není dotaz“ nebo „dotaz bez jediné shody“.
    var rows: [Policy.EmojiSuggestion] = []
    /// Který řádek je vybraný. Drží ho `Policy.pickerSelection`, takže je vždycky v rozsahu.
    var highlighted = 0

    func close() {
        rows = []
        highlighted = 0
    }
}
