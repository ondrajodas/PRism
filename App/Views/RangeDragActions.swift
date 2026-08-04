import CoreGraphics

/// Tažení přes řádky diffu, kterým se vybírá rozsah pro komentář (#110).
///
/// Jeden parametr místo tří closures, které patří k sobě — stejný vzor jako `DraftActions`.
struct RangeDragActions {
    /// Rámečky řádků. `nil` = tady se netáhne (náhledy, testy skládání řádků).
    var frames: DiffRowFrames?
    /// Rozsah se hlásí průběžně: `from` je řádek, na kterém tažení začalo, `to` ten pod myší.
    /// Komentář z toho vznikne až na konci — během tažení se jen zvýrazňuje.
    ///
    /// `to == nil` = pod myší **není** řádek, na který se dá komentovat. Co s tím, rozhoduje store:
    /// rozdělaný rozsah se drží, protože přejetí přes prázdné místo není zrušení výběru.
    var move: (_ from: DraftAnchor, _ to: DraftAnchor?) -> Void = { _, _ in }
    var end: () -> Void = {}
}

/// Rámečky řádků diffu v souřadnicích **obsahu** — z nich se pozná, přes který řádek myš táhne.
///
/// Existuje proto, že diff je líný seznam: gesto se doručuje jen tomu řádku, ve kterém začalo,
/// takže řádek pod myší se musí dohledat ze souřadnic. Jiná cesta není.
///
/// **Není `@Observable`, a to je celý trik.** Zapisuje se při každém přeměření řádku; kdyby to
/// bylo sledované, každý pohyb myší i každé rozbalení kontextu by překreslilo celý diff — a to je
/// přesně ta třída problému, která u #98 aplikaci zasekla na 99 % v layoutu. Tady se jen plní
/// slovník, který si přečte gesto.
///
/// Souřadnice jsou vázané na obsah (`LazyVStack`), ne na okno: scrollováním se rámečky nemění,
/// takže se přeměřování nespouští a záznamy nezastarají.
@MainActor final class DiffRowFrames {
    private var entries: [String: (rect: CGRect, anchor: DraftAnchor)] = [:]

    /// Zapíše rámeček řádku. `anchor == nil` (řádek, který komentář neunese) záznam **maže** —
    /// jinak by po rozbalení kontextu zůstal ležet rámeček řádku, na který se komentovat nedá.
    ///
    /// **Zároveň vyhodí všechny záznamy, které se s tím novým překrývají.** Dva živé řádky se
    /// nikdy nepřekrývají, takže překryv znamená, že ten druhý záznam je po přerovnání
    /// **zastaralý** — po přepnutí pohledu (unified řádek jde přes celou šířku, buňka dvojice po
    /// půlce), po sbalení souboru nebo po přepnutí PR. Bez toho padl bod do obou a vyhrál ten, na
    /// který hledání narazilo první; a protože párování řádky slévá, netrefilo se to ani o pár
    /// míst vedle — nahlášené při zkoušení #110 („vybere se i další 2–3 pod kurzorem“).
    ///
    /// Uklízí se to takhle, ne vyprázdněním krabice zvenčí: `onGeometryChange` se spustí **jen
    /// když se geometrie změní**, takže po vyprázdnění by řádky nic nenahlásily a krabice by
    /// zůstala prázdná — tažení pak nemělo co najít a rozsah se nikdy neroztáhl. Zkoušel jsem to
    /// a mělo to přesně tenhle následek.
    func note(_ rect: CGRect, id: String, anchor: DraftAnchor?) {
        guard let anchor else {
            entries[id] = nil
            return
        }
        for (key, entry) in entries where key != id && entry.rect.intersects(rect) {
            entries[key] = nil
        }
        entries[id] = (rect, anchor)
    }

    /// Kotva řádku pod bodem. `nil` = mimo řádky, na které se dá komentovat.
    ///
    /// Hledá se lineárně přes všechny přeměřené řádky, protože jich je řádově tisíc a odpověď
    /// se počítá jen při pohybu myši se stisknutým tlačítkem.
    ///
    /// `side` **omezuje hledání na jeden sloupec** a předává ho split pohled: tažení, které začalo
    /// vpravo, nemá skákat do levého sloupce, jen protože myš zajela vedle nebo protože levá
    /// protistrana chybí (nahlášené při zkoušení #110). V pohledu pod sebou je `nil`, protože tam
    /// je sloupec jediný a rozsah přes odebrané i přidané řádky je legitimní.
    func anchor(at point: CGPoint, on side: DiffSide?) -> DraftAnchor? {
        entries.values
            .first { entry in
                entry.rect.contains(point) && (side == nil || entry.anchor.side == side)
            }?
            .anchor
    }
}
