import Foundation

/// Našeptávání emotikonů v textovém poli (#483) — **rozhodnutí, ne kresba**.
///
/// Tři věci, a každá je čistá funkce, takže se testují výčtem, ne klikáním: **kdy je otevřený
/// dotaz** (`emojiQuery`), **co se v něm nabídne** (`emojiSuggestions`) a **co z toho vznikne
/// v textu** (`emojiInsertion`). Planý poplach v textovém poli se jinak pozná až v provozu.
///
/// **Kurzor se sem předává jako počet znaků od začátku, ne jako `String.Index`.** Je to podmínka,
/// ne pohodlí: `String.Index` z jiné verze textu položí `distance(from:to:)` **trapem**, a pole
/// mění text i kurzor ve dvou různých okamžicích. Číslo se dá bezpečně ověřit proti délce textu
/// a navíc se dá napsat do testu.
extension Policy {
    /// Otevřený dotaz na emotikon — `:` a to, co se za ní napsalo.
    struct EmojiQuery: Equatable {
        /// Text za dvojtečkou, tedy to, co se hledá. Bez `:`.
        let text: String
        /// Kde stojí `:`, v počtu znaků od začátku textu. To je zároveň začátek rozsahu, který
        /// vložený znak nahradí.
        let colon: Int
        /// Kde stojí kurzor, v počtu znaků od začátku. Konec toho rozsahu.
        let caret: Int
    }

    /// Jeden řádek nabídky.
    struct EmojiSuggestion: Equatable, Identifiable {
        let emoji: Emoji
        /// Alias, kterým shoda přišla. `nil` = sedlo jméno, které je v řádku vidět, takže není co
        /// dopisovat vpravo.
        let alias: String?

        /// **Identita je znak**, ne jméno ani pořadí: řádek je na znak (`:+1:` a `:thumbsup:` je
        /// jeden 👍), takže dva řádky s jednou identitou vzniknout nemají.
        var id: String { emoji.character }
    }

    /// Nový text a nová poloha kurzoru po vložení znaku.
    struct EmojiInsertion: Equatable {
        let text: String
        /// Kurzor **za vloženým znakem**, v počtu znaků od začátku.
        let caret: Int
    }

    // MARK: - Kdy je dotaz otevřený

    /// Dotaz na emotikon pro text a polohu kurzoru. `nil` = nabídka se nemá otevřít.
    ///
    /// **Dvojtečka je v próze běžný znak, takže rozhodovat nemůže sama.** Otevře se, jedině když je
    /// `:` na **začátku textu nebo po mezeře** a za ní stojí něco, z čeho může být shortcode — viz
    /// `emojiQueryHasSubstance(_:)`. Tím vypadnou tři nejčastější plané poplachy naráz: `12:30`
    /// (dvojtečka po číslici), `https://…` (po písmenu) a `Poznámka:` (po písmenu, a za ní mezera).
    ///
    /// „Po mezeře“ znamená po **jakémkoli bílém znaku** — tedy i na začátku řádku uprostřed textu.
    /// `Character.isWhitespace` je na to ta správná otázka a `CRLF` je v něm jeden znak, takže se
    /// nemusí nic dělit (pravidlo z #295 se tu neuplatňuje, protože se text nedělí na řádky).
    ///
    /// **Kurzor musí stát na konci dotazu**, ne kdekoli za dvojtečkou: dotaz je to, co je vlevo od
    /// kurzoru. Odchod kurzoru jinam tím nabídku zavírá sám, bez druhého pravidla.
    static func emojiQuery(in text: String, caret: Int) -> EmojiQuery? {
        guard caret > 0, caret <= text.count else { return nil }
        let caretIndex = text.index(text.startIndex, offsetBy: caret)

        var start = caretIndex
        var length = 0
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard isEmojiQueryCharacter(text[previous]) else { break }
            start = previous
            length += 1
        }
        // Před dotazem musí stát dvojtečka a dotaz nesmí být prázdný.
        guard length > 0, start > text.startIndex else { return nil }
        let colonIndex = text.index(before: start)
        guard text[colonIndex] == ":" else { return nil }

        let query = String(text[start..<caretIndex])
        guard emojiQueryHasSubstance(query) else { return nil }
        // Dvojtečka na začátku textu, nebo po bílém znaku.
        guard colonIndex == text.startIndex
            || text[text.index(before: colonIndex)].isWhitespace
        else { return nil }

