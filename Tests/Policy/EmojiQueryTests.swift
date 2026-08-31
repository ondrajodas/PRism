import Foundation
import Testing

@testable import PRism

/// **Kdy se nabídka emotikonů otevře — a kdy schválně ne** (#483).
///
/// Dvojtečka je v próze běžný znak, takže rozhodovat nemůže sama. Planý poplach v textovém poli se
/// pozná až v provozu (nabídka vyskočí uprostřed psaní času nebo odkazu), a proto je to čistá funkce
/// a testuje se **vyčerpávajícím výčtem**, ne klikáním.
///
/// Kurzor se předává jako **počet znaků**, ne `String.Index` — tím se dá napsat i případ „kurzor
/// mimo text“, který by se indexem nedal ani vyrobit.
@Suite("Dotaz na emotikon (#483)")
struct EmojiQueryTests {
    /// Vstupy, u kterých se nabídka otevřít **má**: text, kurzor, čekaný dotaz a poloha dvojtečky.
    nonisolated static let opens: [(text: String, caret: Int, query: String, colon: Int)] = [
        // Na začátku textu.
        (":ta", 3, "ta", 0),
        (":t", 2, "t", 0),
        // Po mezeře.
        ("Díky za úklid anotací :ta", 25, "ta", 22),
        // Na začátku řádku uprostřed textu — `LF`.
        ("první\n:ta", 9, "ta", 6),
        // A `CRLF`, které je ve Swiftu **jeden** `Character`. Kdyby se počítalo po skalárech,
        // vyšla by poloha dvojtečky o jeden vedle a vložení by sežralo znak před ní.
        ("první\r\n:ta", 9, "ta", 6),
        // Kurzor **uprostřed** rozepsaného shortcodu: dotaz je to, co je vlevo od něj.
        (":tada", 3, "ta", 0),
        // Podtržítko, číslice a znaménko jsou součástí shortcodu, dokud je v dotazu písmeno.
        (":white_check", 12, "white_check", 0),
        (":e-mail", 7, "e-mail", 0),
        (":u7121", 6, "u7121", 0),
        // Diakritika je písmeno; katalog ji nezná, takže z toho bude nabídka bez shody — a to je
        // jiný stav (zavře ji prázdný výsledek), ne jiný dotaz.
        ("ěš :čá", 6, "čá", 3),
        // Velká písmena jsou data, ne chyba: hledá se bez ohledu na velikost.
        (":TA", 3, "TA", 0),
        // Znak před mezerou se počítá jako **jeden**, ne jako jeho skaláry.
        ("🎉 :ta", 5, "ta", 2),
    ]

    /// Vstupy, u kterých se nabídka otevřít **nesmí** — a u každého důvod.
    nonisolated static let closed: [(text: String, caret: Int, why: String)] = [
        ("", 0, "prázdný text"),
        (":ta", 0, "kurzor před dvojtečkou"),
        (":", 1, "dvojtečka bez dotazu"),
        (":ta", 4, "kurzor za koncem textu"),
        (":ta", -1, "kurzor v mínusu"),
        ("ta", 2, "žádná dvojtečka"),
        // Tři nejčastější plané poplachy.
        ("12:30", 5, "dvojtečka po číslici a dotaz bez písmene"),
        ("12:ta", 5, "dvojtečka po číslici"),
        ("https:ta", 8, "dvojtečka po písmenu"),
        ("Poznámka:", 9, "dvojtečka bez dotazu na konci textu"),
        ("Poznámka: ", 10, "za dvojtečkou mezera"),
        ("Poznámka: ta", 12, "kurzor za mezerou, dvojtečka daleko vlevo"),
        // Dotaz musí mít aspoň jedno **písmeno**.
        (":1", 2, "dotaz jen z číslice"),
        (":+1", 3, "dotaz jen ze znaménka a číslice"),
        (":_", 2, "dotaz jen z podtržítka"),
        // Mezera dotaz zavírá.
        (":ta ", 4, "za dotazem mezera"),
        (":ta x", 5, "kurzor v dalším slově"),
        // Dvojtečka po dvojtečce není hranice slova.
        ("::ta", 4, "dvojtečka po dvojtečce"),
        // Hotový shortcode napsaný rukou už dotaz není.
        (":tada:", 6, "kurzor za uzavírací dvojtečkou"),
    ]

    @Test("Nabídka se otevře na hranici slova", arguments: opens)
    func opensOnAWordBoundary(input: (text: String, caret: Int, query: String, colon: Int)) throws {
        let query = try #require(
            Policy.emojiQuery(in: input.text, caret: input.caret),
            "„\(input.text)“ na \(input.caret) mělo otevřít dotaz"
        )

        #expect(query.text == input.query)
        #expect(query.colon == input.colon)
        #expect(query.caret == input.caret)
        // Rozsah k záměně drží dvojtečku i celý dotaz — jinak by po vložení zůstala `:` v textu.
        #expect(query.caret - query.colon == input.query.count + 1)
    }

    @Test("Nabídka se neotevře", arguments: closed)
    func staysClosed(input: (text: String, caret: Int, why: String)) {
        #expect(
            Policy.emojiQuery(in: input.text, caret: input.caret) == nil,
            "„\(input.text)“ na \(input.caret) otevřelo dotaz — \(input.why)"
        )
    }

    /// **Poloha dvojtečky musí sedět na skutečný text**, ne jen být „nějaké číslo“: vkládá se podle
    /// ní, takže o jeden vedle znamená sežraný znak. Ověřuje se to průchodem přes všechny polohy
    /// kurzoru v jedné větě naráz — u jednoho vstupu by se posun o konstantu neprojevil.
    @Test("Dvojtečka na spočítané poloze v textu doopravdy je")
    func pointsAtTheColonInTheText() {
        let text = "🎉 Díky :ta a ještě :whi"

        for caret in 0...text.count {
            guard let query = Policy.emojiQuery(in: text, caret: caret) else { continue }
            let colon = text.index(text.startIndex, offsetBy: query.colon)
            #expect(text[colon] == ":", "na \(query.colon) není dvojtečka (kurzor \(caret))")
            let start = text.index(after: colon)
            let end = text.index(text.startIndex, offsetBy: query.caret)
            #expect(String(text[start..<end]) == query.text)
        }
    }
}
