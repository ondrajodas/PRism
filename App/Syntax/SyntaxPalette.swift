import SwiftUI

/// Barvy obarveného kódu.
///
/// Tmavá je **Darcula** z JetBrains, světlá její protějšek **IntelliJ Light** — dvě
/// nesourodá témata by při přepnutí režimu vypadala jako dvě různé aplikace.
///
/// Obyčejný text vlastní barvu nemá: dědí ji z okolí, takže soubor bez rozpoznaného
/// jazyka a soubor s ním vypadají stejně všude, kde se nic nebarví.
struct SyntaxPalette {
    let comment: Color
    let string: Color
    let number: Color
    let keyword: Color
    let variable: Color

    func color(for kind: SyntaxKind) -> Color? {
        switch kind {
        case .plain: nil
        case .comment: comment
        case .string: string
        case .number: number
        case .keyword: keyword
        case .variable: variable
        }
    }

    static func forScheme(_ scheme: ColorScheme) -> SyntaxPalette {
        scheme == .dark ? .darcula : .intelliJLight
    }

    /// Darcula: klíčová slova oranžová, řetězce zelené, čísla modrá, komentáře šedé.
    static let darcula = SyntaxPalette(
        comment: Color(red: 0.502, green: 0.502, blue: 0.502),   // #808080
        string: Color(red: 0.416, green: 0.529, blue: 0.349),    // #6A8759
        number: Color(red: 0.408, green: 0.592, blue: 0.733),    // #6897BB
        keyword: Color(red: 0.800, green: 0.471, blue: 0.196),   // #CC7832
        variable: Color(red: 0.596, green: 0.463, blue: 0.667)   // #9876AA
    )

    /// IntelliJ Light: klíčová slova tmavě modrá, řetězce zelené, čísla modrá, komentáře šedé.
    static let intelliJLight = SyntaxPalette(
        comment: Color(red: 0.549, green: 0.549, blue: 0.549),   // #8C8C8C
        string: Color(red: 0.024, green: 0.490, blue: 0.090),    // #067D17
        number: Color(red: 0.090, green: 0.314, blue: 0.922),    // #1750EB
        keyword: Color(red: 0.000, green: 0.200, blue: 0.702),   // #0033B3
        variable: Color(red: 0.529, green: 0.063, blue: 0.580)   // #871094
    )
}
