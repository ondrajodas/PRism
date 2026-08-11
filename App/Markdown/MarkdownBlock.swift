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
    /// Citace jako **vnořené bloky**, ne řádky (#279).
    ///
    /// Do #279 nesla surové řádky a view je slepilo do jednoho `Text`u, takže cokoli blokového
    /// uvnitř (`## nadpis`, odrážka, `- [ ]`, vnořená citace) zůstalo v okně jako zdroj. Boti
    /// přitom do citací píšou celé zprávy — tvar `[MarkdownBlock]` je tentýž, jaký má `details`.
    case quote([MarkdownBlock])
    /// GitHubová výstraha — citace, které první řádek říká `[!NOTE]` a spol. (#279).
    ///
    /// Vlastní případ, ne příznak u citace: kreslí se jinak (barevný rámeček, ikona, titulek)
    /// a **neznámý druh výstrahou není** — z `[!FOO]` je obyčejná citace, ve které ten řádek
    /// zůstane textem. Vyhodit ho by bylo přesně to tiché zahození, kterému se tady vyhýbáme.
    case alert(kind: Alert, blocks: [MarkdownBlock])
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

    /// Druh GitHubové výstrahy. Pět jich je a víc jich GitHub nezná.
    ///
    /// `rawValue` je zápis, jak ho má dokumentace GitHubu (velkými písmeny) — z něj se druh
    /// poznává a v modelu se drží **normalizovaně**, takže `[!note]` a `[!NOTE]` dají tentýž
    /// případ. Jak to napsal autor, se z modelu zpátky nedozvíme; kreslí se titulek podle druhu,
    /// takže se tím nic neztrácí.
    enum Alert: String, Hashable, Sendable, CaseIterable {
        case note = "NOTE"
        case tip = "TIP"
        case important = "IMPORTANT"
        case warning = "WARNING"
        case caution = "CAUTION"
    }
}
