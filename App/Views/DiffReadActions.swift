import Foundation

/// Co diff umí se značkou `Prošlo` u souboru (#500).
///
/// **Vlastní struktura vedle `DiffFoldingActions`, ne pole v ní**, i když spolu sbalení a značka
/// souvisí: sbalení má i diff commitu a rozsahový diff, kdežto značka jedině `Změněné soubory`.
/// Volitelnost jednoho parametru (`read: nil`) je proto to, čím se ty dvě obrazovky liší — a je
/// vidět z volání.
struct DiffReadActions {
    /// Stavy značek, klíčem je `FileDiff.displayPath`. **Snímek, ne uzávěr nad storem**: čte je
    /// hlavička každého souboru i strom, takže dotaz po jednom by nad padesátisouborovým PR byl
    /// stovka volání za překreslení. Skládá je `Policy.fileReviewStates` na jednom místě.
    let states: [String: FileReviewState]
    /// Zaškrtnutí i odškrtnutí. Otisk obsahu si bere z toho souboru, který je na obrazovce.
    let toggle: (FileDiff) -> Void

    /// Co v mapě není, je nezaškrtnuté — tak ji `Policy` vydává, aby u PR bez značek nebyla
    /// padesátkrát napsaná nula.
    func state(of file: FileDiff) -> FileReviewState { states[file.displayPath] ?? .unread }
}
