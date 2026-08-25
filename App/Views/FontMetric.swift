import AppKit
import Synchronization

/// Metrika písma — **jedno měření na proces a nikdy zapamatovaná nula** (#407).
///
/// Existuje proto, že se metrika písma v testovacím hostu pod zátěží umí **rozejít mezi dvěma
/// čteními v jednom procesu**, a to tak, že jedno z nich vyjde **nulové**. Změřený projev:
/// `both → 0` proti `treeOnly → 35` v `CommitPanelRoomTests` (víc místa a méně znaků, což
/// z monotónní funkce vyjít nemůže) a výška okýnka logu o **tři řádky** vedle v
/// `LogTailHeightTests` — obojí zeleně, když se sada pustí samostatně, a dvakrát z deseti červeně
/// v plném běhu pod souběžným buildem tří slotů.
///
/// **Léčby byly tři a každá v jiné sadě**: jedno čtení za test (#367), totéž u `DesignPillTests`
/// (#348), jedno čtení na proces s náhradním měřením (#327). Tři léčby jednoho kořene znamenají, že
/// si to musí pamatovat **každá nová sada** — a to je zrovna ten stav, ve kterém čtvrtá zapomene.
/// Odsud si metriku bere aplikace i testy a **žádná sada už o ní vědět nemusí**.
///
/// **Čtení teplého písma to není, a to je změřené**: v samostatném procesu nedal milion čtení z osmi
/// vláken proti churnu ve font cache (tisíce různých velikostí) pod zátěží load 22 ani jednu
/// anomálii, a v testovacím hostu při plném běhu 3,2 milionu čtení šesti cest taky ne
/// (`FontMetricProbe`). Zbývá **rozřešení konkrétního objektu písma** — a to se v testovacím hostu
/// odehraje uprostřed startu aplikace, uplatnění vzhledu a rozjezdu stovek suit.
///
/// **Co ta nula je** (změřeno při #407, na plném běhu v testovacím hostu): je to **přechodně
/// nepoužitelná metrika**, ne zastaralé číslo. `NSFont.monospacedSystemFont(ofSize:weight:)` vrátí
/// instanci, u které `maximumAdvancement.width` nedá použitelnou hodnotu — a sazba **tímtéž**
/// objektem pak spadne uvnitř CoreTextu:
///
/// ```
/// NSInvalidArgumentException: -[__NSPlaceholderDictionary initWithObjects:forKeys:count:]:
///     attempt to insert nil object from objects[0]
///   3 -[NSDictionary initWithDictionary:copyItems:]
///   5 TAttributes::ApplyFont(__CFDictionary const*, __CTFont const*, …)
///   9 CTLineCreateWithAttributedString
///  14 -[NSAttributedString(NSStringDrawing) size]
/// ```
///
/// Zachytilo se to proto, že první podoba téhle třídy měla jako náhradní měření **vysázet `0`** —
/// takže se sazba pustila právě na tom písmu, u kterého hlavní čtení selhalo, a **položila celý
/// běh** (169 testů ze 3 979, zbytek vypsaný jako failing). Z toho plynou dvě věci a obě jsou v kódu
/// níž: nula z metriky **není chybějící číslo, ale vadný objekt**, a **náhradní měření nesmí sázet
/// text** — spadlý proces je horší než červený test.
///
/// **A hlavně je ta vada přechodná** — to je druhé měření, ze kterého vychází zdejší opakování.
/// V osmém z deseti plných běhů pod zátěží spadlo `CommitPanelRoomTests` na `šířka znaku: 0`
/// a `tally` u té zprávy řekl proč:
///
/// ```
/// šířka znaku: 8.0361328125, měření 2, náhradní cesta 0×, nepovedlo se 1×, zamítnuto 0.0
/// ```
///
/// Čte se to takhle: **první měření vrátilo nulu na všech třech cestách** (`nepovedlo se 1×`,
/// `zamítnuto 0.0` — tedy nula, ne `NaN`), nezapamatovalo se, a **totéž písmo o zlomek sekundy
/// později** (při skládání té chybové zprávy) dalo správných **8,0361328125** (`měření 2`). Vada
/// tedy netrvá: nepomůže jiná cesta, pomůže **zkusit to znovu o chvíli později** — proto se řetěz
/// cest opakuje s milisekundovou odmlkou, viz `attempts`.
///
/// **Tři cesty, žádná z nich sazbou:**
///
/// | Cesta | `characterWidth` | `lineHeight` | `boundingHeight` |
/// |---|---|---|---|
/// | `measured` | `maximumAdvancement.width` | `defaultLineHeight(for:)` | `boundingRectForFont.height` |
/// | `fresh` | totéž, ale na písmu **postaveném znovu z deskriptoru** | | |
/// | `derived` | šířka obalového rámce | `ascender − descender + leading` | `ascender − descender` |
///
/// **`fresh` je druhá v řadě schválně** — je to odpověď zrovna na tu příčinu, která se naměřila:
/// vadný je *objekt*, takže se má zkusit jiný. Na písmu s nulovou maticí to je změřené
/// (`FontMetricTests`): `maximumAdvancement` 0,0, čerstvé písmo z téhož deskriptoru 0,618.
///
/// **`derived` je poslední a není to totéž číslo**, je to použitelná mez — zapsané měření, ne naděje:
///
/// - **šířka znaku**: obalový rámec je **horní** mez (11,63 proti 8,04 na mono 13; 9,39 proti 6,49
///   na mono 10,5), tedy širší znak a méně znaků na řádek — chyba na tu stranu, na kterou se chybovat
///   má. `characterWidth` se přitom **ptá jedině na mono**; u proporcionálního písma je ta otázka bez
///   smyslu (`maximumAdvancement` je tam nejširší glyf, 27,4 na systémových 11);
/// - **výška řádku**: na bod (16,0 proti 15,31 na mono 13, 12,0 proti 12,37 na mono 10,5) —
///   `defaultLineHeight` tu sumu ještě zaokrouhluje;
/// - **obalový rámec**: **dolní** mez (19,86 proti 15,31 na mono 13), protože inkoust přečnívá nad
///   ascender i pod descender.
///
/// Plyne z toho jedna věc, která má být vidět: **když se dojde až na `derived`, tvrzení o přesných
/// číslech mohou spadnout** (typicky `LogTailHeightTests.capIsAWholeNumberOfLines` o celém počtu
/// řádků). To je správně — něco s písmem doopravdy je, a v `tally` u zprávy stojí `náhradní cesta 1×`.
///
/// **Nezdařené měření se nepamatuje**, takže se z něj nedá stát stav procesu: příští volání měří
/// znovu. Zapamatovat nulu by bylo horší než ji vrátit jednou, protože `SelectableCodeView`
/// i `DiffToolbar` si šířku znaku drží jako `static let`, tedy **navždycky**.
final class FontMetric: Sendable {
    /// Měřidlo, které používá aplikace i testy. Sdílené schválně — v tom je celá pointa: `mono 13`
    /// je tentýž font v liště diffu, v bloku kódu i v sheetu.
    static let shared = FontMetric()

