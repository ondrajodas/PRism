import CoreGraphics

/// Tažení přes řádky diffu, kterým se vybírá rozsah pro komentář (#110).
///
/// Jeden parametr místo tří closures, které patří k sobě — stejný vzor jako `DraftActions`.
struct RangeDragActions {
    /// Krabice rámečků a diff, do kterého se hlásí. `nil` = tady se netáhne (náhledy, testy
    /// skládání řádků).
    var box: FrameBox?

    /// **Krabice a klíč diffu jsou jedna hodnota schválně** (#274). Krabice, která klíč nedostane,
    /// tiše přestane zahazovat plochy z jiných záložek — tedy přesně ta regrese, kterou #274
    /// opravuje, a potichu. Jedno bez druhého se proto nedá předat ani omylem; volitelné pole
    /// s výchozím prázdným klíčem by se zapomenout dalo (nález Copilota na #349).
    struct FrameBox {
        let frames: DiffRowFrames
        /// Co se kreslí — pull request (`owner/repo#číslo`), nebo commit v tabu `Commity`.
        let subject: String
    }
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
    private var entries: [String: (rect: CGRect, anchor: DraftAnchor?)] = [:]
    /// Plochy **celých bloků**, klíčované jejich `id`. Hlásí je tentýž zápis jako řádky (je to jeho
    /// parametr `covering`), jen se dosud zahazovaly.
    ///
    /// Čte to **skok** (#152): podíl výšky, kterým `scrollTo(anchor:)` cíl umisťuje, platí pro blok,
    /// takže se bez jeho **skutečné** výšky nedá spočítat, kam přistane řádek v něm. Dopočítat ji
    /// z počtu řádků nejde — v pohledu pod sebou se **zalamuje**, takže je blok o dlouhých řádcích
    /// klidně trojnásobný (změřeno u #152: odhad 964 pt proti skutečným ~2 900 a cíl skončil až
    /// 6 017 pt **nad** výřezem).
    private var blocks: [String: CGRect] = [:]
    /// Který diff krabice popisuje. `nil` = zatím žádný.
    ///
    /// Je tu proto, že `@State` detailu **přetéká mezi pull requesty**: jeden `DiffView` obslouží
    /// všechny otevřené záložky, takže bez tohohle by se v krabici vrstvily plochy každého PR,
    /// na který se člověk podíval — vyklizení plochy (`note`) zastaralé záznamy sundá jedině tam,
    /// kam nový blok doopravdy dosáhl. Úklid je lineární v počtu záznamů, takže každá další
    /// prohlédnutá záložka zdražovala zápis (#274).
    private var subject: String?

    /// Jeden zapsaný rámeček.
    ///
    /// **`anchor` je volitelná od #152**: plochy se hlásí za **každý** řádek bloku, protože z nich
    /// počítá i skok, kdežto tažení rozsahu se týká jen řádků, na které se dá komentovat. Řádek bez
    /// kotvy je tedy „vím, kde leží, ale táhnout přes něj nejde“ — a `anchor(at:on:)` ho přeskočí.
    struct Entry {
        let id: String
        let rect: CGRect
        let anchor: DraftAnchor?
    }

