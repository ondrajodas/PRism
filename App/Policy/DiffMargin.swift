import Foundation

/// Co nese pruh na pravé hraně řádku a hrana karty v okraji (#503).
///
/// Je to **tatáž škála jako u bubliny pod řádkem a u karty v panelu** (`FindingBubbleView.accent`,
/// `FindingCardView.accent`, řádek fronty #172) — jen vyjádřená hodnotou, aby o barvě rozhodovalo
/// jedno místo v kresbě (`DiffMarginSeverity.stripe`) a `Policy` zůstala bez `SwiftUI`.
enum DiffMarginSeverity: Hashable, Sendable {
    /// Aspoň jeden platný nález skupiny blokuje merge.
    case blocking
    /// Platný nález, který merge nedrží.
    case finding
    /// Ze skupiny nezbyl platný nález — odmítl jsem je všechny (#113). **Karta nemizí**, jen
    /// ztichne: schovaný nález se nedá přečíst a nedá se odlišit od neexistujícího.
    case dismissed
}

/// Jedna karta v okraji vpravo (#503).
///
/// **Vzniká z dat, ne z geometrie**: o tom, jestli karta existuje, rozhoduje `Policy` nad diffem
/// (soubor je rozbalený a jeho řádek se doopravdy kreslí), kdežto geometrie říká jen **kde** stojí.
/// Kdyby o existenci karty rozhodovalo hlášení z bloku, zmizela by karta u řádku, jehož blok je
/// zrovna mimo nasazený pás (#469) — tedy pokaždé, když se odscrolluje.
struct DiffMarginCard: Identifiable, Hashable, Sendable {
    /// Klíč, na kterém se karta a pruh u řádku potkají: `<cesta souboru>|<řádek>`.
    ///
    /// Skládá se **z cesty, kterou zná blok kódu** (`FileDiff.displayPath`), ne z té, pod kterou
    /// nález přišel: reviewer umí přejmenovaný soubor nahlásit pod starou cestou, takže by se ty
    /// dvě strany jinak nepotkaly.
    let id: String
    let group: FindingGroup
    let path: String
    /// Číslo řádku v **nové** verzi souboru — na to se nález kotví (`DiffRow.withBubbles`).
    let line: Int
    let severity: DiffMarginSeverity
}

/// Značka u jednoho řádku bloku kódu (#503): pruh na pravé hraně a klíč, pod kterým blok hlásí,
/// kde ten řádek leží.
struct DiffMarginMark: Hashable, Sendable {
    let id: String
    let severity: DiffMarginSeverity
}

/// Soubor diffu tak, jak ho okraj potřebuje znát.
///
/// Tři hodnoty, ne closury: `Policy` je čistá funkce a testuje se výčtem, takže si stav
/// (rozbalený kontext, sbalený soubor) skládá volající — je to tentýž vzorec jako u
/// `Policy.commentRangeCells(of:in:)`.
struct DiffMarginSource: Sendable {
    let file: FileDiff
    /// Odkryté úseky mimo hunky. **Prázdné, dokud se obsah souboru nenačte** — tatáž úvaha jako
    /// v `DiffRow.rows(of:…)`, jinak by se karta kotvila na řádek, který se nekreslí.
    let revealed: RevealedLines
    let isFolded: Bool
}

/// Které postranní sloupce diffu jsou rozložené (#188, rozšířeno #503).
struct DiffSideColumns: Hashable, Sendable {
    let tree: Bool
    let panel: Bool
    /// Kreslí se okraj s kartami? **Není to totéž jako „karty existují“** (#503, oprava
    /// z proklikání): karty mohou být, a okraj se přesto nevejde — pak se nekreslí, protože
    /// třistabodová kolona, na kterou není místo, si ho vezme obsahu a schová ho pod proužek
    /// panelu.
    let margin: Bool
}

