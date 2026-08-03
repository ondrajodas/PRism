import Foundation

/// Jeden blok Markdownu tak, jak se kreslí.
///
/// Bloky drží **jen strukturu**, ne formátování uvnitř řádku: tučné, kurzíva, `kód` a odkazy
/// zůstávají v textu a řeší je až view přes `AttributedString`. Dělí se to takhle schválně —
/// systémový parser umí inline výborně, ale bloky (nadpisy, seznamy, fences) ve `Text`u
/// **tiše spolkne**: značky zmizí a odstavce splynou. Struktura je proto naše, inline jeho.
enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    /// Odstavec. Řádky uvnitř se drží tak, jak byly — GitHub v komentářích zalomení
    /// respektuje, takže slít je do jednoho by změnilo, jak text vypadá.
    case paragraph(String)
    case listItem(marker: Marker, indent: Int, text: String)
    /// Blok kódu mezi ` ``` `. Uvnitř se nic neinterpretuje.
    case code(language: String?, lines: [String])
    case quote([String])
    case rule
    /// Tabulka jako **surové řádky**. Vykreslit ji doopravdy je vlastní úloha; svislítka
    /// zůstávají, takže se to dá přečíst a nic se neztratí.
    case table([String])
    /// `<details>` — rozbalovací blok, který GitHub v komentářích umí a boti ho používají.
    ///
    /// Obsah jsou **vnořené bloky**, ne text: uvnitř bývají odstavce a seznamy, takže by se
    /// jinak vykreslily jako jeden slitý řádek.
    case details(summary: String, blocks: [MarkdownBlock])
    /// `<!-- … -->`. Drží se, ale **nekreslí se** — GitHub taky nic nevykreslí, protože je to
    /// značka pro stroje (`linear-linkback` a spol.), ne text pro člověka.
    ///
    /// Zahodit ji už v parseru by rozbilo pravidlo „žádný řádek se neztratí“: text pak nejde
    /// odlišit od chyby parsování. Takhle je vidět v modelu a rozhodnutí ho nekreslit je ve
    /// view, kde patří.
    case htmlComment([String])

    enum Marker: Hashable, Sendable {
        case bullet
        case number(Int)
        /// Zaškrtávací seznam — v popisech PR je ho plno.
        case task(isDone: Bool)
    }
}
