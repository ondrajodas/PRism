import Foundation

/// Rozbalování kontextu jednoho souboru: co je odkryté a z čeho se to bere.
struct FileExpansion: Equatable, Sendable {
    /// Které skryté řádky si uživatel nechal dotáhnout.
    var revealed = RevealedLines()
    /// Obsah souboru, po řádcích. Prázdný, dokud se nenačetl.
    ///
    /// **Z které verze souboru je, říká klíč** (`FileExpansionKey.commit`), ne tenhle typ:
    /// v `Změněných souborech` je to hlava PR, v diffu commitu (#317) ten commit. Dvě verze
    /// pod jedním klíčem by znamenaly rozbalený kontext posunutý o všechno, co mezi commitem
    /// a hlavou přibylo — a to potichu.
    var content: [String] = []
    /// Rozsahy vyžádané, **než** dorazil obsah. Bez nich by se druhý nález v témže
    /// souboru během načítání ztratil.
    var pending: [ClosedRange<Int>] = []
    var isLoading = false
    /// Proč se obsah nepodařilo načíst. Musí být vidět: bez toho vypadá selhání jako
    /// úsek, ve kterém nic není.
    var failure: String?

    /// Text souboru na řádky. Zakončení novým řádkem nedělá prázdný poslední řádek —
    /// jinak by soubor „měl“ o řádek víc, než kolik jich číslují hunky.
    ///
    /// **Dělí `TextLines`** (#295): soubor s `CRLF` by se přes `split(separator: "\n")` načetl jako
    /// **jeden** řádek, takže by se odkrytý rozsah ořezal na první řádek a z rozbaleného kontextu
    /// by byla jedna nekonečná řádka. Je to tatáž past jako v `DiffParser` — a musí se řešit
    /// stejně, protože číslování odsud se páruje s čísly z hunků.
    static func lines(of text: String) -> [String] {
        TextLines.content(text).map(String.init)
    }
}

/// Klíč rozbalení — soubor v konkrétním pull requestu. Cesta sama nestačí, stejný
/// `App/Main.swift` je v každém repu jiný.
struct FileExpansionKey: Hashable, Sendable {
    let pullRequest: PRIdentifier
    let path: String
    /// Ze kterého commitu se obsah čte (#317). `nil` = **hlava PR**, tedy `Změněné soubory`.
    ///
    /// Je to součást klíče, ne údaj vedle: týž soubor má v tabu `Commity` a v `Změněných
    /// souborech` jiný obsah i jiná čísla řádků, takže sdílený záznam by u staršího commitu
    /// odkryl řádky z dnešní hlavy. Úklid se tím nemění — jede pořád podle `pullRequest`.
    var commit: String?
}