extension Policy {
    /// Karty do okraje vpravo (#503) — v pořadí obsahu, tedy po souborech a v nich po řádcích.
    ///
    /// Karta vznikne jedině tam, kde má **co k čemu zarovnat**: soubor je rozbalený a jeho řádek
    /// se v diffu doopravdy kreslí (hunk, nebo odkrytý kontext). Nález bez řádku, nález na řádku,
    /// který v diffu není, i nález ve sbaleném souboru proto v okraji **nejsou** — zůstávají tam,
    /// kde jsou dneska: jako bublina u hlavičky souboru (`DiffRow.finding(anchored: false)`),
    /// respektive jako počet v hlavičce sbaleného souboru. Bez toho pravidla by se karta buď
    /// neměla kde postavit, nebo by tvrdila polohu řádku, který nikdo nekreslí.
    ///
    /// Nálezy se do skupin slévají **tou samou funkcí jako bubliny** (`DiffRow.groups(of:from:)`),
    /// takže se okraj a diff nemohou rozejít v tom, kolik nálezů na jednom řádku je.
    static func marginCards(
        of groups: [FindingGroup],
        in sources: [DiffMarginSource],
        categories: Set<String> = defaultBlockingCategories
    ) -> [DiffMarginCard] {
        var cards: [DiffMarginCard] = []
        for source in sources where !source.isFolded {
            let file = source.file
            var mine: [DiffMarginCard] = []
            for group in DiffRow.groups(of: file, from: groups) {
                guard let line = group.line,
                      DiffRow.renders(line: line, of: file, revealed: source.revealed)
                else { continue }
                mine.append(DiffMarginCard(
                    id: marginKey(path: file.displayPath, line: line),
                    group: group,
                    path: file.displayPath,
                    line: line,
                    severity: marginSeverity(of: group, categories: categories)
                ))
            }
            // Uvnitř souboru podle řádku: `DiffRow.groups` vrací skupiny ze slovníku, takže pořadí
            // nemá — a v okraji je pořadí to, podle čeho se karty odstrkují.
            cards += mine.sorted { $0.line < $1.line }
        }
        return cards
    }

    /// Klíč karty. Jedno místo pro obě strany — okraj i blok kódu.
    static func marginKey(path: String, line: Int) -> String { "\(path)|\(line)" }

    /// Značky pro jeden soubor, klíčované **novým** číslem řádku: blok kódu o kartách nic neví,
    /// zná jen řádky, takže se překlad musí odehrát tady.
    static func marginMarks(of cards: [DiffMarginCard], in path: String) -> [Int: DiffMarginMark] {
        var marks: [Int: DiffMarginMark] = [:]
        for card in cards where card.path == path {
            marks[card.line] = DiffMarginMark(id: card.id, severity: card.severity)
        }
        return marks
    }

    /// Kde karty v okraji doopravdy stojí — **zarovnané k řádku, a když se potkají, odstrčené**.
    ///
    /// Karta chce stát na horní hraně svého řádku. Když by se přitom trefila do té nad sebou,
    /// odstrčí se pod ni; spojnice se tím zalomí do `L` a to je právě to, co ze zarovnání zbude
    /// (kresbu řeší `DiffMarginView`). Odstrkuje se **jen dolů**: nahoru by karta minula řádek,
    /// který už je vidět, a čte se vždycky odshora.
    ///
    /// - Parameters:
    ///   - desired: kde by karta stát chtěla. `nil` = polohu jejího řádku ještě žádný blok
    ///     neohlásil (první rozvržení, nebo blok, který se nikdy nekreslil). Karta pak jde **za
    ///     předchozí**, protože „nevím kde“ je pořád lepší odpověď než „na nule“ — zmizet nesmí.
    ///   - heights: změřené výšky karet ve stejném pořadí. Chybějící výška se bere jako nula,
    ///     tedy bez odstrčení: karta, kterou nikdo nezměřil, o sousedech nic netvrdí.
    ///   - gap: mezera mezi odstrčenými kartami (návrh má 8).
    static func marginTops(desired: [Double?], heights: [Double], gap: Double) -> [Double] {
        var tops: [Double] = []
        tops.reserveCapacity(desired.count)
        // Obsah začíná na nule, takže výš než tam se karta dostat nemá — jinak by vyjela nad diff.
        var floor = 0.0
        for (index, wanted) in desired.enumerated() {
            let top = max(wanted ?? floor, floor)
            tops.append(top)
            floor = top + (heights.indices.contains(index) ? heights[index] : 0) + gap
        }
        return tops
    }

