import CoreGraphics

extension Policy {
    /// Kde v bloku dvojic stojí vodorovný pruh, když blok přesahuje výřez (#428).
    ///
    /// Celé pravidlo je **jedna spojitá funkce posunu**, ne dva stavy:
    ///
    /// ```
    /// y = min(vlastní pás, hrana výřezu − pás)
    /// ```
    ///
    /// Dokud blok dolní hranu výřezu přesahuje, vyhraje druhý člen a pruh stojí **na hraně** — jeho
    /// poloha v okně se rolováním nemění. Jak se vlastní pás bloku do výřezu dostane, vyhraje první
    /// člen a pruh dál jede **rychlostí kódu**. Přechod není animace: vyjde z toho minima sám.
    ///
    /// **Vrací `y` v souřadnicích bloku** — nula je jeho horní hrana a `y` roste dolů. Je to přesně
    /// to, co jde zapsat scrolleru do `frame.origin.y`: `NSScrollView` **je flipped** (změřeno) a
    /// plocha sloupce je vysoká jako celý blok, takže se nic nepřepočítává mezi dvěma soustavami.
    /// Oba obdélníky přitom musí přijít **v jedné soustavě** a taky s `y` dolů (u vnořené plochy to
    /// zajistí `convert(_:from:)`).
    ///
    /// **Pruh nikdy neopustí svůj blok** — a tím padá otázka, komu patří, když jsou na obrazovce
    /// dva: na hraně výřezu může stát nejvýš jeden, ten, který k ní dosahuje. Drží to právě to
    /// minimum; dolní mez se nehlídá, protože ji drží heuristika níž (`visible >= 3 * rowHeight`
    /// znamená `y >= 3 * rowHeight − pás`, tedy nad nulou pro každou výšku řádku větší než třetina
    /// pásu — u kódu je to 16 proti 17). Že to platí přes celé pásmo posunů, tvrdí testy.
    ///
    /// **Jediná heuristika, a je pojmenovaná:** pod třemi viditelnými řádky bloku se pruh
    /// nepřišpendlí a zůstane ve svém pásu (tedy mimo obrazovku). Bez toho by zakryl polovinu toho
    /// mála, co z bloku vidět je, a popisoval by kód, který není čím přečíst. **Tři je odhad, ne
    /// měření** — je to jediné číslo v téhle změně, které měřením podložené není. Padá do ní i blok,
    /// který z výřezu vyjel celý: viditelná výška je nula, takže se ptát nemusíme zvlášť.
    ///
    /// `band` je výška, kterou si pruh bere (`DiffPairScrollView.scrollerHeight`, 17 b z AppKitu) —
    /// tedy tatáž hodnota, kterou si blok rezervuje ve `height(forWidth:)`. **Rezervace se posunem
    /// nemění**: mění se jen `frame.origin.y` scrolleru, protože měnit výšku bloku znamená přerovnat
    /// líný seznam při každém snímku.
    static func pinnedScrollerY(
        ofBlock block: CGRect,
        in viewport: CGRect,
        band: Double,
        rowHeight: Double
    ) -> Double {
        let own = Double(block.height) - band
        let visible = Double(min(block.maxY, viewport.maxY) - max(block.minY, viewport.minY))
        guard rowHeight > 0, visible >= Double(minimumPinnedRows) * rowHeight else { return own }
        return min(own, Double(viewport.maxY - block.minY) - band)
    }

    /// Kolik řádků bloku musí být vidět, aby se pruh přišpendlil k hraně výřezu (#428). Viz
    /// `pinnedScrollerY(ofBlock:in:band:rowHeight:)` — je to **odhad**, ne měření.
    static let minimumPinnedRows = 3
}
