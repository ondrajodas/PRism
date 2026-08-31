import Foundation

/// Jeden emotikon z katalogu (#483) — **znak a jeho shortcody**.
///
/// **Klíč je znak, ne jméno**, a je to celý důvod, proč tenhle typ existuje: `:+1:`
/// a `:thumbsup:` jsou tentýž 👍, takže dva řádky v nabídce by byly nabídka, ve které se nedá
/// vybrat ani dobře, ani špatně. Jméno je jedno (`name`, to se kreslí) a ostatní jsou `aliases`,
/// tedy jen další cesty, jak se ten řádek dá najít.
///
/// **Odesílá se `character`, nikdy shortcode.** Composer je obyčejné textové pole a odchází jeho
/// obsah, takže vložený `:tada:` by byl náhled, který tvrdí něco jiného než výsledek na GitHubu.
struct Emoji: Equatable, Sendable {
    /// Znak, který se vloží do textu. Jeden `Character` i u složených (👨‍👩‍👦), ale drží se jako
    /// `String` — do textu se vkládá řetězec a druhý typ by si vynutil převod na každém volání.
    let character: String
    /// Shortcode, který se v řádku **kreslí**. U 👍 je to `+1`, protože tak ho vydává katalog
    /// GitHubu — a co je v datech první, je to, co GitHub považuje za jméno.
    let name: String
    /// Další jména téhož znaku. Hledá se i podle nich a když shoda přijde odsud, je alias
    /// v řádku vidět vpravo — jinak by řádek `:+1:` vypadal na dotaz `:thu` jako omyl nabídky.
    let aliases: [String]

    /// Všechna jména, kterými se ten znak dá najít. `name` je první.
    var names: [String] { [name] + aliases }
}
