import Foundation

/// Hledání v nabídkách panelu (#392) — labely repozitáře, lidé a týmy k vyžádání review.
///
/// **Pravidlo shody se dělí s paletou ⌘K** (#184), ne opisuje: `searchRange` a `searchStartsWord`
/// jsou tytéž funkce a dělení dotazu na slova taky (`paletteTokens`). Dvě jinak se chovající
/// hledání v jednom okně je horší než sdílení — člověk si zvykne, že `nalez` najde `nález`, a je
/// jedno, do kterého pole to píše.
///
/// **Sdílí se pravidlo, ne `paletteResults`**, a je to rozhodnutí. Paleta hledá nad
/// `CommandPalette.Item` (titulek, podtitulek, klíčová slova, skupina, akce) a má strop **šest
/// řádků na skupinu**; nabídka reviewerů má třicet čtyři týmů a jednu položku o jednom řetězci.
/// Prohnat ji paletou by znamenalo vyrobit položky s vymyšlenou skupinou a akcí, na kterou se
/// nedá kliknout — tedy víc kódu **a** dvě nová místa v paletě, která tam nemají co dělat. Váha
/// shody je proto tatáž (začátek, hranice slova, vnitřek), jen se počítá nad jedním textem.
extension Policy {
    /// Hledá se **bez ohledu na velikost písmen a na diakritiku**: aplikace je česká, takže
    /// `nalez` musí najít `nález` — jinak by se hledání dalo používat jen s přepnutou klávesnicí.
    ///
    /// Sdílené s paletou (#184), viz úvod.
    static func searchRange(of token: String, in text: String) -> Range<String.Index>? {
        text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive])
    }

    /// Začíná shoda na hranici slova? Předchozí znak nesmí být písmeno ani číslice — `/`, `.`,
    /// `-`, `_` i mezera tedy hranice jsou. U cest k souborům to rozhoduje (`secret`
    /// v `src/Vault/SecretClient.php` váží víc než v `MySecretThing.php`) a u slugů týmů stejně:
    /// `swimlane` má v `ajda-swimlane` vážit víc než uprostřed slova.
    ///
    /// **Shoda na začátku textu je hranice slova, ne pád** (nález Copilota). Do #392 to byla
    /// `private` funkce palety, kterou volal jediný volající — a ten se na `startIndex` ptal dřív.
    /// Jako sdílená by na něm padala na `index(before:)`, tedy runtime trapem u prvního volajícího,
    /// který si tu podmínku nepřečte. Skrytá precondition ve funkci, kterou používá víc míst, je
    /// past; totální funkce past není a odpověď „začátek je hranice“ je navíc ta správná.
    static func searchStartsWord(at range: Range<String.Index>, in text: String) -> Bool {
        guard range.lowerBound != text.startIndex else { return true }
        let previous = text[text.index(before: range.lowerBound)]
        return !previous.isLetter && !previous.isNumber
    }

    /// Váha jednoho textu proti dotazu. `nil` = nesedí, nula = nejlepší.
    ///
    /// Tři stupně jako u titulku v paletě: **začátek**, **hranice slova**, **vnitřek**. Víc slov
    /// dotazu se bere jako **a zároveň** (musí sednout všechna) a váha je z nich **nejlepší** —
    /// tatáž úvaha jako v paletě: stačí, aby se jedno potkalo se začátkem, a řádek jde nahoru.
    ///
    /// Prázdný dotaz sedne na všechno s nulovou váhou, takže nabídka bez psaní drží pořadí, ve
    /// kterém přišla (u lidí a týmů abecedně, u labelů tak, jak je dává repozitář).
    static func pickerRank(of text: String, query: String) -> Int? {
        let tokens = paletteTokens(in: query)
        guard !tokens.isEmpty else { return 0 }

        var best = Int.max
        for token in tokens {
            guard let range = searchRange(of: token, in: text) else { return nil }
            if range.lowerBound == text.startIndex {
                best = min(best, 0)
            } else {
                best = min(best, searchStartsWord(at: range, in: text) ? 1 : 2)
            }
        }
        return best
    }

    /// Nabídka po filtru. Řadí se podle váhy shody, při shodě **podle původního pořadí**.
    ///
    /// Původní pořadí se nese jako druhé kritérium schválně: Swiftové `sorted` **není stabilní**,
    /// takže by dvě položky se stejnou váhou přeskakovaly mezi stisky klávesy. Tatáž past jako
    /// v paletě.
    ///
    /// `text(_:)` je to, co je v řádku **vidět** — a je to podmínka, ne parametr pro pohodlí: kdyby
    /// se filtrovalo podle něčeho, co v řádku není, vypadal by výsledek jako chyba.
    static func filteredPicker<Item>(
        _ items: [Item],
        query: String,
        text: (Item) -> String
    ) -> [Item] {
        items.enumerated()
            .compactMap { order, item -> (item: Item, rank: Int, order: Int)? in
                guard let rank = pickerRank(of: text(item), query: query) else { return nil }
                return (item, rank, order)
            }
            .sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
            .map(\.item)
    }

    /// Má nabídka o `count` položkách kreslit hledací pole?
    ///
    /// **Nad šesti položkami, tedy od sedmi.** Tři jména se přečtou rychleji, než se do pole klikne,
    /// a nad prázdnou nabídkou by to bylo pole, ve kterém se nedá nic najít.
    ///
    /// Rozhodnutí je tady, ne ve views, a je to jedna hodnota pro **obě** nabídky (#392): do téhle
    /// změny měla každá vlastní `searchFrom = 6`, takže se prahy mohly rozejít potichu — a jediné,
    /// co by z toho bylo vidět, je jedna nabídka s polem a druhá bez. Zároveň je to jediný způsob,
    /// jak se ta hranice dá otestovat výčtem: pole je stav skutečného okna, kdežto tohle je číslo.
    static func pickerShowsSearch(count: Int) -> Bool {
        count > searchFrom
    }

    /// Od kolika položek má hledání smysl. Kreslí se **nad** touhle hodnotou, viz
    /// `pickerShowsSearch(count:)`.
    static let searchFrom = 6

    /// Kam se posune vybraný řádek po šipce. `count == 0` znamená, že není co vybírat.
    ///
    /// **Ořezává, necyklí.** V nabídce, která se pod rukama filtruje, je přeskok z konce na začátek
    /// k nerozeznání od „šipka nic neudělala“ — a u třiceti položek by se to stalo při každém
    /// přidržení klávesy. Ořez drží kurzor tam, kde na něj člověk kouká.
    static func pickerSelection(from current: Int, step: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return min(max(0, current + step), count - 1)
    }
}
