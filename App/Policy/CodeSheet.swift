import CoreGraphics
import Foundation

/// Jak velký je sheet s kódem: podlaha a velikost, se kterou se otevře (#417).
///
/// Dvě hodnoty spolu, ne dvě funkce: podlaha je ta velikost, kterou sheet **doopravdy dostane**,
/// když se ideál pokazí (viz `Policy.codeSheetSizing`), takže se o nich rozhoduje naráz.
struct CodeSheetSizing: Equatable, Sendable {
    /// `minWidth`/`minHeight` rámce — a tedy `contentMinSize` okna sheetu, takže je ta mez vidět
    /// rukou, ne jen v kódu.
    let floor: CGSize
    /// S čím se sheet otevře, dokud si uživatel nenatáhl vlastní velikost.
    let ideal: CGSize
}

/// Kolik řádků textu se na šířku nevešlo (#417) — patička sheetu s hunkem.
struct CodeSheetOverflow: Equatable, Sendable {
    /// Kolik logických řádků je delších, než co se vejde na jeden řádek sazby.
    let wrapped: Int
    /// Kolik řádků text má celkem.
    let total: Int
}

extension Policy {
    // MARK: - Velikost sheetu s kódem (#417)

    /// Podlaha sheetu s hunkem: velikost, ve které je **mediánový hunk celý**.
    ///
    /// Deset řádků do patnácti, mediánový řádek 38 znaků do šestašedesáti (změřeno na 128 hunkech
    /// z pěti PR, sekce 28 návrhu). Není to nejmenší číslo, které projde: **podlaha je přesně to, co
    /// sheet dostane, když se ideál pokazí**, a #417 je toho dokladem — bez
    /// `presentationSizing(.fitted)` se `idealWidth` zahodí a zbyde `minWidth`.
    static let codeSheetHunkFloor = CGSize(width: 560, height: 320)

    /// S čím se otevře hunk. Kritérium bylo **devět hunků z deseti bez jediného zalomení**: při
    /// 1 180 bodech (143 znaků) to platí u 91 % ze 128 měřených hunků.
    ///
    /// **Netáhne se k 1 600**, kde by bez zalomení byly všechny: mediánový řádek hunku má 38 znaků,
    /// tedy 305 bodů, takže by to byl sheet z devíti desetin prázdný — a sheet je modální okno nad
    /// diffem, ze kterého se právě čte, takže se šířka platí tím, co zakryje. Výška 520 = 27 řádků
    /// = 88 % hunků bez rolování (ze 420 na 520 je to +5 pb, nad 520 už jen +1 pb na sto bodů).
    static let codeSheetHunkIdeal = CGSize(width: 1_180, height: 520)

    /// Podlaha sheetu s logem: **820 je šířka, na kterou se sheet otevíral do #292**, takže pod ni
    /// by to byla regrese — v číslech 98 znaků na řádek, z nich 69 na obsah po timestampu. Výška 420
    /// je tolik jako u přepisu session a je to důvod, ne shoda: obojí je dlouhý výpis, kterým se
    /// roluje, takže obojí potřebuje aspoň těch 21 řádků naráz.
    static let codeSheetLogFloor = CGSize(width: 820, height: 420)

    /// Výška, se kterou se otevře log. `visibleFrame` téhle obrazovky je 883 bodů, takže po okrajích
    /// je 760 zhruba všechno, co jde. Že je to tolik jako u přepisu session, není souměrnost —
    /// rozhoduje tentýž displej.
    static let codeSheetLogIdealHeight: CGFloat = 760

