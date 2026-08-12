import SwiftUI

/// Podpis obsahu bloku kódu — klíč, podle kterého `DiffTextView.show(…)` pozná, že text **nemá**
/// znovu sázet (#157). Sázení ruší výběr, a `updateNSView` chodí i při pouhém přejezdu myší.
///
/// **Jedno místo pro obě podoby diffu.** Skládaly ho `DiffCodeBlockView` (pod sebou)
/// i `DiffPairBlockView` (vedle sebe), každý svým řetězcem — a přitom to musí být tentýž vzorec.
/// Dvě kopie znamenají, že se příští oprava udělá jen v jedné.
enum DiffBlockSignature {
    /// **Barevný režim je v podpisu schválně a musí v něm zůstat.** Barvy jsou v tom vysázeném
    /// textu zapečené (`SyntaxPalette.forScheme(_:)`), takže bez režimu v podpisu by se po přepnutí
    /// vzhledu (#278) sázení přeskočilo a v okně by zbyl kód obarvený podle předchozího režimu —
    /// a potichu, protože text ani jazyk se nezměnily. Je to tentýž požadavek jako u #153: pod
    /// klíčem smí být jen to, čeho je uložená hodnota funkcí.
    ///
    /// (`SyntaxRunCache` je jiná cache a barvy v ní nejsou, jen druhy run — tu tedy přepnutí
    /// režimu zneplatňovat nemusí, viz `App/Syntax/`.)
    static func of(blockHash: Int, language: Language?, colorScheme: ColorScheme) -> String {
        "\(blockHash)|\(language?.name ?? "")|\(colorScheme)"
    }
}