    /// Které postranní sloupce jsou rozložené (#188, rozšířeno #503).
    ///
    /// **Pohled vedle sebe složí oba** — řádek se v něm dělí na dvě strany, takže na 14" nezbude
    /// ani sto znaků (#188).
    ///
    /// **A okraj s kartami složí panel vpravo**, protože v tom stavu jsou vpravo dvě třistabodové
    /// kolony o téže věci: karta v okraji a týž nález jako řádek v panelu. Panel **nezmizí** —
    /// složený je proužek s počtem nálezů a značkou rozdělaného review, a `⌘2` ho vrátí až do
    /// další změny pohledu, přesně jako u #188.
    ///
    /// **Od #548 je to větev za přepínačem, ne výchozí stav.** Výchozí jsou bubliny pod řádky,
    /// takže `hasMargin` je `false` a o panelu rozhoduje jedině pohled — tedy #188 beze změny,
    /// stav, jaký byl do #503. Skládání panelu je tedy vidět jedině s okrajem zapnutým z lišty,
    /// **a vrací se to zpátky**: přepnutím na bubliny se panel zase rozloží, protože `task(id:)`
    /// v `DiffView` má identitou samo rozhodnutí, ne jeho vstupy. Odpadne to teprve se #504
    /// (seznam nálezů v panelu zaniká), a to je od #548 odložené v `Průběžné`.
    ///
    /// **Šířka je vstup, ne dodatečná kontrola** (#220, oprava z proklikání #503). Do téhle
    /// opravy o kolonách rozhodoval jen pohled, takže se v úzkém okně sešly strom (210), kód
    /// a okraj (300) v jednom `HStack`u, jehož pružné dítě je uprostřed — a když se pevné části
    /// nevejdou, `HStack` **přesype rozdíl doprava**, tedy pod složený proužek panelu. Naměřeno
    /// v okně 700 (podlaha `RootView`u): přetečení **35 bodů** s okrajem a **16** bez něj,
    /// v obou pohledech; u hlavičky souboru se to projeví ukousnutým `+347 −0`.
    ///
    /// Rozhoduje se proto **odečítáním**, ne dohadováním, a v pořadí podle toho, co je jak drahé
    /// zahodit:
    ///
    /// 1. **Kód nikdy** — je to důvod, proč je okno otevřené.
    /// 2. **Strom jde první**, protože je nejlevnější: `⌘1` ho vrátí a v liště je pořád popover
    ///    se stejným seznamem, takže se tím nic nedozvíme méně.
    /// 3. **Okraj až potom, a nikdy tak, aby nález zůstal bez domova.** Zahodit okraj znamená
    ///    schovat nález, takže se s ním zároveň **rozloží panel**, který ho převezme
    ///    (`panel` níž). Ve `Vedle sebe` se proto okraj drží, i když na kód zbývá pod podlahu —
    ///    úzká kolona kódu je menší škoda než nález, který na obrazovce není; zahodí se teprve
    ///    tehdy, když se ta kolona nevejde **fyzicky**.
    ///
    /// **Zahození okraje rozloží panel, a přesto to nekmitá** — což je ta neintuitivní část.
    /// `available` je šířka **po** odečtení panelu (měří ji detail PR), takže rozhodnutí mění svůj
    /// vlastní vstup a `task(id: columns)` v `DiffView` má stráž jen proti **témuž** výsledku, ne
    /// proti kmitání A→B→A. Bezpečné je to proto, že ta zpětná vazba je **monotónní**: rozložením
    /// panelu se `available` jedině **zmenší**, a menší `available` okraj drží zahozený. Cyklus by
    /// vznikl jedině tehdy, kdyby zahození okraje šířku zvětšilo — a to se stát nemůže, protože
    /// složený proužek je vždycky užší než rozložený panel.
    ///
    /// - Parameter available: šířka, o kterou se dělí **sloupec, kód a okraj** — tedy okno bez
    ///   railu a bez panelu. **Od #506 to není štěrbina diffu**: sloupec odečítá rozvržení detailu
    ///   PR, takže si ji `DiffView` bere z prostředí (`sideColumnsWidth`).
    ///   `nil` znamená „nikdo ji nezměřil“ a chová se jako dřív (rozhoduje jen pohled) — bez toho
    ///   by se kolony složily každému, kdo `DiffView` hostuje mimo okno. **A nula je totéž co
    ///   `nil`, ne nejužší možné okno** (#506/3): první průchod `GeometryReaderem` vydá nulu, ze
    ///   které by vyšlo „složit všechno“ — a protože se to rozhodnutí od #506 ukládá do volby
    ///   člověka, nebyl by to jen problém jednoho snímku. Je to tatáž hranice, na které mlčí
    ///   `widthWithItinerary`, jen z druhé strany: ta vydá `nil`, kdežto fallback na vlastní
    ///   štěrbinu diffu nulu propustí.
    static func diffSideColumns(
        layout: DiffLayout,
        hasMargin: Bool,
        available: Double? = nil
    ) -> DiffSideColumns {
        let wide = layout != .split
        guard let available, available > 0 else {
            return DiffSideColumns(tree: wide, panel: wide && !hasMargin, margin: hasMargin)
        }
        let floor = minimumCodeWidth(layout: layout)
        var tree = wide
        var margin = hasMargin
        func codeWidth() -> Double {
            available - treeColumnWidth(expanded: tree) - marginColumnWidth(shown: margin)
        }
        if codeWidth() < floor { tree = false }
        // **Pod sebou** stačí, že se kód dostal pod podlahu — panel okraj převezme a je v něm
        // na nález víc místa než v úzké koloně vedle kódu.
        if wide, codeWidth() < floor { margin = false }
        // **Vedle sebe** se okraj drží, dokud se vejde fyzicky: hlídá se, že po něm zbyde na kód
        // aspoň něco, ne že zbyde podlaha.
        if codeWidth() <= 0 { margin = false }
        return DiffSideColumns(
            tree: tree,
            // **Karty rozhodují víc než pohled**: když se okraj nekreslí a nálezy jsou, panel je
            // jejich jediný domov a musí být rozložený — i ve `Vedle sebe`, kde by ho #188 jinak
            // složilo. Bez karet platí #188 beze změny.
            panel: hasMargin ? !margin : wide,
            margin: margin
        )
    }