    /// Kolik zůstane kolem sheetu na obrazovce (dohromady, ne na stranu), když se **uplatňuje
    /// uložená** velikost.
    ///
    /// Není to `codeSheetMargin` (152), kterým se řídí *ideální* šířka logu, a je to schválně: tohle
    /// je tvrdý ořez „vejde se to na displej“, kdežto 152 je pohodlí. Na 1512 × 883 by ořez o 152
    /// srazil i nakreslenou výšku logu (883 − 152 = 731 proti 760).
    ///
    /// Ořezává se, protože se velikost **natáhne na jedné obrazovce a otevírá na druhé**: 3 000 bodů
    /// z ultrawide monitoru by na notebooku byl sheet přes celou plochu a přes hrany. AppKit sám
    /// clampuje jen **výšku** (změřeno u #327: 1 040 požadovaných → 917 daných), šířku nechá přetéct.
    static let codeSheetScreenMargin: CGFloat = 120

    /// Poslední mez, kdyby obrazovka nebyla známá — **pojistka proti nesmyslu v `UserDefaults`**
    /// (soubor se dá editovat rukou), ne návrhové rozhodnutí. Skutečný strop je obrazovka. Tatáž
    /// úvaha i tatáž hodnota jako u `rawSessionSheetCap`.
    static let codeSheetCap = CGSize(width: 6_000, height: 4_000)

    /// Podlaha a ideální velikost podle druhu obsahu — **jedna čistá funkce pro oba profily**.
    ///
    /// **Dva profily, jeden sheet** (sekce 28 návrhu): u hunku se hledá šířka, ve které se kód
    /// nezalamuje, u logu **žádná šířka nestačí** (p99 řádku 333 znaků, jeden měl 732 087), takže se
    /// bere, co obrazovka pohodlně dovolí — `codeSheetWidth`, tedy obrazovka bez 152 bodů, nejvýš
    /// 2 700. Zlom je změřený: do 1 360 bodů stojí každých sto bodů 5,8 až 7,3 procentního bodu
    /// zalomených řádků, nad ním 2,2 a méně.
    ///
    /// Ideál se ořezává o obrazovku, aby se sheet vešel i na malý displej; podlaha nikdy — sheet,
    /// který je menší než jeho `contentMinSize`, neexistuje.
    static func codeSheetSizing(kind: CodeText.Kind, screen: CGSize?) -> CodeSheetSizing {
        let bounds = codeSheetBounds(kind: kind, screen: screen)
        let ideal = switch kind {
        case .hunk: codeSheetHunkIdeal
        case .log: CGSize(width: codeSheetWidth(screenWidth: screen?.width), height: codeSheetLogIdealHeight)
        }
        let floor = codeSheetFloor(kind: kind)
        return CodeSheetSizing(
            floor: floor,
            ideal: CGSize(
                // **Nikdy pod podlahu**, a není to jen pro pořádek: `idealWidth` menší než `minWidth`
                // by SwiftUI přebilo podlahou, takže by se v rámci sešly dvě různé odpovědi na
                // jednu otázku. Nastane to u logu na malinké obrazovce — `codeSheetWidth` tam
                // rozhoduje podle displeje a spadne pod 820.
                width: min(max(ideal.width, floor.width), bounds.width),
                height: min(max(ideal.height, floor.height), bounds.height)
            )
        )
    }

    /// S jakou velikostí se sheet otevře: **uloženou, když je použitelná, jinak ideální**.
    ///
    /// Nula znamená „nic uloženého“, ne nulový sheet — `@AppStorage` bez zapsané hodnoty vrací právě
    /// ji, a odlišit „neuloženo“ od „uloženo“ je potřeba k tomu, aby výchozí velikost mohla dál
    /// vycházet z obrazovky.
    ///
    /// Ořez je **při použití, ne při zápisu** (tatáž úvaha jako u přepisu session): v `UserDefaults`
    /// může být cokoli — ruční editace, hodnota z jiného monitoru, jiný rozsah ze starší verze —
    /// a `frame(idealWidth:)` se zápornou hodnotou rozhodí celé okno.
    static func codeSheetSize(
        kind: CodeText.Kind,
        storedWidth: Double,
        storedHeight: Double,
        screen: CGSize?
    ) -> CGSize {
        let sizing = codeSheetSizing(kind: kind, screen: screen)
        guard storedWidth.isFinite, storedHeight.isFinite, storedWidth > 0, storedHeight > 0 else {
            return sizing.ideal
        }
        let bounds = codeSheetBounds(kind: kind, screen: screen)
        return CGSize(
            width: min(max(storedWidth, sizing.floor.width), bounds.width),
            height: min(max(storedHeight, sizing.floor.height), bounds.height)
        )
    }

