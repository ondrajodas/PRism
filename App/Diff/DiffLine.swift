import Foundation

/// Jeden řádek uvnitř hunku.
///
/// Čísla jsou optional schválně: odebraný řádek v novém souboru neexistuje a přidaný ve
/// starém, takže „chybí“ je informace, ne mezera k doplnění. Na `newNumber` se v #19
/// zavěsí bublina nálezu.
struct DiffLine: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case context
        case added
        case removed
        /// Poznámka `git`u uvnitř hunku, typicky `\ No newline at end of file`. Není to
        /// obsah souboru, takže nemá číslo ani neposouvá počítadla.
        case meta
    }

    let kind: Kind
    let oldNumber: Int?
    let newNumber: Int?
    /// Obsah řádku **bez** znaku, kterým diff určuje druh.
    let text: String

    /// Týž řádek, ale jako kontext (#216).
    ///
    /// Používá to úryvek u vlákna na ose konverzace, kde se barví **jen komentovaný řádek**:
    /// celý zelený blok se čte jako změna, o které vlákno není. Čísla i text zůstávají, mění se
    /// jedině to, jak se řádek kreslí.
    var asContext: DiffLine {
        DiffLine(kind: .context, oldNumber: oldNumber, newNumber: newNumber, text: text)
    }
}