    /// Šířka kolony kódu — **plocha, na které se doopravdy sází** (#546).
    ///
    /// Je to tatáž aritmetika, jakou provádí `HStack` v `DiffView`: od štěrbiny diffu se odečte
    /// okraj a **mezera před tím, co stojí vpravo** (`codeColumnTrailingGap`, #503 — ta je
    /// mimo `fillingSlot` schválně, takže od štěrbiny ubývá). Odsud se šířka **předává** obsahu
    /// i ukazateli `N znaků na stranu`; do #546 si ji obsah měřil sám a měřil něco jiného.
    ///
    /// **Levý sloupec se odsud od #506 neodečítá.** Itinerář stojí vedle **všech** tabů, takže ho
    /// odečítá rozvržení detailu PR a `available` je štěrbina, ve které už není. Kdo ho odečte
    /// znovu, dostane kolonu o 260 (respektive 34) bodů užší, než jakou `HStack` doopravdy dá —
    /// a to je přesně ta třída vady, kterou řešilo #546, jen v druhém směru.
    ///
    /// **Proč to není další pole `DiffSideColumns`.** Ta struktura je identita `task(id:)`
    /// v `DiffView` — rozhodnutí o kolonách se má uplatnit jednou —, kdežto tohle je číslo, které se
    /// mění při každém tažení za roh okna. Slité dohromady by se automatika sloupců pouštěla při
    /// každém bodu změny šířky.
    ///
    /// `nil` znamená „nikdo štěrbinu nezměřil“ a chová se jako do #546: obsah si vezme, co dostane.
    /// Bez toho by `DiffView` mimo okno (náhledy, sondy) dostal nulu a zmizel by.
    ///
    /// **Nikdy záporná**: v okně užším než postranní kolony by odečítání šlo pod nulu a `frame`
    /// se zápornou šířkou je nedefinovaný stav. `diffSideColumns` proto okraj v takovém okně
    /// zahodí — tahle podlaha je druhá pojistka, ne to rozhodnutí.
    static func diffCodeColumnWidth(available: Double?, columns: DiffSideColumns) -> Double? {
        guard let available else { return nil }
        let sides = marginColumnWidth(shown: columns.margin) + codeColumnTrailingGap
        return max(available - sides, 0)
    }

