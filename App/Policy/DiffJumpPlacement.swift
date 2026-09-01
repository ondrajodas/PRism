import Foundation

/// Rozměry cíle skoku, ze kterých se počítá podíl výšky pro `scrollTo(anchor:)` (#152).
///
/// **Dvě čísla, a obě v bodech** — ne počet řádků: jedině tak se dá tatáž funkce nakrmit **změřenou**
/// plochou bloku (`DiffRowFrames`, platí i pro zalomené řádky) i dopočítanou z výšky řádku
/// (`Policy.jumpMetrics`), když se blok ještě nikdy nekreslil.
struct DiffJumpMetrics: Equatable, Sendable {
    /// Kolik bodů bloku je **nad** cílovým řádkem.
    let above: Double
    /// Výška celého bloku.
    let height: Double
}

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
    /// - **Rozměry se přednostně berou změřené** (`DiffRowFrames` — plochu bloku i řádku hlásí bloky
    ///   při kreslení), a dopočítaná varianta z výšky řádku je jen záloha pro blok, který se ještě
    ///   nikdy nekreslil. Není to detail: v pohledu pod sebou se **zalamuje**, takže u souboru
    ///   s dlouhými řádky vyšel odhad 964 pt proti skutečným ~2 900 — a cíl skončil **6 017 pt nad**
    ///   výřezem. Ve split pohledu se nezalamuje, tam odhad sedí.
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
        metrics: DiffJumpMetrics
    ) -> Double? {
        guard let offset = jumpOffset(of: target, viewport: viewport) else { return nil }
        let slack = viewport - metrics.height
        // Blok přesně tak vysoký jako výřez: podíl výšky s ním nehýbe (`a × 0`), takže není co
        // počítat a řádek přistane tam, kde v bloku je. Nula je pak jediná poctivá odpověď.
        guard abs(slack) > 0.5 else { return 0 }
        return (offset - metrics.above) / slack
    }

    /// Rozměry cíle **dopočítané z výšky řádku** — použijí se tam, kde změřené nejsou (blok se ještě
    /// nikdy nekreslil).
    ///
    /// **Je to odhad a v pohledu pod sebou umí být hodně vedle**: tam se zalamuje, takže řádek
    /// o dvou stech znacích je vysoký tři řádky sazby. Změřeno u #152 — u souboru s dlouhými řádky
    /// vyšel odhad bloku 964 pt proti skutečným ~2 900 a cíl skončil až **6 017 pt nad** výřezem,
    /// tedy dávno mimo obrazovku. Proto se **přednostně bere změřená plocha** (`DiffRowFrames`)
    /// a tohle je jen záloha pro první skok do bloku, který se ještě nekreslil.
    static func jumpMetrics(of row: DiffJumpSpot, rowHeight: Double) -> DiffJumpMetrics {
        DiffJumpMetrics(
            above: Double(max(row.above, 0)) * rowHeight,
            height: Double(max(row.rows, 1)) * rowHeight + blockInset
        )
    }

    /// Svislý inset bloku kódu — `DiffTextView` ho má na obou stranách, takže se do výšky započítá
    /// dvakrát. Vlastní konstanta, protože `Policy` je bez I/O a na `NSFont` nesahá.
    static let blockInset = 4.0
}

extension Policy {
    /// Kam posunout sloupec **vodorovně**, aby byl výskyt hledání vidět (#152, druhé kolo
    /// proklikání). `nil` = je vidět, nehýbat.
    ///
    /// **Posouvá se jedině to, co vidět není, a je to rozhodnutí, ne opatrnost.** Vodorovná poloha
    /// je něco, co si člověk nastavil sám (odrolovaný sloupec zůstává odrolovaný, dokud s ním
    /// nehne), takže ji přerovnat u výskytu, který je na obrazovce, je tentýž bezdůvodný poskok,
    /// jaký se u svislé osy zamítal — jen s tím rozdílem, že svisle jde o **pořadí čtení** (výskyt
    /// se má číst pořád ve stejné výšce), kdežto vodorovně o **rozkoukanou polohu v řádku**.
    ///
    /// **Rezerva je dvakrát**: nalevo, aby výskyt neseděl přesně na hraně a bylo vidět, že před ním
    /// něco je, a napravo z téhož důvodu. Když je výskyt delší než výřez, vyhrává jeho **začátek** —
    /// číst se začíná zleva.
    ///
    /// Vrací se **posun plochy** (levá hrana výřezu v souřadnicích dokumentu), ne poloha výskytu:
    /// to je hodnota, kterou bere `NSClipView.scroll(to:)`, takže se po cestě nemá co přepočítat.
    static func horizontalReveal(
        match: ClosedRange<Double>,
        visible: ClosedRange<Double>,
        margin: Double = searchRevealMargin
    ) -> Double? {
        let width = visible.upperBound - visible.lowerBound
        guard width > 0 else { return nil }
        // Vejde se celý i s rezervou? Pak se nehýbe.
        if match.lowerBound >= visible.lowerBound + margin, match.upperBound <= visible.upperBound - margin {
            return nil
        }
        // Delší než výřez, nebo začíná nalevo od něj: zarovná se jeho začátek.
        if match.upperBound - match.lowerBound > width - 2 * margin || match.lowerBound < visible.lowerBound + margin {
            return max(match.lowerBound - margin, 0)
        }
        // Přetéká doprava: doskočí se tak, aby byl i s rezervou u pravé hrany.
        return max(match.upperBound + margin - width, 0)
    }

    /// Kolik místa zůstane před výskytem a za ním, když se sloupec posune. Zhruba dva znaky
    /// monospace písma — dost na to, aby bylo vidět, že výskyt na hraně nekončí.
    static let searchRevealMargin = 24.0
}
