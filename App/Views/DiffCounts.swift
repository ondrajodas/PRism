import SwiftUI

/// Počty přidaných a odebraných řádků jako obarvený text — `+X` zeleně, `−Y` červeně (#156).
///
/// Vlastní typ, protože ta tři místa spolu jinak nesousedí: souhrn nad diffem a hlavička
/// souboru (`DiffView`) a strom souborů (`FileTreeView`). Kdyby si to každé skládalo samo,
/// zůstalo by po první změně jedno z nich šedé — a mluví přitom o tomtéž údaji.
enum DiffCounts {
    /// Barvu dává `DiffLineView.signColor(of:)`, tedy tentýž zdroj jako znak změny v řádku
    /// diffu. Vlastní konstanty by byly druhá sada, která se s první jednou rozejde.
    ///
    /// **Ne `DiffLineView.background(of:)`** — to je dvanáctiprocentní výplň a jako barva
    /// písma je nečitelná. Sytá barva znaku je naopak text, který v diffu stojí od #18.
    ///
    /// Vrací `Text`, ne `some View`: jen tak se dá slít se zbytkem věty do jednoho řádku,
    /// který se zalamuje jako celek (souhrn to tak dělá). Font a `monospacedDigit` si nasazuje
    /// volající — v souhrnu a v hlavičce jsou jiné.
    ///
    /// Čísla jdou `verbatim`, jako všude jinde v diffu: `+\(1234)` přes locale vyjde jako
    /// `+1 234`, a počet řádků není množství, které by se takhle formátovalo.
    static func text(additions: Int, deletions: Int) -> Text {
        Text(verbatim: "+\(additions)").foregroundStyle(DiffLineView.signColor(of: .added))
            + Text(verbatim: " ")
            + Text(verbatim: "−\(deletions)").foregroundStyle(DiffLineView.signColor(of: .removed))
    }
}
