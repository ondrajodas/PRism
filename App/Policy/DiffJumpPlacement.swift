import Foundation

/// Co je cílem skoku v diffu (#152). Rozhoduje o tom, **kolik místa nad cílem zůstane**.
///
/// Dva případy, ne jeden, a je to rozdíl v tom, co ten cíl je — ne v tom, odkud se na něj kliklo.
enum DiffJumpTarget: Equatable, Sendable {
    /// Nález, moje rozdělaná poznámka, soubor ze stromu. Co je pro ně společné: **kontext si nesou
    /// s sebou** a visí **pod** svým řádkem, takže se pod cílem musí vejít bublina.
    case bubble
    /// Výskyt hledání. Kontext má jedině v kódu okolo, a hlavně v tom **nad** ním: bez něj se z něj
    /// nepozná, ve které funkci vlastně je.
    case searchHit
}

extension Policy {
    /// Kolik bodů nad cílem skoku má zůstat vidět. `nil` = výška výřezu ještě není známá, takže se
    /// nedá počítat nic — volající si vezme střed, jedinou hodnotu, která na neznámé výšce nezávisí.
    ///
    /// **Skáče se vždycky, i na cíl, který je zrovna vidět** (#152, připomínka z proklikání
    /// u hledání). Procházení výskytů je `⏎ ⏎ ⏎`: když každý výskyt přistane ve stejné výšce, oko
    /// se nehýbe a čte se zvýrazněné slovo. Kdyby se pohled přerovnával jen tehdy, když cíl mimo
    /// výřez je, poskakoval by výskyt po celé obrazovce a musel by se hledat očima — tedy zrovna
    /// to, kvůli čemu se skáče. Text pod okem se tím sice posune i tehdy, když posun nutný nebyl,
    /// ale to je slabší cena: kdo hledá, kouká na výskyt, ne na kód pod ním.
    ///
    /// **Přesný střed ne** — u kódu se čte dolů, takže polovina obrazovky nad cílem je zbytečná
    /// (změřeno na běžící aplikaci u #72, kde se z půlky slevilo). Půlka je proto **strop**, ne
    /// hodnota: v nízkém okně je „třetina shora“ i „devadesát bodů“ nesplnitelné a střed je pak to
    /// nejlepší, co jde udělat.
    static func jumpOffset(of target: DiffJumpTarget, viewport: Double) -> Double? {
        guard viewport > 0 else { return nil }
        let wanted = switch target {
        case .bubble: bubbleContextAbove
        // **Třetina shora, ne devadesát bodů jako u bubliny.** Nález pod sebou nese bublinu s celým
        // textem, takže si o místo pod řádkem říká sám; výskyt hledání je jen místo v kódu a to,
        // co je nad ním, je polovina odpovědi na „kde to je“.
        case .searchHit: max(viewport / 3, bubbleContextAbove)
        }
        return min(wanted, viewport / 2)
    }

    /// Ukotvená hlavička souboru (~30 pt) a tři řádky diffu (~22 pt na řádek). Vyladěné na běžící
    /// aplikaci u #72: s pěti řádky (140 pt) působil odskok zbytečně velký.
    static let bubbleContextAbove = 90.0

