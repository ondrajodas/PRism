import Foundation

/// Co se uvnitř přepsaného řádku změnilo (#153). Čistá funkce, žádné I/O.
///
/// `DiffLine` je celý řádek, takže u řádku, kde se změnilo jedno slovo, svítí zeleně a červeně
/// všechno — a rozdíl se u dlouhého řádku hledá přečtením obou verzí. Tenhle typ říká, **které
/// kusy** řádku se liší; obarvit je je věc kreslení (`DiffTextView`).
///
/// **Nesmí to skončit v `SyntaxRunCache`.** Zvýraznění závisí na **protějšku** řádku, ne jen na
/// jeho textu, takže do cache klíčované `(text řádku, jazyk)` nepatří: tentýž řádek spárovaný
/// s jiným protějškem má jiné zvýraznění a cache by tiše vracela to cizí. Je to proto **druhá
/// vrstva nad** výsledkem z cache (pozadí), ne další druh `SyntaxRun`u.
enum WordDiff {
    /// Zvýrazněné kusy řádků v bloku, klíčované **indexem řádku** v něm.
    ///
    /// Rozsahy patří tomu řetězci, ze kterého se spočítaly (`DiffLine.text` daného řádku) —
    /// jinam se přenášet nedají.
    typealias Spans = [Int: [Range<String.Index>]]

    /// Rozdíl uvnitř jedné dvojice: co ubylo vlevo a co přibylo vpravo.
    struct Change: Equatable {
        let old: [Range<String.Index>]
        let new: [Range<String.Index>]
    }

    /// Kolik textu musí být dvojici společné, aby se ještě počítala za **přepsaný** řádek.
    ///
    /// Pod tím je to smazání a přidání, ne přepsání, a zvýrazňovat se nemá vůbec — jinak by na
    /// dvou nesouvisejících řádcích svítily náhodné závorky a mezery, které se v kódu potkají
    /// vždycky. Počítá se **jen z neprázdných znaků**: odsazení mají společné skoro všechny řádky
    /// souboru a podobnost samo o sobě neznamená.
    ///
    /// Hodnota je **z měření na skutečných diffech**, ne z odhadu (viz specifikace, sekce k #153):
    /// nad 0,30 vyšla v ručně projitém vzorku každá dvojice jako opravdové přepsání
    /// (`.font(.caption2)` → `.font(.system(size: 10.5))` má 0,32), pod 0,27 už to bylo smazání
    /// a přidání vedle sebe (`folding.toggle(file)` proti `file: file,` má 0,20).
    static let similarityThreshold = 0.30

    /// Strop na součin délek obou stran, nad kterým se nehledá nejdelší společná podposloupnost.
    ///
    /// Cena je součin počtu tokenů, takže dva generované řádky po tisících znacích by se počítaly
    /// znatelně dlouho — a je to práce při skládání textu bloku, tedy tam, kde se čeká na
    /// vykreslení. Nad stropem se zvýrazní **celý rozdílný střed**, což je pořád víc informace
    /// než obarvený celý řádek.
    static let pairBudget = 40_000

    // MARK: - Jedna dvojice

    /// Které kusy se v dvojici liší, nebo `nil`, když to přepsaný řádek není.
    ///
    /// `nil` znamená „obarvi to jako dosud“: dvojice si je málo podobná (viz
    /// `similarityThreshold`), jedna strana je prázdná, nebo jsou obě strany shodné.
    static func change(from old: String, to new: String) -> Change? {
        guard !old.isEmpty, !new.isEmpty, old != new else { return nil }

        let oldTokens = tokens(of: old)
        let newTokens = tokens(of: new)
        // Společný začátek a konec jde poznat porovnáním, takže se do dražšího hledání pouští jen
        // to, co zbude uprostřed. U běžné změny (jedno slovo v řádku) zbude pár tokenů.
        let prefix = commonPrefix(oldTokens, newTokens)
        let suffix = commonSuffix(oldTokens, newTokens, after: prefix)
        let oldMiddle = Array(oldTokens[prefix..<(oldTokens.count - suffix)])
        let newMiddle = Array(newTokens[prefix..<(newTokens.count - suffix)])

        let matched = matches(oldMiddle, newMiddle)
        guard isRewrite(
            old: old,
            new: new,
            common: weight(of: oldTokens, outside: prefix ..< (oldTokens.count - suffix))
                + weight(of: oldMiddle, matched: matched.old)
        ) else { return nil }

        return Change(
            old: ranges(of: oldMiddle, matched: matched.old),
            new: ranges(of: newMiddle, matched: matched.new)
        )
    }

    // MARK: - Celé bloky

