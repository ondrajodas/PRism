import Foundation

extension Policy {
    /// Kolik znaků kódu se vejde na jednu stranu diffu (#188).
    ///
    /// Aplikace slibuje, že se **PHP na 120 znaků vejde** (`CLAUDE.md`), jenže v pohledu vedle
    /// sebe se řádek dělí na dvě strany a k tomu mu ubírají postranní sloupce. Když se ten slib
    /// nedá splnit, je poctivější to **ukázat číslem** než nechat řádky potichu ořezávat.
    ///
    /// Počítá se z **měřené** šířky obsahu a šířky jednoho znaku písma, kterým se kód sází —
    /// spočítané tabulky v zadání #188 platí pro jeden displej a jedno nastavení, kdežto tohle
    /// platí pro okno, které mám zrovna otevřené.
    ///
    /// `gutter` je to, co si na každé straně bere sloupec s čísly řádků a znaménkem změny.
    /// **Bez výchozí hodnoty schválně** (nález Copilota na #188): měl jsem tu 64, kdežto diff
    /// kreslí `DiffLineView.contentInset(for:)` — tedy 84 ve splitu a 136 pod sebou. Vymyšlené
    /// číslo dělalo ukazatel optimističtější, než jaká je pravda, takže varování mohlo mlčet
    /// zrovna nad řádky, které se lámou. Volající předává skutečnou hodnotu.
    static func charactersPerSide(
        contentWidth: Double,
        characterWidth: Double,
        layout: DiffLayout,
        gutter: Double
    ) -> Int {
        guard characterWidth > 0 else { return 0 }
        // U pohledu vedle sebe se šířka dělí na dvě strany a každá má vlastní sloupec s čísly.
        let sides = layout == .split ? 2.0 : 1.0
        let available = contentWidth / sides - gutter
        return max(Int(available / characterWidth), 0)
    }

    /// Kolik znaků aplikace slibuje. Pod tím se v liště rozsvítí varování — a je to **slib
    /// z `CLAUDE.md`**, ne odhad: PHP se v Keboole píše na 120.
    static let promisedCharactersPerSide = 120

    /// Jak široký má být sheet s kódem a s celým logem (#292).
    ///
    /// **Sheet zalamuje** (`SelectableCodeView`), takže úzké okno neznamená, že se text nevejde —
    /// znamená, že jeden řádek logu je pár řádků sazby a scrolluje se přes ně. Změřeno na skutečném
    /// 8,78MB logu (25 534 logických řádků, mono 13 b, 8,04 b na znak):
    ///
    /// | Šířka sheetu | Znaků na řádek | Řádků sazby | Proti logickým |
    /// |---|---|---|---|
    /// | 820 (**dřív** ideální) | 100 | 99 362 | 3,89× |
    /// | 1 360 (na 1512b obrazovce) | 167 | 67 138 | 2,63× |
    /// | 1 600 | 197 | 59 589 | 2,33× |
    /// | 2 000 | 246 | 52 203 | 2,04× |
    /// | 2 400 | 296 | 41 248 | 1,62× |
    /// | **2 700 (strop)** | **333** | **39 269** | **1,54×** |
    /// | 3 288 (celá 3440b obrazovka) | 407 | 30 845 | 1,21× |
    ///
    /// Ze 820 na 1 360 ubude **třetina** řádků sazby, na stropu 2 700 je to **60 %**. Zalamování se
    /// přitom úplně odstranit nedá: nejdelší řádek má 2 229 znaků, tedy 17 900 bodů.
    ///
    /// Tři meze a každá má důvod:
    /// - **`margin` od hran obrazovky**, aby sheet nebyl banner přes celou plochu;
    /// - **strop 2 700 bodů = 333 znaků na řádek**, protože to je zrovna **mediánový řádek toho
    ///   logu** (327 znaků; p90 je 452). Do téhle šířky tedy přestane zalamovat *typický* řádek,
    ///   a co je nad ní, už jen ukrajuje z toho dlouhého konce rozdělení — za cenu sheetu přes celou
    ///   plochu ultrawide monitoru, ve kterém se navíc kreslí i hunky kódu (řádek ~120 znaků, tedy
    ///   ~960 bodů). **Strop byl chvíli 1 600** a zvedl se po tom, co se měřilo na skutečné
    ///   obrazovce uživatele (3 440 bodů): 1 600 tam nechávalo 2,33× proti 1,54×, tedy polovinu
    ///   scrollování navíc, a to jen kvůli číslu odhadnutému na menším displeji;
    /// - **nikdy užší než dřív (820)**, ledaže by se to nevešlo na obrazovku; na malém displeji
    ///   rozhoduje obrazovka, ne konstanta z většího.
    static func codeSheetWidth(screenWidth: CGFloat?) -> CGFloat {
        guard let screenWidth, screenWidth > 0 else { return previousCodeSheetWidth }
        let comfortable = min(screenWidth - codeSheetMargin, codeSheetWidthCap)
        return max(comfortable, min(previousCodeSheetWidth, screenWidth - codeSheetEdge))
    }

    /// Ideální šířka sheetu do #292. Zůstává jako **dolní mez**: širší je zlepšení, užší by byla
    /// regrese.
    static let previousCodeSheetWidth: CGFloat = 820
    /// Kolik zůstane po stranách sheetu na obrazovce (dohromady, ne na stranu).
    static let codeSheetMargin: CGFloat = 152
    /// Naprostá mez u hrany obrazovky — pod ni se jde jen na displeji, kam se `820` nevejde.
    static let codeSheetEdge: CGFloat = 40
    /// Strop: šířka, ve které přestane zalamovat mediánový řádek Actions logu (333 znaků).
    static let codeSheetWidthCap: CGFloat = 2_700
}
