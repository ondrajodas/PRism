import Foundation
import Testing

@testable import PRism

/// **Co nabídka emotikonů vydá a co z toho vznikne v textu** (#483).
///
/// Dvě věci, které se rozbijí potichu: **slučování aliasů** (jeden znak = jeden řádek) a **záměna
/// dotazu za znak** (rozsah o jeden vedle sežere znak před dvojtečkou). Obojí je čistá funkce, takže
/// se testuje nad daty, ne klikáním.
///
/// Prohání se to **skutečným katalogem**, ne vymyšleným: fixture by nesla pořadí a aliasy, které
/// v aplikaci nejsou, a zrovna na nich ta dvě pravidla stojí. Malý katalog se používá jen tam, kde
/// se tvrdí o **pravidlu** (strop, prázdný dotaz).
@Suite("Řádky nabídky emotikonů (#483)")
struct EmojiSuggestionRowTests {
    // MARK: - Slučování aliasů

    /// `:thu` vrátí 👍 **jednou, ne dvakrát** — a alias se nese s řádkem.
    ///
    /// Je to ten případ, na kterém stojí rozhodnutí „řádek je na znak, ne na jméno“: `+1`
    /// a `thumbsup` jsou tentýž znak, takže dva řádky by byly nabídka, ve které se nedá vybrat ani
    /// dobře, ani špatně.
    @Test("Dotaz „thu“ vrátí jeden palec a nese alias")
    func mergesAliasesIntoOneRow() throws {
        let rows = Policy.emojiSuggestions(for: "thu")

        #expect(rows.filter { $0.emoji.character == "👍" }.count == 1)
        let thumb = try #require(rows.first)
        #expect(thumb.emoji.character == "👍")
        // Kreslí se jméno z katalogu (`+1`), protože tak ten znak jmenuje GitHub…
        #expect(thumb.emoji.name == "+1")
        // …a alias je vidět vpravo, jinak by řádek `:+1:` vypadal na dotaz `:thu` jako omyl.
        #expect(thumb.alias == "thumbsup")
        #expect(rows[safely: 1]?.emoji.character == "👎")
        #expect(rows[safely: 1]?.alias == "thumbsdown")
    }

    /// **Shoda přes jméno alias nedopisuje.** Řádek to jméno kreslí, takže by to byl šum.
    @Test("Shoda přes jméno nemá alias")
    func leavesTheAliasEmptyWhenTheNameMatches() throws {
        let rows = Policy.emojiSuggestions(for: "tada")

        #expect(rows.count == 1)
        let tada = try #require(rows.first)
        #expect(tada.emoji.character == "🎉")
        #expect(tada.emoji.name == "tada")
        #expect(tada.alias == nil)
    }

    /// Řádek nalezený **jedině** aliasem ho ukáže, i když je znak v katalogu pod jiným jménem:
    /// `:w` najde 🌔 přes `waxing_gibbous_moon`, a jméno v řádku je `moon`.
    @Test("Řádek nalezený aliasem alias ukáže")
    func carriesTheAliasThatMatched() throws {
        let rows = Policy.emojiSuggestions(for: "waxing_gib")

        let moon = try #require(rows.first)
        #expect(moon.emoji.character == "🌔")
        #expect(moon.emoji.name == "moon")
        #expect(moon.alias == "waxing_gibbous_moon")
    }

    // MARK: - Řazení a strop

    /// **Váha shody rozhoduje, pořadí katalogu je až druhé kritérium** — tedy stejně jako nabídky
    /// v panelu. `check` na začátku jména váží víc než uprostřed.
    @Test("Začátek jména váží víc než hranice slova")
    func ranksTheStartOfTheNameFirst() throws {
        let rows = Policy.emojiSuggestions(for: "check")

        #expect(rows.first?.emoji.name == "checkered_flag")
        let names = rows.map(\.emoji.name)
        #expect(names.contains("white_check_mark"))
        // Podtržítko je hranice slova, takže `white_check_mark` je až za shodou na začátku.
        let flag = try #require(names.firstIndex(of: "checkered_flag"))
        let mark = try #require(names.firstIndex(of: "white_check_mark"))
        #expect(flag < mark)
    }

