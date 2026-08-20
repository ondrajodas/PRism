import AppKit
import SwiftUI

/// Paleta obarvení převedená na **AppKitové** barvy.
///
/// Existuje kvůli ceně, ne kvůli typu. `NSColor(Color)` je most ze SwiftUI a `DiffTextView` si ho
/// volal **na každý run** — u velkého diffu 16 000× na jedno projetí (3,59 ms na 27 blocích,
/// změřeno u #275). Barev je přitom šest a na runu nezávisí vůbec, takže se převedou **jednou na
/// blok** a dál se sahá sem.
///
/// **Není to cache a nemá klíč**: je to hodnota složená z palety, kterou volající zrovna drží.
/// Cache by tu byla horší, ne lepší — paleta se mění se vzhledem okna (#278) a zapamatovaná
/// z předchozího režimu by tiše vracela cizí barvy, což je přesně chyba #153 v jiných šatech.
///
/// **Dynamické barvy zůstávají dynamické.** `NSColor(Color(light:dark:))` je katalogová barva,
/// která se vyhodnotí až při kreslení, takže převod dopředu nezmrazí režim.
struct SyntaxColors {
    /// Barva **obyčejného textu** — identifikátory, interpunkce, text souboru bez rozpoznaného
    /// jazyka (#393).
    ///
    /// **Nasazuje se jako základ celého textu, ne po runech**, takže nic nestojí: obarvení syntaxe
    /// ji přes svoje rozsahy přepíše. A nasadit se **musí** — v atributovaném řetězci znamená
    /// chybějící `.foregroundColor` **černou**, ne „dědí z okolí“ (to platí jen ve SwiftUI, odkud
    /// se ta úvaha do #157 přenesla). V tmavém režimu z toho byly identifikátory černé na
    /// tmavozeleném pozadí přidaného řádku, tedy kontrast **1,39** proti 12,55 s touhle barvou.
    ///
    /// Hodnota je token `--ink` z návrhu (`Palette.ink`), protože `td.code` v mockupu dědí barvu
    /// textu stránky. **Ne `labelColor`**: ten je poloprůhledný (bílá na 85 %), takže by se přes
    /// barevné pozadí řádku složil jinak než v návrhu.
    let plain = NSColor(Palette.ink)

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

    /// Barva písma pro daný druh runu. `nil` u obyčejného textu znamená **nechat základní barvu**
    /// (`plain`), kterou volající nasadil na celý text — ne „černá“ a ne „dědí z okolí“, viz
    /// `plain`. Rozděluje se to tady stejně jako v `SyntaxPalette.color(for:)`, ať se ty dva výčty
    /// nerozejdou.
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
