import Foundation

/// Co se v diffu hledá (#152, návrh sekce 39).
///
/// **Podřetězec, ne regulární výraz.** V kódu se hledá jméno, a chybný regexp je stav, který by
/// pruh musel hlásit — tedy hláška navíc u operace, která má mít odpověď hned.
struct DiffSearchQuery: Hashable, Sendable {
    let text: String
    /// Rozlišovat velikost písmen. Výchozí je **nerozlišovat**: `flush_timeout` má najít
    /// `FLUSH_TIMEOUT`, protože kdo hledá, obvykle ještě neví, jak se to jmenuje přesně.
    var isCaseSensitive = false

    /// Hledá se vůbec? Prázdný dotaz **nesmí najít všechno** — a taky nic, tedy ani prázdný stav:
    /// prázdné pole je „ještě jsem nezačal“, ne „nenašlo se“.
    var isActive: Bool { !text.isEmpty }
}

/// Jeden výskyt v diffu.
///
/// **Neklíčuje se `id`em řádku ze seznamu**, ale samotným řádkem. Identita řádku se totiž mezi
/// pohledy liší: ve split pohledu nese dvojice `id` **pravého** řádku (`DiffRow.paired(_:)`), takže
/// `id` odebraného řádku v seznamu vůbec není a `scrollTo` by na něj tiše nic neudělalo. Řádek se
/// naproti tomu pozná v obou pohledech — hledá ho `DiffRow.anchor(in:hit:layout:revealed:content:)`
/// stejně, jako se hledá kotva mého rozdělaného komentáře.
struct DiffSearchHit: Hashable, Sendable {
    /// Cesta, pod kterou soubor v okně vystupuje (`FileDiff.displayPath`).
    let path: String
    /// Řádek, ve kterém výskyt je. Porovnává se s ním i při kreslení, takže je to **tentýž** údaj
    /// pro skok i pro zvýraznění.
    let line: DiffLine
    /// Kolikátý výskyt na tom řádku (od nuly). Jeden řádek jich může nést několik a každý z nich
    /// je vlastní zastávka.
    let occurrence: Int
}

/// Co se v bloku zvýrazní (#152).
///
/// **Druhá vrstva nad výsledkem ze `SyntaxRunCache`, nikdy v ní** (#153): zvýraznění závisí na
/// dotazu, kdežto cache je klíčovaná `(text řádku, jazyk)` — tentýž řádek by z ní při jiném dotazu
/// vytáhl cizí zvýraznění, a to potichu. Přidává se proto až atributem přes hotové runy
/// (`DiffTextView.highlightSearch`).
struct DiffSearchHighlight: Equatable {
    /// Nehledá se. Výchozí stav všude, kde o hledání nikdo neřekl.
    static let none = DiffSearchHighlight(query: nil, current: nil)

    let query: DiffSearchQuery?
    /// Výskyt, na kterém člověk právě stojí — sytější podklad. `nil`, když se ještě nikam
    /// neskočilo, nebo když aktuální výskyt leží v **jiném souboru** (vybírá to volající, protože
    /// blok o svém souboru ví, kdežto text v něm ne).
    let current: DiffSearchHit?

    var isActive: Bool { query?.isActive ?? false }

    /// Je tenhle výskyt ten aktuální?
    func isCurrent(_ line: DiffLine, occurrence: Int) -> Bool {
        guard let current else { return false }
        return current.line == line && current.occurrence == occurrence
    }
}

/// Hledání v diffu — **čisté funkce nad modelem, žádné I/O** (#152).
///
/// Hledá se nad `Diff`em, ne nad tím, co je nakreslené, a není to volba: od #469 kreslí diff pevný
/// `VStack` a blok kódu mimo pás kolem výřezu **nemá `NSTextView` vůbec** (`Policy.mountBand`,
/// `DiffBlockSlot`). Nad vykresleným textem by hledání našlo obrazovku a půl a počet výskytů by se
/// **měnil s odrolováním**.
///
/// **Rozsah je to, co je načtené**: hunky a rozbalený kontext (#47). Zbytek souborů se kvůli
/// hledání nedotahuje — u PR o padesáti souborech je to padesát volání na GitHub kvůli jednomu
/// slovu. Že se hledá jen tam, **říká pruh na obrazovce** (`Policy.searchScopeNote`), a prázdný
/// výsledek se proto nehlásí jako „nic nenalezeno“ (`Policy.searchEmptyNote`).
enum DiffSearch {
    /// Kde na řádku dotaz sedí. **Jediné místo, kde se porovnává** — počet výskytů i jejich
    /// podklad v textu z něj vycházejí, takže se nemají jak rozejít.
    ///
    /// Výskyty se **nepřekrývají** a jdou zleva doprava: `aa` v `aaa` je jeden výskyt, ne dva.
    /// Je to volba, ne omezení hledání — dva se překrývající podklady by se v textu složily do
    /// jednoho a počet by pak tvrdil něco, co v okně není vidět.
    static func ranges(in text: String, query: DiffSearchQuery) -> [Range<String.Index>] {
        guard query.isActive, !text.isEmpty else { return [] }
        // `.literal`, tedy porovnání znak po znaku: hledá se v kódu, takže se `e` nemá shodovat
        // s `é` (to by dělalo výchozí, jazykově citlivé porovnání). `.caseInsensitive` se s ním
        // kombinovat dá — ověřeno testem, ne přečteno v dokumentaci.
        var options: String.CompareOptions = [.literal]
        if !query.isCaseSensitive { options.insert(.caseInsensitive) }

        var result: [Range<String.Index>] = []
        var from = text.startIndex
        while from < text.endIndex,
              let found = text.range(of: query.text, options: options, range: from..<text.endIndex) {
            result.append(found)
            // Prázdná shoda vzniknout nemá (prázdný dotaz je odfiltrovaný výš), ale kdyby přece,
            // posune se index o znak — jinak by se smyčka zacyklila.
            from = found.upperBound > found.lowerBound ? found.upperBound : text.index(after: found.lowerBound)
        }
        return result
    }

