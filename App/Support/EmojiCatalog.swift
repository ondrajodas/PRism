import Foundation

/// Katalog emotikonů, jak ho vidí aplikace (#483).
///
/// **V aplikaci, ne z GitHubu.** `GET /emojis` vrací jména a **adresy obrázků**, ne znaky (kód se
/// dá vyloupnout z názvu souboru, ale to je rozbor cizí adresy, ne API). Seznam se navíc nemění,
/// takže síťové volání kvůli textovému poli by byla závislost bez užitku — a `GitHubGateway`
/// zůstává bez nového dotazu.
///
/// **Rozebírá se líně a jednou za běh procesu.** `static let` ve Swiftu je líné, takže kdo si
/// v okně nikdy nenapíše `:`, nezaplatí nic; kdo si napíše, zaplatí jeden průchod tabulkou
/// (změřeno v `EmojiCatalogTests`).
///
/// Data i generátor jsou v repu (`bin/emoji-sources/`, `bin/make-emoji.swift`), takže se tabulka
/// dá vyrobit znovu — viz hlavička generátoru.
enum EmojiCatalog {
    /// Celý katalog, v pořadí tabulky (abecedně podle prvního shortcodu).
    static let all: [Emoji] = parse(EmojiTable.rows)

    /// Rozbor tabulky. **Veřejné kvůli testům**, které ji prohánějí i vadnými řádky — chování na
    /// nich je součást kontraktu, ne detail.
    ///
    /// **Vadný řádek se zahodí, nezastaví rozbor.** Je to jediné místo v aplikaci, kde je zahození
    /// bez hlášky v pořádku, a je to proto, že vstup je **vygenerovaný zdroják z téhož commitu**,
    /// ne cizí data: kdyby se rozešel, spadne test (`EmojiCatalogTests` tvrdí počet znaků i
    /// shortcodů literálem), ne provoz. Zastavit rozbor by naopak znamenalo prázdnou nabídku
    /// v okně kvůli jednomu řádku.
    ///
    /// Řádky dělí `TextLines`, ne `split(separator: "\n")` — pravidlo z #295 platí i na text, který
    /// vyrábíme sami: kdyby generátor jednou zapsal `CRLF`, nerozdělilo by se **vůbec**.
    static func parse(_ table: String) -> [Emoji] {
        TextLines.nonEmpty(table).compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2 else { return nil }
            return Emoji(
                character: String(fields[0]),
                name: String(fields[1]),
                aliases: fields.dropFirst(2).map(String.init)
            )
        }
    }
}