    /// Kolik hodnot si měřidlo nejvýš pamatuje. Aplikace měří **jednotky** písem (mono 13 na kód,
    /// mono 10,5 na log a kapsli, 11 na pásek s čísly), takže 64 je s rezervou i pro velikosti,
    /// o které si řeknou testy a sondy. Při překročení se zahodí **celá** sada — je to O(1) a stojí
    /// jedno přeměření, tedy tatáž úvaha jako u `SyntaxRunCache`.
    let capacity: Int

    init(capacity: Int = 64) {
        self.capacity = capacity
    }

    /// Šířka jednoho znaku písma, kterým se sází kód. Mono má všechny znaky stejně široké, takže
    /// stačí změřit jeden.
    func characterWidth(of font: NSFont) -> CGFloat {
        value(.characterWidth, of: font)
    }

    /// Výška jednoho řádku sazby v tom písmu, kterým se kreslí (#236).
    func lineHeight(of font: NSFont) -> CGFloat {
        value(.lineHeight, of: font)
    }

    /// Výška obalového rámce písma — tedy inkoust, ne řádek sazby. Kreslí se z ní pásek s čísly
    /// řádků v diffu.
    func boundingHeight(of font: NSFont) -> CGFloat {
        value(.boundingHeight, of: font)
    }

