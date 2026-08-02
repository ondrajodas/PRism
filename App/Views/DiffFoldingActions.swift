import Foundation

/// Co diff umí se sbalováním celých souborů.
///
/// **Není to `DiffExpansionActions`.** Ta řeší rozbalování **kontextu** uvnitř souboru
/// (řádky, které v diffu nejsou); tohle je zavření celého souboru, jako na GitHubu.
/// Česky se obojímu říká „sbalit“, takže se ty dva typy jmenují různě schválně.
struct DiffFoldingActions {
    let isFolded: (FileDiff) -> Bool
    let toggle: (FileDiff) -> Void
    let foldAll: ([FileDiff]) -> Void
    /// Bez seznamu souborů: rozbalené je to, co není sbalené.
    let unfoldAll: () -> Void
}