        return EmojiQuery(text: query, colon: caret - length - 1, caret: caret)
    }

    /// Může z toho, co je za dvojtečkou, být shortcode? (#483, rozšířeno po proklikání)
    ///
    /// Tři pravidla, a **nejsou symetrická schválně**:
    ///
    /// 1. **Písmeno kdekoli v dotazu** — to je ta obvyklá cesta (`:ta`, `:e-mail`, `:u7121`).
    /// 2. **Dotaz začínající `+`** projde hned, tedy i samotné `:+`. Do prvního proklikání sem
    ///    patřilo jen písmeno, čímž vypadly `:+1:` a `:-1:` — dva nejčastější shortcody na GitHubu.
    ///    `:+` je přitom v próze po mezeře skoro nemožné, takže se za to neplatí ničím.
    /// 3. **Dotaz začínající `-` potřebuje ještě jeden znak.** `:-1` tedy projde, samotné `:-` ne —
    ///    a je to kvůli **textovým smajlíkům**: `:-)` a `:-(` jsou v české próze běžnější než
    ///    `:-1:` a začínají přesně tou kombinací. Bez tohohle pravidla by nabídka na `:-` **problikla**
    ///    (👎, 🚱, 🦖) a při dopsání `)` zmizela — a to není detail, to je viditelné chování
    ///    v každé druhé větě. Hotový smajlík nabídku neotevře ani tak (`)` a `(` nejsou znaky
    ///    dotazu), takže se tímhle zavírá právě a jen ten mezistav.
    ///
    /// **Číslice sama nestačí** (`:1`, `:30`) a podtržítko taky ne (`:_`): ani jedno není začátek
    /// shortcodu, který by šel dopsat.
    ///
    /// Zvažovaná a zamítnutá varianta (symetrická, `+` i `-` hned) je v záznamu rozhodnutí ve
    /// specifikaci.
    private static func emojiQueryHasSubstance(_ query: String) -> Bool {
        if query.contains(where: \.isLetter) { return true }
        guard let first = query.first else { return false }
        if first == "+" { return true }
        if first == "-" { return query.count > 1 }
        return false
    }

    /// Smí ten znak stát v dotazu za dvojtečkou?
    ///
    /// Písmena, číslice a `_`, `+`, `-` — tedy přesně to, z čeho se skládají shortcody v katalogu
    /// (`+1`, `-1`, `e-mail`, `white_check_mark`). Mezera mezi nimi není, a proto mezera nabídku
    /// zavírá: hned za ní dotaz končí.
    private static func isEmojiQueryCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "+"
            || character == "-"
    }

    // MARK: - Co se nabídne

    /// Kolik řádků nabídka nejvýš vydá.
    ///
    /// **Šest, a je to strop kresby, ne libovůle.** Bez stropu by dotaz `:a` vydal stovky řádků
    /// a nabídka by přerostla okno; se stropem má **203 bodů** (změřeno, `EmojiSuggestionMenuTests`
    /// na to má strop 210), takže nepotřebuje scroll — a bez scrollu je `↑↓` prostě posun po
    /// řádcích, ne posun po řádcích plus rolování. Návrh (sekce 38) kreslí šest, čtyři a dva řádky,
    /// tedy jednu scénu **na** stropu a dvě pod ním.
    static let emojiSuggestionLimit = 6

    /// Řádky nabídky pro daný dotaz. Prázdný výsledek znamená **nabídka se nekreslí**.
    ///
    /// **Řadí se váhou shody, při shodě pořadím v katalogu** — tedy stejně jako nabídky v panelu
    /// (`filteredPicker`). Swiftové `sorted` není stabilní, takže bez druhého kritéria by řádky
    /// se stejnou váhou mezi stisky klávesy přeskakovaly.
    ///
    /// **Stupně shody se dělí s paletou ⌘K i s nabídkami panelu** (`searchStartsWord`): začátek
    /// jména, hranice slova, vnitřek. Co se **nedělí, je `searchRange` a `pickerRank`**, a je to
    /// vědomé rozhodnutí ze dvou důvodů:
    ///
    /// - **Věcně.** Shortcody jsou ASCII malými písmeny (ověřeno nad celým katalogem), takže dotaz
    ///   složený na malá písmena dá s `.caseInsensitive` **tentýž** výsledek — kdežto
    ///   `.diacriticInsensitive` ze `searchRange` by přidalo shody, které nikdo nechce: `:čá` by
    ///   po složení diakritiky nabídlo `taco`.
    /// - **Cenou.** Tahle smyčka běží při **každém úhozu** s otevřenou nabídkou.
    ///   `range(of:options:)` nad 1913 jmény stojí **1,88 ms**, prosté `range(of:)` nad složeným
    ///   dotazem **0,50 ms** (změřeno v `-O`; v Debug buildu je to čtyřnásobek obojího).
    ///   `pickerRank` by k tomu dotaz **1913× tokenizoval na slova**, což je práce nazmar: v dotazu
    ///   na emotikon žádná mezera být nemůže (viz `emojiQuery`).
    static func emojiSuggestions(
        for query: String,
        in catalog: [Emoji] = EmojiCatalog.all,
        limit: Int = emojiSuggestionLimit
    ) -> [EmojiSuggestion] {
        guard !query.isEmpty, limit > 0 else { return [] }
        // Jednou na dotaz, ne jednou na jméno.
        let needle = query.lowercased()

        var scored: [(row: EmojiSuggestion, rank: Int, order: Int)] = []
        for (order, emoji) in catalog.enumerated() {
            guard let hit = emojiHit(of: emoji, query: needle) else { continue }
            scored.append((EmojiSuggestion(emoji: emoji, alias: hit.alias), hit.rank, order))
        }
        return scored
            .sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
            .prefix(limit)
            .map(\.row)
    }

    /// Nejlepší shoda jednoho znaku. `alias` je neprázdný jen tehdy, když ji nedalo jméno z řádku.
    ///
    /// **Jméno má přednost i při stejné váze**: řádek jméno kreslí, takže dopisovat vedle něj alias,
    /// který sedí zrovna tak dobře, by byl šum.
    /// Jména se prohánějí **bez `Emoji.names`**, tedy bez pole na každou položku: tahle smyčka běží
    /// 1870× na úhoz, takže jedna zbytečná alokace na kolo už je měřitelná.
    private static func emojiHit(of emoji: Emoji, query: String) -> (rank: Int, alias: String?)? {
        var best: (rank: Int, alias: String?)?
        if let rank = emojiRank(of: emoji.name, query: query) {
            best = (rank, nil)
        }
        for alias in emoji.aliases {
            guard let rank = emojiRank(of: alias, query: query) else { continue }
            if let current = best, current.rank <= rank { continue }
            best = (rank, alias)
        }
        return best
    }

    /// Váha jednoho shortcodu proti dotazu. `nil` = nesedí, nula = nejlepší.
    ///
    /// Tři stupně jako u titulku v paletě: **začátek**, **hranice slova** (u shortcodů `_`, `+`
    /// a `-`), **vnitřek**. `query` už musí být **složený na malá písmena** — viz
    /// `emojiSuggestions(for:in:limit:)`.
    private static func emojiRank(of name: String, query: String) -> Int? {
        guard let range = name.range(of: query) else { return nil }
        if range.lowerBound == name.startIndex { return 0 }
        return searchStartsWord(at: range, in: name) ? 1 : 2
    }

    // MARK: - Jak se shortcode vysází

    /// Shortcode, jak stojí v řádku nabídky — `:jméno:`, a **se zlomy uvnitř**.
    ///
    /// **Jméno se má zalomit, ne ořezat** (návrh, `overflow-wrap: anywhere`): je jediné, podle čeho
    /// se pozná, který znak se vloží — tatáž úvaha jako u jména nového labelu v #413. Jenže shortcode
    /// je **jedno slovo s podtržítky** a `Text` ve SwiftUI uvnitř slova nezalamuje: změřeno na
    /// 48znakovém jméně, kde zůstal na jednom řádku a **přetekl** za hranu nabídky (výška se přitom
    /// nezměnila, takže by se to `fittingSize`m nepoznalo).
    ///
    /// Zlom se proto **nabídne**, a to nulovou mezerou (`U+200B`) za oddělovači. Není to hack pro
    /// hack: podtržítko je v shortcodu hranice slova, takže je to zrovna to místo, kde by se text
    /// zalomil, kdyby to bylo v próze. Delší úsek než 16 znaků mezi oddělovači v katalogu není
    /// (`arrows_counterclockwise`), takže se tím zalomí každé jméno, které se nevejde.
    ///
    /// Do textu zprávy se **nedostane nic z tohohle** — vkládá se znak, ne jméno. A čtečka obrazovky
    /// čte popisek řádku, ne tenhle řetězec.
    static func emojiShortcodeLabel(of name: String) -> String {
        var drawn = ":"
        for character in name {
            drawn.append(character)
            if character == "_" || character == "-" || character == "+" {
                drawn.append(emojiWordBreak)
            }
        }
        return drawn + ":"
    }

    /// Nulová mezera — nabídnutý zlom, který se nekreslí.
    static let emojiWordBreak: Character = "\u{200B}"

    // MARK: - Co z toho vznikne v textu

    /// Text po vložení znaku — **záměna napsaného dotazu za znak** (`:ta` → 🎉), ne přidání na
    /// konec.
    ///
    /// **Odejde znak, ne shortcode.** Composer je obyčejné textové pole a odchází jeho obsah, takže
    /// vložený `:tada:` by byl náhled, který tvrdí něco jiného než výsledek na GitHubu. Je to tatáž
    /// úvaha, kvůli které se u nového labelu posílá hex vždycky (#413).
    ///
    /// `nil` = dotaz **nesedí na tenhle text**, a je to jediná správná odpověď: vložit znak na
    /// spočítané místo v jiném textu znamená rozsekat větu, kterou tam někdo napsal. Pole se proti
    /// tomu chrání tím, že dotaz počítá z **téhož** textu, do kterého pak vkládá — takže se to
    /// stát nemá; test na to je, aby se z „nemá“ nestalo „položí to text“.
    static func emojiInsertion(
        into text: String,
        replacing query: EmojiQuery,
        with emoji: String
    ) -> EmojiInsertion? {
        guard query.colon >= 0, query.caret > query.colon, query.caret <= text.count else {
            return nil
        }
        let lower = text.index(text.startIndex, offsetBy: query.colon)
        let upper = text.index(text.startIndex, offsetBy: query.caret)

        var replaced = text
        replaced.replaceSubrange(lower..<upper, with: emoji)
        return EmojiInsertion(text: replaced, caret: query.colon + emoji.count)
    }
}