    /// Výskyty v celém diffu, v pořadí, ve kterém jsou na obrazovce.
    ///
    /// - Parameter expansion: co je u souboru rozbalené a jaký má obsah. Closure, ne hodnota:
    ///   drží to store a tady se z toho čte jen to, co k souboru patří — tentýž vzorec jako
    ///   `DiffExpansionActions`.
    static func hits(
        in diff: Diff,
        query: DiffSearchQuery,
        expansion: (FileDiff) -> FileExpansion
    ) -> [DiffSearchHit] {
        guard query.isActive else { return [] }
        return diff.files.flatMap { file in
            let state = expansion(file)
            return hits(in: file, query: query, revealed: state.revealed, content: state.content)
        }
    }

    /// Výskyty v jednom souboru.
    ///
    /// Jde se **přes hotové řádky** (`DiffRow.rows(of:)`), ne přes hunky: rozbalený kontext je
    /// řádek jako každý jiný a pořadí výskytů má být to, v jakém jsou v okně. Sbalený soubor se
    /// tím **počítá** — sbalení je stav okna, ne stav dat, a skok si soubor rozbalí sám.
    ///
    /// Pohled se nepředává schválně: skládá se **vždycky pod sebou**, protože ve split pohledu by
    /// se odebraný a přidaný řádek slily do jedné dvojice a dva výskyty by z toho byly dva
    /// v jednom řádku — tedy jiný počet podle toho, jak je zrovna přepnutý pohled.
    static func hits(
        in file: FileDiff,
        query: DiffSearchQuery,
        revealed: RevealedLines = RevealedLines(),
        content: [String] = []
    ) -> [DiffSearchHit] {
        guard query.isActive else { return [] }
        var result: [DiffSearchHit] = []
        for row in DiffRow.rows(of: file, revealed: revealed, content: content) {
            for line in row.sourceLines {
                let count = ranges(in: line.text, query: query).count
                guard count > 0 else { continue }
                for occurrence in 0..<count {
                    result.append(DiffSearchHit(path: file.displayPath, line: line, occurrence: occurrence))
                }
            }
        }
        return result
    }

    /// Kolik výskytů má který soubor — pro kapsli v jeho hlavičce.
    ///
    /// Klíčem je `displayPath`, tedy to, pod čím soubor v okně vystupuje: hlavička kreslí tuhle
    /// cestu, takže by se s klíčem ze staré cesty přejmenovaného souboru nepotkala.
    static func counts(of hits: [DiffSearchHit]) -> [String: Int] {
        hits.reduce(into: [:]) { counts, hit in counts[hit.path, default: 0] += 1 }
    }
}

extension DiffRow {
    /// Kam v diffu ukazuje výskyt hledání (#152).
    ///
    /// **Vlastní funkce, ne `anchor(in:file:line:)`**, a je to tentýž důvod jako u mého rozdělaného
    /// komentáře: ta porovnává **nové** číslo řádku, kdežto výskyt může ležet na odebraném řádku,
    /// který nové číslo nemá. Hledá se proto nad **hotovými řádky** v tom pohledu, který je zrovna
    /// v okně — ve split pohledu nese dvojice `id` pravého řádku, takže `id` složené odjinud by
    /// v seznamu nebylo a `scrollTo` by tiše neudělalo nic.
    ///
    /// Rozbalený kontext se předává, protože výskyt v něm být může — bez něj by řádek v seznamu
    /// nebyl a skok by skončil u hlavičky souboru.
    static func anchor(
        in diff: Diff,
        hit: DiffSearchHit,
        layout: DiffLayout = .unified,
        revealed: RevealedLines = RevealedLines(),
        content: [String] = []
    ) -> String? {
        guard let file = diff.file(at: hit.path) else { return nil }
        for row in rows(of: file, layout: layout, revealed: revealed, content: content)
        where row.sourceLines.contains(hit.line) {
            return row.id
        }
        // Řádek v seznamu není (přišel nový commit, kontext se mezitím sbalil) — odskočit aspoň
        // na soubor je pořád lepší než nehnout se.
        return file.id
    }
}