    /// Šířka, o kterou se dělí **sloupec, kód a okraj** — spočítaná ze štěrbiny, kterou dostal
    /// obsah tabu (#506).
    ///
    /// Od #506 stojí itinerář vedle všech tabů, takže ho odečítá `HStack` v detailu PR a `slot`
    /// je to, co po něm zbylo. Rozhodnutí o kolonách (`diffSideColumns`) se ale musí ptát na tu
    /// **společnou** šířku — jinak by se sloupec skládal podle toho, co po něm zbylo, tedy sám
    /// podle sebe.
    ///
    /// **Přičtení je přesné, ne odhad**: sloupec má právě dvě šířky (`treeColumnWidth`) a která
    /// z nich zrovna platí, ví ten, kdo ho kreslí. Zpětná vazba se tím nerozkmitá: složení
    /// sloupce štěrbinu zvětší přesně o tolik, o kolik se přičítalo méně, takže z obojího vyjde
    /// tatáž společná šířka a tedy totéž rozhodnutí.
    ///
    /// `nil` = **štěrbinu nikdo nezměřil** (nulová plocha při prvním průchodu, náhled mimo okno),
    /// a `diffSideColumns` se pak rozhoduje jen podle pohledu — jako do #503. Bez toho by se
    /// v prvním průchodu složilo všechno a vzápětí rozložilo zpátky.
    static func widthWithItinerary(slot: Double, expanded: Bool) -> Double? {
        guard slot > 0 else { return nil }
        return slot + treeColumnWidth(expanded: expanded)
    }

    /// Kolik musí zbýt na kód, aby to k něčemu bylo.
    ///
    /// **Je to změřená mez, ne kulaté číslo.** Hlavička souboru nese `nový`, `2 blokují`,
    /// `+347 −0` a `Prošlo` na jedné řádce; v okně 820 (kolona kódu 396) se vejde celá, v okně
    /// 700 (kolona 276, respektive 169 s rozloženým stromem) se **ukousne** — a přesně tím se
    /// vada z proklikání poznala. Podlaha je proto nad tím horním koncem naměřeného rozpětí.
    ///
    /// **Vedle sebe je dvojnásobná**, protože se šířka dělí na dvě strany: to je tatáž úvaha,
    /// jakou má #188 pro složení sloupců, jen vyjádřená číslem místo příznaku.
    static func minimumCodeWidth(layout: DiffLayout) -> Double {
        layout == .split ? 2 * 180 : 360
    }

    /// Šířka levého sloupce — rozložený z návrhu (`260px`, sekce 47), složený jako pruh s ikonou.
    /// Konstanty jsou tady schválně: rozhoduje se podle nich, takže view je čte odsud, ne naopak.
    ///
    /// **Od #506 je to 260, ne 210** (návrh sekce 47). Sloupec přestal být strom cest a stal se
    /// itinerářem: na řádce vedle sebe stojí glyf stavu, nadpis zastávky a údaj vpravo
    /// (`3 commity`, `návrh: schválit`), a to se do 210 bodů nevejde — nejdelší z těch údajů má
    /// 18 znaků, tedy ~100 bodů, a na nadpis `Soubory podle rizika` by zbylo ~70.
    ///
    /// **Změřeno, ne odhadnuto** (`ItineraryColumnRoomTests`, štěrbina 1 047 b, znak 8,036 b):
    /// *Vedle sebe* **3 znaky na stranu** (41 → 38), *Pod sebou* **6 znaků** (86 → 80). A ve
    /// `split`u se za to neplatí ani tou trojkou: kolonu kódu tam neurčuje šířka sloupce, ale
    /// `diffSideColumns` — sloupec se ve `split`u **skládá** (#188), takže je z něj pruh 34 bodů
    /// v obou případech; ta trojka je cena za to, když si ho tam člověk otevře `⌘1`. Hranice, pod
    /// kterou se sloupec skládá, se posunula o týchž **50 bodů** (570 → 620 bez okraje karet,
    /// 870 → 920 s ním). Čísla jsou v `docs/testovani.md`.
    static func treeColumnWidth(expanded: Bool) -> Double {
        expanded ? 260 : 34
    }

    /// Šířka okraje s kartami z návrhu (`300px`), nebo nula, když se nekreslí.
    static func marginColumnWidth(shown: Bool) -> Double {
        shown ? 300 : 0
    }

    /// Barva hrany karty a pruhu u řádku. Odmítnutá skupina ztichne, blokující křičí — **tatáž
    /// úvaha jako `FindingBubbleView.accent`**, jen vyjádřená hodnotou.
    private static func marginSeverity(
        of group: FindingGroup,
        categories: Set<String>
    ) -> DiffMarginSeverity {
        let active = group.activeFindings
        guard !active.isEmpty else { return .dismissed }
        return active.contains { isBlocking($0, categories: categories) } ? .blocking : .finding
    }
}
