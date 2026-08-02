import Foundation

/// Čím řádek je z pohledu obarvení.
enum SyntaxKind: Equatable, Sendable {
    case plain
    case comment
    case string
    case number
    case keyword
    /// Proměnná poznatelná ze syntaxe — `$name` v PHP nebo shellu. Jazyky, kde je
    /// proměnná obyčejné jméno, tenhle druh nemají: rozeznat ji od volání funkce by
    /// znamenalo rozumět kódu, ne řádku.
    case variable
}

/// Souvislý kus řádku s jedním významem. Řádek se skládá z run po sobě jdoucích kusů,
/// takže jejich spojení musí vždycky dát původní text.
struct SyntaxRun: Equatable, Sendable {
    let text: String
    let kind: SyntaxKind
}