    /// Má se uložená velikost přepsat naměřenou? `nil` = **nezapisovat**.
    ///
    /// Je to tentýž tvar jako `Policy.hoverChange(from:to:)` a ze stejného důvodu: rozhodnutí „tohle
    /// je změna, kterou stojí za to zapsat“ patří na jedno místo, kde se dá vyčerpat výčtem.
    ///
    /// Porovnává se s tím, **s čím se sheet otevřel**, ne s uloženou hodnotou: velikost, o kterou si
    /// aplikace řekla sama, není volba uživatele, takže se neukládá — jinak by se nula („nic
    /// uloženého“) při prvním otevření přepsala na konkrétní číslo a výchozí velikost by přestala
    /// vycházet z obrazovky.
    ///
    /// **Mezistav rozvržení tahle funkce nepozná, a nemá ho poznat**: sheet se rozvrhuje dvakrát
    /// a v prvním průchodu hlásí **podlahu**. Podlaha je přitom legitimní velikost — kdo si sheet
    /// stáhne až na ni, má ji mít zapamatovanou —, takže ji nelze zamítnout tady. Zahazuje ji
    /// **odmlka ve view** (`CodeTextSheet.resizeSettle`); je na to test, který tvrdí, že se otevřením
    /// a zavřením neuloží nic.
    static func codeSheetResize(kind: CodeText.Kind, opened: CGSize, measured: CGSize) -> CGSize? {
        guard measured.width.isFinite, measured.height.isFinite else { return nil }
        let floor = codeSheetFloor(kind: kind)
        let rounded = CGSize(width: measured.width.rounded(), height: measured.height.rounded())
        // Pod podlahu se nezapisuje: sheet se pod ni nedostane (je to `contentMinSize` okna), takže
        // menší číslo je mezistav rozvržení, ne velikost okna.
        guard rounded.width >= floor.width, rounded.height >= floor.height else { return nil }
        let asked = CGSize(width: opened.width.rounded(), height: opened.height.rounded())
        guard rounded != asked else { return nil }
        return rounded
    }

    private static func codeSheetFloor(kind: CodeText.Kind) -> CGSize {
        switch kind {
        case .hunk: codeSheetHunkFloor
        case .log: codeSheetLogFloor
        }
    }

    /// Jak velký sheet **smí** být: obrazovka bez okrajů, nebo pojistka, když obrazovku neznáme.
    /// Nikdy pod podlahu — na displeji, kam se podlaha nevejde, rozhoduje podlaha, ne okraj.
    private static func codeSheetBounds(kind: CodeText.Kind, screen: CGSize?) -> CGSize {
        let floor = codeSheetFloor(kind: kind)
        guard let screen, screen.width.isFinite, screen.height.isFinite,
              screen.width > 0, screen.height > 0
        else { return codeSheetCap }
        return CGSize(
            width: max(screen.width - codeSheetScreenMargin, floor.width),
            height: max(screen.height - codeSheetScreenMargin, floor.height)
        )
    }

    // MARK: - Co se do šířky vejde

    /// Odsazení textu od hrany kontejneru v `SelectableCodeView` (`textContainerInset`), na každé
    /// straně jedno. Je tady, aby se **kresba a výpočet nerozešly** — view si tuhle hodnotu bere
    /// odsud.
    static let codeSheetTextInset: CGFloat = 8

    /// `lineFragmentPadding` textového kontejneru — TextKit ho drží na obou stranách řádku a **do
    /// šířky textu se nepočítá**. Není to naše volba, je to default; test nad skutečným
    /// `NSTextView`em tvrdí, že platí pořád.
    static let codeSheetFragmentPadding: CGFloat = 5