    /// Zapíše rámečky **celého bloku naráz** a vyklidí jeho plochu od všeho ostatního.
    ///
    /// **Po blocích, ne po řádcích** (#252). Úklid je lineární v počtu záznamů, takže po řádcích
    /// to bylo kvadratické: šedesátiřádkový blok ve split pohledu má 120 ploch a v krabici leží
    /// řádově tisíce záznamů, tedy stovky tisíc porovnání na jeden blok, který se objeví ve
    /// viditelném okně. Naráz je to jeden průchod na blok.
    ///
    /// **Vyklizení plochy je to, co drží záznamy aktuální.** Dva živé řádky se nikdy nepřekrývají,
    /// takže záznam v ploše bloku, který blok sám nehlásí, je po přerovnání **zastaralý** — po
    /// přepnutí pohledu (unified řádek jde přes celou šířku, buňka dvojice po půlce), po sbalení
    /// souboru, po rozbalení kontextu nebo po přepnutí PR. Bez toho padl bod do obou a vyhrál ten,
    /// na který hledání narazilo první; a protože párování řádky slévá, netrefilo se to ani o pár
    /// míst vedle — nahlášené při zkoušení #110 („vybere se i další 2–3 pod kurzorem“).
    ///
    /// Uklízí se to takhle, ne vyprázdněním krabice zvenčí: hlásí se **jen při změně** geometrie,
    /// takže po vyprázdnění by bloky nic nenahlásily a krabice by zůstala prázdná — tažení pak
    /// nemělo co najít a rozsah se nikdy neroztáhl. Zkoušel jsem to a mělo to přesně tenhle
    /// následek.
    ///
    /// Prázdná plocha se ignoruje: rámeček bloku, který se ještě nerozložil, je nulový a vyklidil
    /// by cizí záznamy na souřadnici nula.
    ///
    /// **Uklízí se před zápisem**, ne po něm — jinak by blok vyklidil sám sebe (leží celý ve své
    /// ploše) a zbyl by z něj poslední řádek. Vynechání vlastních `id` z úklidu je proti tomu jen
    /// úspora práce na horké cestě: blok se hlásí znovu při každém posunu, takže nemá smysl
    /// stopadesát záznamů mazat a hned vracet.
    ///
    /// **Plochy z jiného diffu se zahodí naráz** (#274), a to ve chvíli, kdy přijde první hlášení
    /// z toho nového — tedy z **hlášení**, ne zvenčí. Na tom to celé stojí: vyprázdnit krabici
    /// zvenčí by znamenalo, že bloky, které stojí a geometrii nemění, už nic nenahlásí a tažení
    /// nemá co najít (viz odstavec výš). Tímhle způsobem je v krabici vždycky nejvýš jeden diff,
    /// takže zápis stojí totéž s jednou otevřenou záložkou jako se čtyřmi.
    func note(_ rows: [Entry], covering area: CGRect, of subject: String, block: String? = nil) {
        guard !area.isEmpty else { return }
        if subject != self.subject {
            // `keepingCapacity`, protože přihrádky za chvíli zaplní tentýž počet ploch nového
            // diffu — je to tatáž úvaha jako u `SyntaxRunCache.clear()`.
            entries.removeAll(keepingCapacity: true)
            blocks.removeAll(keepingCapacity: true)
            self.subject = subject
        }
        if let block { blocks[block] = area }
        let live = Set(rows.map(\.id))
        for (key, entry) in entries where !live.contains(key) && entry.rect.intersects(area) {
            entries[key] = nil
        }
        for row in rows { entries[row.id] = (row.rect, row.anchor) }
    }

    /// Kolik ploch v krabici leží. Čte to **jen test a měření** — tažení se ptá na kotvu, ne na
    /// počet; je to tatáž výjimka jako `SyntaxRunCache.count`.
    var count: Int { entries.count }

    /// Plocha jednoho řádku v souřadnicích obsahu. `nil` = ten řádek se ještě nehlásil, nebo se
    /// hlásit nemůže (komentovat se dá jen řádek v hunku).
    ///
    /// Čte to **skok** (#152), a jedině při skoku — tedy jednou za kliknutí, ne z těla view.
    func rect(of id: String) -> CGRect? { entries[id]?.rect }

    /// Plocha celého bloku v souřadnicích obsahu. `nil` = blok se ještě nikdy nekreslil.
    ///
    /// **Plocha bloku a plochy jeho řádků jsou vždycky z téhož hlášení** (píše je jeden zápis), takže
    /// i kdyby záznam zastaral posunem obsahu, **rozdíl mezi nimi** — tedy to, co skok potřebuje —
    /// zůstává platný.
    func block(_ id: String) -> CGRect? { blocks[id] }

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
            .lazy
            .compactMap { entry -> DraftAnchor? in
                // Řádek bez kotvy je v krabici kvůli skoku (#152), ne kvůli tažení — přes ten se
                // rozsah táhnout nedá, takže se přeskočí.
                guard let anchor = entry.anchor, entry.rect.contains(point) else { return nil }
                return side == nil || anchor.side == side ? anchor : nil
            }
            .first
    }
}