    /// Při stejné váze drží pořadí **katalog**, a ten je abecedně podle prvního shortcodu. Bez toho
    /// druhého kritéria by řádky mezi úhozy přeskakovaly (`sorted` ve Swiftu není stabilní).
    @Test("Stejná váha se řadí abecedně, jak je katalog")
    func keepsTheCatalogOrderOnTies() {
        let rows = Policy.emojiSuggestions(for: "ta")

        #expect(rows.map(\.emoji.name) == [
            "taco", "tada", "taiwan", "tajikistan", "takeout_box", "tamale",
        ])
    }

    /// Strop je **šest řádků**, jinak by `:a` přerostlo okno.
    @Test("Nabídka nevydá víc než strop")
    func stopsAtTheLimit() {
        #expect(Policy.emojiSuggestionLimit == 6)
        #expect(Policy.emojiSuggestions(for: "a").count == 6)
        #expect(Policy.emojiSuggestions(for: "a", limit: 2).count == 2)
        // Nula znamená „nic“, ne „bez stropu“ — jinak by přepnutá konstanta vykreslila 1870 řádků.
        #expect(Policy.emojiSuggestions(for: "a", limit: 0).isEmpty)
    }

    /// Prázdný dotaz a dotaz bez shody dávají **prázdno**, což je stav „nabídka se nekreslí“.
    ///
    /// **`čá` je mezi nimi schválně**: hledání v panelu i v paletě je diakritiku ignorující (`nalez`
    /// najde `nález`), a kdyby se to pravidlo vzalo i sem, nabídlo by `:čá` po složení diakritiky
    /// `taco`. Shortcody jsou ASCII, takže tady je správná odpověď „nic“.
    @Test("Bez shody se nekreslí nic", arguments: ["", "qqzzx", "🎉", "čá", "tádá"])
    func returnsNothingWithoutAMatch(query: String) {
        #expect(Policy.emojiSuggestions(for: query).isEmpty)
    }

    /// **Velká písmena jsou data, ne chyba** — dotaz se skládá na malá jednou, ne u každého jména.
    @Test("Hledá se bez ohledu na velikost písmen", arguments: ["TADA", "Tada", "tAdA"])
    func ignoresTheCaseOfTheQuery(query: String) {
        #expect(Policy.emojiSuggestions(for: query).first?.emoji.character == "🎉")
    }

    // MARK: - Jak se shortcode vysází

    /// Shortcode se kreslí **v dvojtečkách a se nabídnutými zlomy** — jinak by nejdelší jméno
    /// z katalogu přeteklo za hranu nabídky (`Text` uvnitř slova nezalamuje, změřeno
    /// v `EmojiSuggestionMenuTests`).
    ///
    /// Tvrdí se obojí: že tam ty zlomy jsou, **a** že se jméno po jejich odebrání nezměnilo — zlom
    /// je nabídka pro sazbu, ne úprava dat.
    @Test("Shortcode se sází v dvojtečkách a se zlomy", arguments: [
        "tada", "+1", "white_check_mark", "hand_with_index_finger_and_thumb_crossed", "e-mail",
    ])
    func drawsTheShortcodeWithBreakOpportunities(name: String) {
        let drawn = Policy.emojiShortcodeLabel(of: name)
        let stripped = drawn.filter { $0 != Policy.emojiWordBreak }

        #expect(stripped == ":\(name):")
        let separators = name.filter { $0 == "_" || $0 == "-" || $0 == "+" }.count
        #expect(drawn.filter { $0 == Policy.emojiWordBreak }.count == separators)
    }

    /// **Do textu zprávy se ze sazby nedostane nic.** Vkládá se znak, ne jméno — takže se nulová
    /// mezera nemá kudy dostat do komentáře, který jde na GitHub.
    @Test("Nulová mezera se do zprávy nedostane")
    func keepsTheZeroWidthSpaceOutOfTheMessage() throws {
        let text = "Díky :ta"
        let query = try #require(Policy.emojiQuery(in: text, caret: 8))
        let row = try #require(Policy.emojiSuggestions(for: query.text).first)

        let insertion = try #require(
            Policy.emojiInsertion(into: text, replacing: query, with: row.emoji.character)
        )

        #expect(!insertion.text.contains(Policy.emojiWordBreak))
    }

    // MARK: - Vložení

    /// Vstupy: text, dotaz a to, co má vzniknout. Ve všech se **zaměňuje napsaný dotaz**, ne přidává
    /// na konec — a v posledních dvou zůstává text **za** kurzorem nedotčený.
    nonisolated static let insertions: [(text: String, query: String, result: String, caret: Int)] = [
        (":ta", ":ta", "🎉", 1),
        ("Díky za úklid anotací :ta", ":ta", "Díky za úklid anotací 🎉", 23),
        ("Díky :ta!", ":ta", "Díky 🎉!", 6),
        ("Díky :ta a ještě něco", ":ta", "Díky 🎉 a ještě něco", 6),
        ("🎉 :ta", ":ta", "🎉 🎉", 3),
    ]

    @Test("Vložení zamění dotaz za znak", arguments: insertions)
    func replacesTheQueryWithTheCharacter(
        input: (text: String, query: String, result: String, caret: Int)
    ) throws {
        let colon = try #require(input.text.range(of: input.query))
        let query = Policy.EmojiQuery(
            text: String(input.query.dropFirst()),
            colon: input.text.distance(from: input.text.startIndex, to: colon.lowerBound),
            caret: input.text.distance(from: input.text.startIndex, to: colon.upperBound)
        )

        let insertion = try #require(Policy.emojiInsertion(into: input.text, replacing: query, with: "🎉"))

        #expect(insertion.text == input.result)
        #expect(insertion.caret == input.caret)
        // V textu je **znak**, ne shortcode — to je celé to rozhodnutí (#483).
        #expect(!insertion.text.contains(":tada:"))
        #expect(!insertion.text.contains(input.query))
    }

    /// **Zastaralý dotaz text nerozseká.** Je to to nejcennější tvrzení téhle sady: kdyby se rozsah
    /// jen ořezal do délky textu, vloží se znak doprostřed věty, kterou tam někdo napsal — a pozná
    /// se to až z odeslaného komentáře.
    nonisolated static let stale: [(colon: Int, caret: Int, why: String)] = [
        (5, 40, "kurzor za koncem textu"),
        (-1, 3, "dvojtečka v mínusu"),
        (3, 3, "prázdný rozsah"),
        (5, 2, "kurzor před dvojtečkou"),
    ]

    @Test("Zastaralý dotaz nevloží nic", arguments: stale)
    func refusesAStaleQuery(input: (colon: Int, caret: Int, why: String)) {
        let text = "Díky :ta"
        let query = Policy.EmojiQuery(text: "ta", colon: input.colon, caret: input.caret)

        #expect(
            Policy.emojiInsertion(into: text, replacing: query, with: "🎉") == nil,
            "vložilo se i s \(input.why)"
        )
    }

    /// Dotaz spočítaný `emojiQuery` a vložení podle něj do sebe **musí zapadnout na každé poloze
    /// kurzoru** — u jednoho vstupu by se posun o konstantu neprojevil.
    @Test("Dotaz a vložení do sebe zapadnou na každé poloze")
    func fitsTogetherAtEveryCaret() throws {
        let text = "🎉 Díky :ta a ještě :whi"

        for caret in 0...text.count {
            guard let query = Policy.emojiQuery(in: text, caret: caret) else { continue }
            let insertion = try #require(Policy.emojiInsertion(into: text, replacing: query, with: "🌮"))
            // Vložený znak stojí na místě dvojtečky a text okolo zůstal.
            #expect(insertion.text.count == text.count - query.text.count)
            #expect(insertion.caret == query.colon + 1)
            let placed = insertion.text.index(insertion.text.startIndex, offsetBy: query.colon)
            #expect(insertion.text[placed] == "🌮")
        }
    }
}
