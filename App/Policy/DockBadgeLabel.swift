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
}
