import Foundation

/// Odznak v Docku (#529, návrh sekce 49) — **jedno číslo, dvě místa**.
///
/// Odznak je *rail v Docku*, ne nový výpočet: bere tutéž množinu (cizí PR po filtru) a totéž
/// pravidlo o nule i o nenačteném seznamu. Kdyby si počet skládal sám, byla by to druhá pravda
/// o jednom čísle — a rozešly by se potichu, protože v Docku a v railu se nikdy nekoukám naráz.
extension Policy {
    /// Co napsat na dlaždici. `nil` znamená **prázdná dlaždice**, ne nula.
    ///
    /// **Prázdno, nula a „nevím“ vydávají totéž, a je to rozhodnutí** (poznámka 179 v návrhu):
    /// dlaždice má jeden kanál, takže se do ní věta „fronta ještě nedorazila“ napsat nedá,
    /// a odznak `0` by v systémové červené hlásil poplach nad ničím. Všechny tři stavy proto
    /// kreslí prázdno a rozlišují se **v okně** — rail má nulu bez odznaku, nenačtený seznam
    /// pozná stavový řádek. Odznak tvrdí jednu věc: *tolik jich čeká*.
    ///
    /// - Parameters:
    ///   - queue: fronta **po filtru** (cizí PR), nebo `nil`, dokud se seznam nenačetl. Že je to
    ///     tatáž množina pro obě čísla, drží **tvar téhle funkce**: `blocking` se počítá z toho
    ///     samého pole, takže nemůže vyjít větší než `waiting`. Kdyby se blokující bralo ze
    ///     souhrnu fronty (`queueSummary`), který filtr ignoruje, umělo by přepnutí volby ukázat
    ///     **větší** číslo — a invariant „blokující ≤ čekající“ drží jedině nad jednou množinou.
    ///   - isBlocking: leží na tomhle PR platný blokující nález? **U `waiting` a `off` se
    ///     nezavolá ani jednou** — je to uzávěr nad uloženými nálezy, takže by se jinak odznak
    ///     probouzel na každé změně záznamů i ve výchozí volbě, ve které o nálezech nemluví.
    static func dockBadge(
        _ mode: DockBadgeMode,
        queue: [PullRequestSummary]?,
        isBlocking: (PRIdentifier) -> Bool
    ) -> String? {
        // Pořadí je schválně takhle: volba `nic` neznamená „nevím“, ale „neptej se“ — takže se
        // nad ní nemá ani sahat na frontu.
        guard mode != .off else { return nil }
        guard let queue else { return nil }

        let count =
            switch mode {
            case .waiting: queue.count
            case .blocking: queue.count { isBlocking($0.id) }
            case .off: 0
            }
        return count == 0 ? nil : String(count)
    }

    /// Kde na dlaždici odznak leží a jak velké je v něm písmo.
    ///
    /// **Geometrie je tady, ne v kresbě**, ze stejného důvodu jako u `DiffGutterGeometry`: je to
    /// aritmetika nad rozměrem, takže se dá projít výčtem — kdežto ve `draw(_:)` by se ověřovala
    /// jedině bitmapou.
    ///
    /// **Odznak leží uvnitř dlaždice, ne za jejím rohem** (#529, změna proti sekci 49 návrhu).
    /// Systémový odznak dlaždici přesahuje, ale ten se kreslit nedá — `badgeLabel` je pod
    /// přepínačem `Odznaky` v Oznámeních a potichu se zahodí, takže si odznak kreslíme sami do
    /// `contentView`, a ten je plochou dlaždice **ořezaný**. Přiléhá proto k pravému hornímu
    /// rohu; **změřeno v živém Docku**, že systémový odznak má horní hranu na horní hraně ikony,
    /// takže se ta poloha od naší liší jen tím vodorovným přesahem.
    ///
    /// - Parameters:
    ///   - characters: kolik znaků na odznaku stojí. Odznak s jedním znakem je **kruh**, další
    ///     znaky ho roztáhnou do pilulky — jinak by dvojciferný počet z kruhu vylezl.
    ///   - bounds: plocha dlaždice. Rozhoduje **kratší strana**: dlaždice je čtverec, ale kdyby
    ///     ji systém podal jinak, odznak odvozený od šířky by se svisle nevešel.
    static func dockBadgeLayout(characters: Int, in bounds: CGRect) -> DockBadgeLayout {
        let side = min(bounds.width, bounds.height)
        // 0,38 kratší strany je **naměřená** velikost systémového odznaku: 17 px na dlaždici
        // 45 px v Docku téhle mašiny. Ne 22/72 ze sekce 49 návrhu — tam odznak leží půlkou venku,
        // takže by uvnitř dlaždice vyšel menší než ten, který kreslí systém vedle.
        let diameter = side * 0.38
        // Vata od hrany, aby odznak nesplýval s obrysem ikony. Podíl, ne body — dlaždice má
        // v Docku jinou velikost podle nastavení systému.
        let inset = side * 0.02
        // Každý další znak přidá 0,4 průměru. Odhad, ne sazba: číslice je v tomhle písmu asi
        // 0,37 průměru široká a kresba si text stejně **doměří** a v případě potřeby zmenší.
        //
        // **Strop na plochu dlaždice je podmínka, ne pojistka**, a přišel z testu: `contentView`
        // je dlaždicí ořezaný, takže od pěti znaků výš odznak jednou hranou vylezl a nenakreslil
        // se celý. Pět číslic ve frontě je nesmysl, ale odznak, ze kterého je vidět půlka, je
        // horší než veliké číslo — a text se do sražené pilulky zmenší.
        let width = min(
            diameter + diameter * 0.4 * CGFloat(max(0, characters - 1)),
            side - 2 * inset
        )
        return DockBadgeLayout(
            pill: CGRect(
                x: bounds.maxX - inset - width,
                y: bounds.maxY - inset - diameter,
                width: width,
                height: diameter
            ),
            fontSize: diameter * 0.62
        )
    }

    /// Rozměry odznaku na dlaždici (#529). Pilulka a velikost písma v ní.
    struct DockBadgeLayout: Equatable, Sendable {
        /// Obdélník odznaku. U jednoho znaku je to čtverec, tedy po zaoblení kruh.
        var pill: CGRect
        /// Velikost písma **před** doměřením v kresbě — viz `DockBadgeTileView`.
        var fontSize: CGFloat
    }
}