    /// Zvýraznění uvnitř souvislého úseku řádků — pohled **pod sebou**.
    ///
    /// Páruje se stejným pravidlem jako `DiffRow.paired(_:)`: blok odebraných řádků se
    /// s následujícím blokem přidaných spáruje jeden na jednoho a přebytek na kterékoli straně
    /// zůstane bez protějšku. Kdyby se ta dvě pravidla rozešla, svítilo by v každém pohledu něco
    /// jiného — hlídá to test, který obojí porovnává na skutečném diffu.
    static func spans(in lines: [DiffLine]) -> Spans {
        var result: Spans = [:]
        var removed: [Int] = []
        var added: [Int] = []

        func flush() {
            for (old, new) in zip(removed, added) {
                add(change(from: lines[old].text, to: lines[new].text), old: old, new: new, to: &result)
            }
            removed.removeAll(keepingCapacity: true)
            added.removeAll(keepingCapacity: true)
        }

        for (index, line) in lines.enumerated() {
            switch line.kind {
            case .removed:
                // `+` po `-` je přepsání téhož místa, ale `-` po `+` je další skupina.
                if !added.isEmpty { flush() }
                removed.append(index)
            case .added:
                added.append(index)
            case .context, .meta:
                flush()
            }
        }
        flush()
        return result
    }

    /// Totéž pro pohled **vedle sebe**, kde dvojice existuje: řádek vlevo proti řádku vpravo.
    ///
    /// Páruje se rovnou podle pozice, protože `DiffRow.paired(_:)` sloupce už zarovnal. Zvýrazní
    /// se jen dvojice `-` proti `+` — kontext má na obou stranách tentýž řádek a chybějící
    /// protějšek není co s čím porovnat.
    static func spans(left: [DiffLine?], right: [DiffLine?]) -> (left: Spans, right: Spans) {
        var result: (left: Spans, right: Spans) = ([:], [:])
        for index in 0..<min(left.count, right.count) {
            guard let old = left[index], let new = right[index],
                  old.kind == .removed, new.kind == .added
            else { continue }
            guard let change = change(from: old.text, to: new.text) else { continue }
            add(change.old, at: index, to: &result.left)
            add(change.new, at: index, to: &result.right)
        }
        return result
    }

    // MARK: - Skládání výsledku

    /// Zápis obou stran do **jednoho** slovníku — v pohledu pod sebou leží starý i nový řádek
    /// v témže bloku, jen na jiných indexech.
    private static func add(_ change: Change?, old: Int, new: Int, to spans: inout Spans) {
        guard let change else { return }
        add(change.old, at: old, to: &spans)
        add(change.new, at: new, to: &spans)
    }

    /// Prázdná strana se **nezapisuje**: u čistého přidání slova není na staré straně co
    /// zvýraznit a prázdné pole by tvrdilo něco jiného než „nic tu není“.
    private static func add(_ spans: [Range<String.Index>], at index: Int, to result: inout Spans) {
        guard !spans.isEmpty else { return }
        result[index] = spans
    }

    /// Souvislé úseky nespárovaných tokenů jako rozsahy v řádku. Sousední se slévají do jednoho —
    /// jinak by z jednoho přepsaného jména byly tři obdélníčky.
    private static func ranges(of tokens: [Token], matched: [Bool]) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start: String.Index?
        var end: String.Index?

