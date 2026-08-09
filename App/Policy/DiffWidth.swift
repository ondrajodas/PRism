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
    static func charactersPerSide(
        contentWidth: Double,
        characterWidth: Double,
        layout: DiffLayout,
        gutter: Double = 64
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
}