    /// Kolik měření měřidlo udělalo, kolikrát musela pomoct náhradní cesta a kolikrát nepomohla ani
    /// ta. **Čte to `FontMetricTests` a `FontMetricProbe`** a od #407 je to i ve zprávě u tvrzení,
    /// která na metrice stojí: bez toho počtu se „měří se jednou za proces“ nedá tvrdit testem
    /// a „šířka znaku: 0“ zůstane příznakem bez příčiny, jak to u #327 vypadalo.
    var tally: Tally {
        storage.withLock { $0.tally }
    }

    /// Kolik hodnot je zapamatovaných. Čte to test meze — v aplikaci se na to nikdo neptá.
    var remembered: Int {
        storage.withLock { $0.values.count }
    }

    /// Počty měření. `Equatable` schválně: test o „jednom měření na proces“ porovnává dva odečty.
    ///
    /// `firstRejected` je **ta nepoužitelná hodnota, kvůli které se šlo dál** — první za běh. Bez ní
    /// zůstane „šířka znaku: 0“ příznakem bez příčiny a u #327 to tak doopravdy vypadalo: nevědělo se,
    /// jestli metrika vrátila nulu, nebo `NaN`. Je to jedno číslo, ne záznam, protože rozhoduje ten
    /// první — po něm už měřidlo drží zapamatovanou hodnotu.
    struct Tally: Sendable, Equatable, CustomStringConvertible {
        var measurements = 0
        var retries = 0
        var fallbacks = 0
        var failures = 0
        var firstRejected: CGFloat?

        var description: String {
            let base = """
                měření \(measurements), opakování \(retries)×, náhradní cesta \(fallbacks)×, \
                nepovedlo se \(failures)×
                """
            guard let firstRejected else { return base }
            return base + ", zamítnuto \(firstRejected)"
        }
    }

    // MARK: - Měření

    private func value(_ kind: Kind, of font: NSFont) -> CGFloat {
        let key = Key(name: font.fontName, size: font.pointSize, kind: kind)
        // Měří se **pod zámkem**, ne vedle něj: dvě vlákna, která minou zapamatovanou hodnotu
        // naráz, by změřila dvakrát — a „jedno měření na proces“ je zrovna to, co se má držet.
        // Zámek je držený mikrosekundy a nic uvnitř se na `FontMetric` nevolá zpátky.
        return storage.withLock { store in
            if let remembered = store.values[key] { return remembered }

            let measurement = Self.measure(kind, of: font)
            store.tally.measurements += 1
            store.tally.retries += measurement.attempts - 1
            if store.tally.firstRejected == nil { store.tally.firstRejected = measurement.rejected }
            guard let value = measurement.value else {
                store.tally.failures += 1
                return 0
            }
            if measurement.route != .measured { store.tally.fallbacks += 1 }
            // Mez se počítá **včetně toho, co se právě vkládá**, aby se přes ni sada nedostala ani
            // na jeden zápis — tatáž úvaha jako u `SyntaxRunCache`.
            if store.values.count + 1 > capacity { store.values.removeAll() }
            store.values[key] = value
            return value
        }
    }

    /// Kolikrát se celý řetěz cest zkusí, než měřidlo prohlásí, že to nešlo — a **odmlka mezi
    /// pokusy**.
    ///
    /// **Je to naměřené, ne pojistka pro klid duše** (#407, běh 8 z deseti): u mono 13 vyšly
    /// v jednom okamžiku **všechny tři cesty nulové** — i ta, která staví písmo znovu z deskriptoru
    /// — a **totéž písmo dalo o zlomek sekundy později 8,0361328125**. Vada je tedy **přechodná**,
    /// takže jeden průchod řetězem nestačí a *žádná* jiná cesta v tom okamžiku nepomůže: pomůže
    /// jedině zkusit to znovu **o chvíli později**.
    ///
    /// Bez odmlky by to byl tentýž stav přečtený čtyřikrát (celý řetěz je pár mikrosekund), takže
    /// milisekunda je to nejkratší, co má smysl. Cena je **nejvýš 3 ms jednou za písmo a proces**,
    /// a jedině tehdy, když měření selhává — v normálním běhu se čeká nula.
    static let attempts = 4
    static let pauseBetweenAttempts = 0.001