        for (index, token) in tokens.enumerated() {
            if matched[index] {
                if let start, let end { result.append(start..<end) }
                start = nil
                end = nil
                continue
            }
            if start == nil { start = token.range.lowerBound }
            end = token.range.upperBound
        }
        if let start, let end { result.append(start..<end) }
        return result
    }

    // MARK: - Podobnost

    /// Je dvojice přepsaný řádek, nebo dvě nesouvisející změny?
    private static func isRewrite(old: String, new: String, common: Int) -> Bool {
        let size = max(printable(in: old), printable(in: new))
        guard size > 0 else { return false }
        return Double(common) / Double(size) >= similarityThreshold
    }

    /// Kolik neprázdných znaků text má. Odsazení se nepočítá — mají ho společné skoro všechny
    /// řádky souboru, takže by z něj vycházela podobnost i tam, kde žádná není.
    private static func printable(in text: some StringProtocol) -> Int {
        text.reduce(0) { $1.isWhitespace ? $0 : $0 + 1 }
    }

    /// Váha spárovaných tokenů uprostřed.
    private static func weight(of tokens: [Token], matched: [Bool]) -> Int {
        zip(tokens, matched).reduce(0) { $1.1 ? $0 + printable(in: $1.0.text) : $0 }
    }

    /// Váha toho, co se ořízlo jako společný začátek a konec — ta část je společná z definice.
    private static func weight(of tokens: [Token], outside middle: Range<Int>) -> Int {
        tokens.indices.reduce(0) { middle.contains($1) ? $0 : $0 + printable(in: tokens[$1].text) }
    }

    // MARK: - Tokeny

    /// Kus řádku, který se porovnává jako celek.
    private struct Token {
        let range: Range<String.Index>
        let text: Substring
    }

    /// Řádek na tokeny: jméno (písmena, číslice, `_`), souvislá mezera, souvislý operátor,
    /// a každý ostatní znak zvlášť.
    ///
    /// **Po tokenech, ne po znacích** — rozhodnuto měřením na skutečném diffu (#153): po znacích
    /// se z přepsaného jména stane skvrna složená ze společných písmen a mezer uprostřed, takže se
    /// svítící kusy rozpadnou a je jich několikrát víc. Podrobnosti ve specifikaci.
    ///
    /// **Operátor drží pohromadě** ze stejného důvodu: `==` → `!=` je jedna změna, ale po znacích
    /// by se první `=` spárovalo a svítil by jen jeden znak z dvouznakového operátoru. Závorky,
    /// čárky a středníky se naopak neslévají — jsou to hranice, ne jedno slovo.
    private static func tokens(of line: String) -> [Token] {
        var result: [Token] = []
        var index = line.startIndex

        while index < line.endIndex {
            let start = index
            if isWord(line[index]) {
                while index < line.endIndex, isWord(line[index]) { index = line.index(after: index) }
            } else if line[index].isWhitespace {
                while index < line.endIndex, line[index].isWhitespace { index = line.index(after: index) }
            } else if isOperator(line[index]) {
                while index < line.endIndex, isOperator(line[index]) { index = line.index(after: index) }
            } else {
                index = line.index(after: index)
            }
            result.append(Token(range: start..<index, text: line[start..<index]))
        }
        return result
    }

    private static func isWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// Znaky, které se slévají do jednoho operátoru (`==`, `!=`, `->`, `?.`, `...`).
    private static let operators: Set<Character> = [
        "=", "<", ">", "!", "+", "-", "*", "/", "%", "&", "|", "^", "~", "?", ":", ".",
    ]

    private static func isOperator(_ character: Character) -> Bool {
        operators.contains(character)
    }

    private static func commonPrefix(_ old: [Token], _ new: [Token]) -> Int {
        var count = 0
        while count < old.count, count < new.count, old[count].text == new[count].text { count += 1 }
        return count
    }

    private static func commonSuffix(_ old: [Token], _ new: [Token], after prefix: Int) -> Int {
        var count = 0
        while count < old.count - prefix, count < new.count - prefix,
              old[old.count - 1 - count].text == new[new.count - 1 - count].text { count += 1 }
        return count
    }

    // MARK: - Nejdelší společná podposloupnost

    /// Které tokeny uprostřed mají na druhé straně protějšek.
    ///
    /// Klasické LCS nad tokeny. Tabulka je jednorozměrné pole, ne pole polí — je to horké místo
    /// při skládání textu bloku a vnořené pole by k němu přidalo alokaci na řádek.
    private static func matches(_ old: [Token], _ new: [Token]) -> (old: [Bool], new: [Bool]) {
        var oldMatched = [Bool](repeating: false, count: old.count)
        var newMatched = [Bool](repeating: false, count: new.count)
        // Nad stropem se za shodné neprohlásí nic, takže se zvýrazní celý rozdílný střed. Je to
        // horší zvýraznění, ne chybějící — a hlavně ohraničená práce.
        guard !old.isEmpty, !new.isEmpty, old.count * new.count <= pairBudget else {
            return (oldMatched, newMatched)
        }

        let columns = new.count + 1
        var table = [Int](repeating: 0, count: (old.count + 1) * columns)
        for row in stride(from: old.count - 1, through: 0, by: -1) {
            for column in stride(from: new.count - 1, through: 0, by: -1) {
                table[row * columns + column] = old[row].text == new[column].text
                    ? table[(row + 1) * columns + column + 1] + 1
                    : max(table[(row + 1) * columns + column], table[row * columns + column + 1])
            }
        }

        var row = 0
        var column = 0
        while row < old.count, column < new.count {
            if old[row].text == new[column].text {
                oldMatched[row] = true
                newMatched[column] = true
                row += 1
                column += 1
            } else if table[(row + 1) * columns + column] >= table[row * columns + column + 1] {
                row += 1
            } else {
                column += 1
            }
        }
        return (oldMatched, newMatched)
    }
}
