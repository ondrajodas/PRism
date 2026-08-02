import Foundation

/// Rozbalování kontextu jednoho souboru: co je odkryté a z čeho se to bere.
struct FileExpansion: Equatable, Sendable {
    /// Které skryté řádky si uživatel nechal dotáhnout.
    var revealed = RevealedLines()
    /// Obsah souboru na hlavě PR, po řádcích. Prázdný, dokud se nenačetl.
    var content: [String] = []
    var isLoading = false
    /// Proč se obsah nepodařilo načíst. Musí být vidět: bez toho vypadá selhání jako
    /// úsek, ve kterém nic není.
    var failure: String?

    /// Text souboru na řádky. Zakončení novým řádkem nedělá prázdný poslední řádek —
    /// jinak by soubor „měl“ o řádek víc, než kolik jich číslují hunky.
    static func lines(of text: String) -> [String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }
}

/// Klíč rozbalení — soubor v konkrétním pull requestu. Cesta sama nestačí, stejný
/// `App/Main.swift` je v každém repu jiný.
struct FileExpansionKey: Hashable, Sendable {
    let pullRequest: PRIdentifier
    let path: String
}