    /// Kolik znaků kódu se vejde na jeden řádek sazby v sheetu dané šířky.
    ///
    /// Ta samá aritmetika, kterou jsou spočítané tabulky v sekci 28 návrhu (66 znaků při 560 bodech,
    /// 143 při 1 180, 166 při 1 360), a `characterWidth` se **měří na písmu**, ne zadrátovává:
    /// mono 13 b má na tomhle systému 8,036 bodu na znak, ale je to hodnota fontu, ne konstanta
    /// aplikace. Tatáž úvaha jako u `charactersPerSide` (#188).
    static func codeSheetCharacters(width: CGFloat, characterWidth: CGFloat) -> Int {
        guard characterWidth > 0 else { return 0 }
        let text = width - 2 * (codeSheetTextInset + codeSheetFragmentPadding)
        return max(Int(text / characterWidth), 0)
    }

    /// Řádky textu v sheetu — **jedno místo pro počítání**, ať hlavička a patička nemluví každá
    /// o jiném počtu.
    ///
    /// `TextLines`, ne `split(separator: "\n")`: kód z cizího repa má `CRLF` a ten je ve Swiftu jeden
    /// `Character` (#292), takže by z celého hunku zbyl jeden „řádek“. A **poslední prázdný řádek za
    /// koncovým zlomem se nepočítá** — tatáž úvaha jako u `logTail` a `jobLog`: je to konec
    /// posledního řádku, ne řádek další. `Policy.code(of:)` zlomem nekončí, takže na hunku z diffu se
    /// tím nic nemění; platí to o textu, který sem přijde odjinud.
    static func codeSheetLines(of code: String) -> [Substring] {
        var lines = TextLines.all(code)
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    /// Kolik řádků hunku se na šířku nevejde. `nil` = **nevejde se žádný, nebo není co počítat**.
    ///
    /// Kreslí se z toho věta v patičce, protože **bez ní vypadá zalomený řádek jako dva** — a i
    /// nejširší rozumný sheet dlouhý řádek zalomí (nejdelší ze 128 měřených hunků měl 181 znaků).
    ///
    /// **Jen pro hunk, ne pro log** (#417): u logu se zalamuje čtvrtina až dvě třetiny řádků, takže
    /// věta nic neřekne — a hlavně by to byl scan megabajtů **při každém přerovnání šířky**, tedy
    /// zrovna to, co zakazuje #224. Hunk má desítky řádků.
    ///
    /// **Počítá se ze šířky sheetu, ne z šířky textu, a je v tom jedna změřená nepřesnost.** Svislý
    /// scroller si v **legacy** stylu ukusuje 17 bodů (změřeno: `contentView.bounds.width` 1 163
    /// proti 1 180 při `overlay`), tedy necelé dva znaky. Nepočítá se s ním ze dvou důvodů: styl se
    /// mění **za běhu** podle připojené myši (změřeno u #347), takže by věta jednou tvrdila tohle
    /// a jednou tamto, a tabulka v sekci 28 návrhu je spočítaná bez něj. Cena je zapsaná: u řádku,
    /// který je o znak nebo dva nad kapacitou, může věta při legacy scrolleru **mlčet**. Je to ta
    /// strana, na které se chybovat má — mlčení znamená „není co říct“, kdežto věta o zalomení,
    /// které nenastalo, je nepravda.
    static func codeSheetOverflow(code: String, width: CGFloat, characterWidth: CGFloat) -> CodeSheetOverflow? {
        let capacity = codeSheetCharacters(width: width, characterWidth: characterWidth)
        guard capacity > 0 else { return nil }
        let lines = codeSheetLines(of: code)
        let wrapped = lines.count { $0.count > capacity }
        guard wrapped > 0 else { return nil }
        return CodeSheetOverflow(wrapped: wrapped, total: lines.count)
    }
}