    private static func measure(_ kind: Kind, of font: NSFont) -> Measurement {
        var rejected: CGFloat?
        for attempt in 0..<attempts {
            if attempt > 0 { Thread.sleep(forTimeInterval: pauseBetweenAttempts) }
            for route in Route.allCases {
                guard let read = route.read(kind, of: font) else { continue }
                if let usable = Policy.usableFontMetric(read) {
                    return Measurement(value: usable, route: route, rejected: rejected, attempts: attempt + 1)
                }
                if rejected == nil { rejected = read }
            }
        }
        return Measurement(value: nil, route: nil, rejected: rejected, attempts: attempts)
    }

    private struct Measurement {
        let value: CGFloat?
        let route: Route?
        /// První nepoužitelná hodnota, kvůli které se šlo na další cestu — jde do `Tally`.
        let rejected: CGFloat?
        /// Kolikátý průchod řetězem to dal (nebo kolik jich bylo, když nedal žádný).
        let attempts: Int
    }

    /// Klíč je `(jméno písma, velikost, druh metriky)`. Jméno v něm nese i řez — mono regular je
    /// `.AppleSystemUIFontMonospaced-Regular`, semibold jiné jméno —, takže se dvě různá písma
    /// nemají jak potkat. Písma, která se liší **jen transformační maticí**, by se v klíči slila;
    /// aplikace žádné takové nestaví (v `App/` není jediné `NSFontDescriptor` s `.matrix`), a kdyby
    /// je postavila, byl by ten rozdíl vidět na kresbě.
    ///
    /// **`NaN` ve velikosti sadu nenafoukne**, i když se nerovná sám sobě: zapisuje se **jen povedené
    /// měření**, a písmo s `NaN` velikostí nedá použitelnou hodnotu na žádné cestě (naměřeno), takže
    /// se do sady nedostane vůbec. A i kdyby, drží to mez o dvacet řádků výš.
    private struct Key: Hashable, Sendable {
        let name: String
        let size: Double
        let kind: Kind
    }

    /// **Není `private` schválně**: cesty si porovnává `FontMetricTests`, a to je jediný způsob, jak
    /// se o náhradní cestě dá tvrdit, že vydá použitelné číslo. Cesta, kterou nikdo nezkusil, je
    /// cesta, která nefunguje — a tady se navíc projeví jedině tehdy, když se to hlavní měření
    /// nepovede, tedy nikdy během běžného běhu.
    enum Kind: Hashable, Sendable {
        case characterWidth
        case lineHeight
        case boundingHeight
    }

    /// **Pořadí je součást opravy, ne kosmetika**: `fresh` je druhá, protože vadný je ten objekt
    /// písma, a `derived` poslední, protože její čísla jsou jen meze. `CaseIterable` drží to pořadí
    /// z deklarace, takže se mění právě tady.
    enum Route: Sendable, CaseIterable {
        case measured
        case fresh
        case derived

        func read(_ kind: Kind, of font: NSFont) -> CGFloat? {
            switch self {
            case .measured:
                Self.direct(kind, of: font)
            case .fresh:
                NSFont(descriptor: font.fontDescriptor, size: font.pointSize)
                    .map { Self.direct(kind, of: $0) }
            case .derived:
                Self.derived(kind, of: font)
            }
        }

        private static func direct(_ kind: Kind, of font: NSFont) -> CGFloat {
            switch kind {
            case .characterWidth: font.maximumAdvancement.width
            case .lineHeight: NSLayoutManager().defaultLineHeight(for: font)
            case .boundingHeight: font.boundingRectForFont.height
            }
        }

        /// **Nesází text, a je to podmínka téhle třídy** (#407): sazba písmem, u kterého selhalo
        /// přímé čtení metriky, spadne uvnitř CoreTextu a položí celý proces — změřeno, výpis
        /// výjimky je v hlavičce souboru. Poslední cesta se proto ptá jedině na čísla, která má
        /// `NSFont` sám u sebe.
        private static func derived(_ kind: Kind, of font: NSFont) -> CGFloat {
            switch kind {
            case .characterWidth:
                font.boundingRectForFont.width
            case .lineHeight:
                font.ascender - font.descender + font.leading
            case .boundingHeight:
                font.ascender - font.descender
            }
        }
    }

    private struct Storage: Sendable {
        var values: [Key: CGFloat] = [:]
        var tally = Tally()
    }

    private let storage = Mutex(Storage())
}