    /// Podíl výšky pro `scrollTo(anchor:)` tak, aby v požadované výšce skončil **cílový řádek**, ne
    /// blok, ve kterém leží (#152). `nil` = výška výřezu není známá, volající si vezme střed.
    ///
    /// **Tohle je ta oprava míjení.** `scrollTo(id, anchor:)` srovná bod na podílu `a` výšky **cíle**
    /// s bodem na podílu `a` výšky výřezu, takže pro cíl vysoký `bh` platí
    ///
    /// ```
    /// horní hrana cíle pod hranou výřezu = a × (výřez − bh)
    /// ```
    ///
    /// Cílem je od #157 **blok** o nejvýš šedesáti řádcích (`DiffBlock.maxLines`), tedy až ~1 000 pt.
    /// S pevným podílem (`offset ÷ výřez`) se tím pádem umisťoval blok a řádek v něm ležel, kde
    /// ležel: **naměřeno v okně 1 200 × 800 (výřez 762 pt), že řádek 52 skončil 889 pt pod hranou
    /// výřezu a řádek 195 dokonce 2 181 pt** — vidět byly první čtyři desítky řádků z dvou set.
    /// Odsud se proto podíl **dopočítá** z toho, kolik řádků bloku je nad cílem:
    ///
    /// ```
    /// a = (offset − řádky nad cílem × výška řádku) ÷ (výřez − výška bloku)
    /// ```
    ///
    /// Tři věci, které z toho plynou a nejsou vidět na první pohled:
    ///
    /// - **Podíl mimo `0…1` se vrací schválně a `scrollTo` ho zvládne** — vzorec je lineární
    ///   extrapolace, ne interpolace uvnitř cíle, a u bloku vyššího než výřez je hodnota mimo rozsah
    ///   ta jediná správná. **Ověřeno měřením, ne dokumentací** (#152): s ořezáním na `0…1` skončil
    ///   řádek na kraji bloku vyššího než výřez mimo obrazovku (844 pt pod hranou) a u podílu přesně
    ///   `0` se okno **nepohnulo vůbec**; bez ořezání sedí posun na dva body (`51 + 208 − 169 = 90`).
    /// - **Výška bloku se počítá z výšky řádku, ne měří.** V pohledu vedle sebe se nezalamuje, takže
    ///   je to přesné; v pohledu pod sebou zalomený řádek výšku podhodnotí a cíl přistane o ten
    ///   přebytek níž. Mez je tím **blok** (nejvýš šedesát řádků), ne diff — a to je celý rozdíl
    ///   proti stavu, kdy se poloha řádku v bloku nepočítala vůbec. Měřit ji nejde: přesnou výšku
    ///   zná jedině nasazený blok (`DiffBlockSlot`) a ten se nasadí teprve po skoku.
    /// - **U kraje dokumentu se posun ořeže sám** (nahoře i dole) a cíl pak leží jinde, než kam se
    ///   mířilo. Není to chyba — dál se odscrollovat nedá.
    ///
    /// **Změna struktury seznamu je zamítnutá varianta, a je to změřené.** První pokus vyjmul cílový
    /// řádek do vlastního bloku (`blocked(_:breakingAt:)`), aby podíl platil přímo pro něj. Nefunguje
    /// to: nové bloky vzniknou v témže průchodu, ve kterém se skáče, takže je `scrollTo` vidí
    /// nerozvržené a posun vyšel **na geometrii těch starých** (naměřeno: posun 75, 1 039 a 2 003 pt,
    /// tedy přesně hrany nerozdělených bloků). Aritmetika je proti tomu na rozvržení nezávislá.
    static func jumpAnchorY(
        of target: DiffJumpTarget,
        viewport: Double,
        row: DiffJumpSpot,
        rowHeight: Double
    ) -> Double? {
        guard let offset = jumpOffset(of: target, viewport: viewport) else { return nil }
        let block = Double(max(row.rows, 1)) * rowHeight + blockInset
        let above = Double(max(row.above, 0)) * rowHeight
        let slack = viewport - block
        // Blok přesně tak vysoký jako výřez: podíl výšky s ním nehýbe (`a × 0`), takže není co
        // počítat a řádek přistane tam, kde v bloku je. Nula je pak jediná poctivá odpověď.
        guard abs(slack) > 0.5 else { return 0 }
        return (offset - above) / slack
    }

    /// Svislý inset bloku kódu — `DiffTextView` ho má na obou stranách, takže se do výšky započítá
    /// dvakrát. Vlastní konstanta, protože `Policy` je bez I/O a na `NSFont` nesahá.
    static let blockInset = 4.0
}
