import Foundation

extension Character {
    /// Zakončení řádku, jak ho vyrábí `git`, `gh` a CI runner: `LF`, `CRLF`, nebo samotné `CR`.
    ///
    /// **Ne `isNewline`**, který je pravda i pro `VT`, `FF`, `NEL`, `U+2028` a `U+2029`. Tyhle
    /// znaky jsou pro `git` **obsah řádku**, ne jeho konec — takže rozdělit se na nich znamená
    /// vyrobit řádek, který v souboru není. U diffu to není teorie: čísla řádků se počítají tím,
    /// kolik jich hunk vydal, takže jeden `U+2028` v cizím zdrojáku by posunul všechna čísla pod
    /// sebou a ta druhá půlka řádku by navíc nezačínala `+`/`-`/mezerou, tedy by se spočítala jako
    /// ztracená (`unrecognizedLines`).
    ///
    /// `String.singleLine` si proti tomu **`isNewline` schválně nechává**: tam se cizí text sráží
    /// do jednoho řádku kvůli **sazbě**, a `U+2028` je pro sazbu zlom, který by popisek rozhodil.
    /// Jsou to dvě různé otázky — „kde končí řádek v bajtech, které mi někdo poslal“ a „co mi
    /// zalomí popisek“ — a proto mají dvě různé odpovědi.
    var isLineTerminator: Bool { self == "\n" || self == "\r\n" || self == "\r" }
}

/// Dělení textu na řádky. **Jedno místo pro celou aplikaci** (#295).
///
/// Existuje kvůli jedné pasti, kterou se dá projít review i zeleným testem: `"\r\n"` je ve Swiftu
/// **jeden `Character`**, takže `split(separator: "\n")` na textu s `CRLF` **nerozdělí vůbec**
/// a z celého vstupu zbyde jediný „řádek“. Ne o jeden vedle — celý.
///
/// Vypadá to jako okrajový případ a není: `#292` na tom vypnul celý konec logu u checků, protože
/// `gh api -i` zakončuje hlavičky `CRLF` a `Content-Length` se proto nenašel u **žádného** checku.
/// A `CR` prochází i do diffu — fixture `gh/pr-diff-crlf.diff` je `gh pr diff` na veřejný
/// `microsoft/terminal#20524`, kde je `CRLF` na 70 řádcích ze 76. Diff souboru s `CRLF` by se
/// tedy rozparsoval jako jediný řádek.
///
/// Druhá past, kterou to zavírá, je `components(separatedBy: .newlines)`: ta pracuje po skalárech,
/// takže `CRLF` je pro ni **dva** oddělovače a mezi ně vloží prázdný řádek. Rozdělí to sice, ale
/// v markdownu z GitHubu (kde `CRLF` v tělech komentářů doopravdy je) je prázdný řádek konec
/// odstavce — takže by se každý řádek cizího komentáře vysázel jako vlastní odstavec.
///
/// Tři funkce, ne jedna s přepínačem: liší se tím, **co je řádek** pro volajícího, a to je věc,
/// kterou má být na místě volání vidět.
enum TextLines {
    /// Všechny řádky, včetně prázdných — i toho posledního, který vyrobí koncové zakončení.
    ///
    /// Pro text, kde prázdný řádek nese význam: kód (drží strukturu), markdown (odděluje odstavce),
    /// log (prázdné řádky v něm jsou).
    static func all<S: StringProtocol>(_ text: S) -> [S.SubSequence] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isLineTerminator)
    }

    /// Řádky obsahu — jako `all(_:)`, ale **bez prázdného posledního** za koncovým zakončením.
    ///
    /// Textový soubor končí zakončením řádku, takže `all(_:)` na něm vydá o řádek víc, než kolik
    /// jich soubor má. U diffu by ten navíc byl „nerozpoznaný řádek“ u každého úplného vstupu,
    /// u obsahu souboru by se rozešel s číslováním hunků a u konce logu by tvrdil ořez, který
    /// nenastal.
    static func content<S: StringProtocol>(_ text: S) -> [S.SubSequence] {
        var lines = all(text)
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    /// Jen neprázdné řádky — pro výpisy, kde je řádek jeden záznam a prázdný žádný záznam není
    /// (výstupy `git` plumbingu, hlavičky HTTP, `PATH` z přihlašovacího shellu).
    static func nonEmpty<S: StringProtocol>(_ text: S) -> [S.SubSequence] {
        text.split(omittingEmptySubsequences: true, whereSeparator: \.isLineTerminator)
    }
}
