import AppKit
import SwiftUI

/// Paleta obarvení převedená na **AppKitové** barvy.
///
/// Existuje kvůli ceně, ne kvůli typu. `NSColor(Color)` je most ze SwiftUI a `DiffTextView` si ho
/// volal **na každý run** — u velkého diffu 16 000× na jedno projetí (3,59 ms na 27 blocích,
/// změřeno u #275). Barev je přitom pět a na runu nezávisí vůbec, takže se převedou **jednou na
/// blok** a dál se sahá sem.
///
/// **Není to cache a nemá klíč**: je to hodnota složená z palety, kterou volající zrovna drží.
/// Cache by tu byla horší, ne lepší — paleta se mění se vzhledem okna (#278) a zapamatovaná
/// z předchozího režimu by tiše vracela cizí barvy, což je přesně chyba #153 v jiných šatech.
///
/// **Dynamické barvy zůstávají dynamické.** `NSColor(Color(light:dark:))` je katalogová barva,
/// která se vyhodnotí až při kreslení, takže převod dopředu nezmrazí režim.
struct SyntaxColors {
    private let comment: NSColor
    private let string: NSColor
    private let number: NSColor
    private let keyword: NSColor
    private let variable: NSColor

    init(_ palette: SyntaxPalette) {
        comment = NSColor(palette.comment)
        string = NSColor(palette.string)
        number = NSColor(palette.number)
        keyword = NSColor(palette.keyword)
        variable = NSColor(palette.variable)
    }

    /// Barva písma pro daný druh runu. `nil` znamená **dědit z okolí**, ne „černá“ — obyčejný
    /// text vlastní barvu nemá, aby soubor bez rozpoznaného jazyka vypadal stejně jako s ním.
    /// Rozděluje se to tady stejně jako v `SyntaxPalette.color(for:)`, ať se ty dva výčty nerozejdou.
    func color(for kind: SyntaxKind) -> NSColor? {
        switch kind {
        case .plain: nil
        case .comment: comment
        case .string: string
        case .number: number
        case .keyword: keyword
        case .variable: variable
        }
    }
}
