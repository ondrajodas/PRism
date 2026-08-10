import Foundation
import Synchronization

/// Zapamatované obarvení řádků (#224).
///
/// `SyntaxHighlighter` prochází řádek znak po znaku a volá se **při každém vykreslení** — tedy
/// i při přejezdu myší, při skoku mezi nálezy, při psaní do draftu a pokaždé, když líný seznam
/// zahodí blok a za chvíli ho postaví znovu. Naměřeno u #220: **44 ms na 2400 řádků**, a ta práce
/// vycházela pokaždé stejná, protože **text řádku se nemění**.
///
/// Klíč je proto `(text řádku, jméno jazyka)`. Jazyk v něm být musí: `# poznámka` je v shellu
/// komentář a ve Swiftu obyčejný text, takže cache bez jazyka by jeden soubor obarvila podle
/// pravidel druhého.
///
/// **Barvy uvnitř nejsou.** `SyntaxRun` nese druh (`keyword`, `string`), ne `Color` — paletu si
/// bere view až při kreslení. Přepnutí světlého a tmavého režimu proto cache **nezneplatňuje**.
///
/// **Co ji vyprazdňuje.** Po jednotlivých položkách nic: klíčem je text, takže záznam nemůže
/// zastarat — otázka je jen růst. Drží ho dvě hranice a při překročení kterékoli se cache zahodí
/// **celá**: počet zapamatovaných řádků (`capacity`) a součet jejich délek (`budget`). Dvě proto,
/// že každá chytá jiný způsob, jak přetéct: tisíce krátkých řádků z dlouhého sezení, nebo pár
/// obřích řádků z generovaného souboru. Obě se počítají **včetně toho, co se právě vkládá**, takže
/// se přes ně cache nedostane ani na jeden zápis; řádek delší než celý rozpočet se nepamatuje.
///
/// **Zahodit všechno je schválně, ne z lenosti.** Je to O(1) a stojí jeden přepočet toho, co je
/// zrovna vidět — blok o 60 řádcích je z naměřených 18 µs na řádek asi 1,1 ms, tedy nic, co by šlo
/// vidět. LRU by za to platila zápisem pořadí **při každém nahlédnutí**, tedy zdražením té
/// operace, kvůli které cache vznikla.
final class SyntaxRunCache: Sendable {
    /// Cache, kterou používá `SyntaxHighlighter.runs(of:in:)`. Sdílená schválně: řádek `    }`
    /// je tentýž ve všech souborech PR a v obou pohledech na diff.
    static let shared = SyntaxRunCache()

    /// Kolik řádků si cache nejvýš pamatuje. 4000 je s rezervou nejdelší soubor, jaký v tomhle
    /// repu měříme (2400 řádků) — víc by drželo soubory, na které se nikdo nedívá.
    let capacity: Int
    /// Kolik bajtů textu si cache nejvýš pamatuje. Sčítá se **délka řádků**, ne skutečná paměť;
    /// je to horní odhad toho, co z řádku vzniklo, protože spojení run dá zpátky původní text.
    let budget: Int

    private let storage = Mutex(Storage())

    init(capacity: Int = 4000, budget: Int = 4 * 1024 * 1024) {
        self.capacity = capacity
        self.budget = budget
    }

    /// Obarvení řádku — zapamatované, nebo spočítané a zapamatované.
    func runs(of line: String, in language: Language) -> [SyntaxRun] {
        let key = Key(line: line, language: language.name)
        if let cached = cached(key) { return cached }

        let runs = SyntaxHighlighter.scan(line, in: language)
        remember(runs, for: key, size: line.utf8.count)
        return runs
    }

    /// Kolik řádků je zapamatovaných. Čte to test meze a měření — v aplikaci se na to nikdo neptá.
    var count: Int {
        storage.withLock { $0.entries.count }
    }

    private func cached(_ key: Key) -> [SyntaxRun]? {
        storage.withLock { $0.entries[key] }
    }

    private func remember(_ runs: [SyntaxRun], for key: Key, size: Int) {
        // Řádek delší, než je celý rozpočet, se nepamatuje vůbec. Uložit ho znamená přetéct hned
        // a při dalším zápisu zase zahodit všechno — z cache by byla přihrádka na jeden řádek.
        guard size <= budget else { return }

        storage.withLock { storage in
            // Tentýž řádek můžou spočítat dvě vlákna naráz. To druhé už nic nepřidává, takže nesmí
            // ani započítat jeho délku podruhé, ani kvůli němu cache vyprázdnit.
            guard storage.entries.index(forKey: key) == nil else { return }
            // Meze se počítají **včetně toho, co se právě vkládá** — jinak by cache po vložení
            // stála nad rozpočtem až do příštího zápisu, tedy přesně u toho jednoho obřího řádku,
            // kvůli kterému rozpočet je.
            if storage.entries.count + 1 > capacity || storage.bytes + size > budget { storage.clear() }
            storage.entries[key] = runs
            storage.bytes += size
        }
    }

    private struct Storage {
        var entries: [Key: [SyntaxRun]] = [:]
        /// Součet délek zapamatovaných řádků, ne počet položek — viz `budget`.
        var bytes = 0

        mutating func clear() {
            // `keepingCapacity`, protože přihrádky slovníku jsou zrovna to, co se za chvíli zase
            // zaplní; strop paměti drží `capacity`, ne uvolnění pole.
            entries.removeAll(keepingCapacity: true)
            bytes = 0
        }
    }

    /// Jazyk se v klíči nese **jménem**. `Language` se sám porovnává taky podle jména a hashovat
    /// jeho sadu klíčových slov při každém nahlédnutí by stálo víc než samotné obarvení.
    private struct Key: Hashable {
        let line: String
        let language: String
    }
}
