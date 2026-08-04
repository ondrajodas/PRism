import Foundation

/// Slití řádků diffu do dvojic pro pohled **vedle sebe**. Čistá funkce, žádné I/O.
extension DiffRow {
    /// Hotové řádky souboru slité do dvojic: vlevo starý obsah, vpravo nový.
    ///
    /// Pravidlo je jednoduché a poziční: blok po sobě jdoucích **odebraných** řádků se
    /// s následujícím blokem **přidaných** spáruje jeden na jednoho a přebytek na kterékoli
    /// straně dostane prázdnou protistranu. U přepsaného bloku tak `-` a `+` řádek stojí
    /// proti sobě, což je zrovna ta otázka, kvůli které se split pohled otevírá.
    ///
    /// Kontextový řádek stojí na **obou** stranách jako tatáž hodnota — z rovnosti se pozná,
    /// že je to jeden řádek souboru, ne dva (viz `DiffRow.sourceLines`).
    ///
    /// **Přes celou šířku jde všechno, co stranu nemá**: hlavička hunku, rozbalovací řádek,
    /// poznámka i `meta` řádek (`\ No newline at end of file`). Ten poslední není obsah
    /// souboru, takže dělit ho na poloviny nemá co znamenat.
    ///
    /// **Identita dvojice je identita pravého řádku**, levého jen tam, kde pravý není. Kotvy
    /// z nálezů i z vláken se hledají podle `newNumber` a ten je vždycky vpravo, takže
    /// `anchor(in:file:line:)` platí ve split pohledu **beze změny**.
    ///
    /// Slévá se **před** zavěšením bublin, ne po něm: bublina se vkládá za řádek s daným
    /// `newNumber`, takže by uprostřed bloku přidaných řádků párování rozťala a druhá
    /// polovina bloku by se spárovala s prázdnem.
    static func paired(_ rows: [DiffRow]) -> [DiffRow] {
        var result: [DiffRow] = []
        result.reserveCapacity(rows.count)
        // Rozdělaný blok. Řádky se drží i se svým `id`, protože z nich vzniká identita
        // dvojice — odvodit ji z pořadí by ji po rozbalení kontextu posunulo.
        var removed: [(id: String, line: DiffLine)] = []
        var added: [(id: String, line: DiffLine)] = []

        func flush() {
            let overlap = min(removed.count, added.count)
            for index in 0..<overlap {
                result.append(.pair(added[index].id, left: removed[index].line, right: added[index].line))
            }
            // Jen jedna z těch dvou smyček může mít co dělat — přebytek je vždycky
            // na jedné straně.
            for item in removed.dropFirst(overlap) {
                result.append(.pair(item.id, left: item.line, right: nil))
            }
            for item in added.dropFirst(overlap) {
                result.append(.pair(item.id, left: nil, right: item.line))
            }
            removed.removeAll(keepingCapacity: true)
            added.removeAll(keepingCapacity: true)
        }

        for row in rows {
            guard case .line(let id, let line) = row else {
                flush()
                result.append(row)
                continue
            }
            switch line.kind {
            case .removed:
                // Přidané řádky blok **uzavírají**: `+` po `-` je přepsání téhož místa,
                // ale `-` po `+` už je další skupina. Párovat je napříč by posadilo starý
                // obsah proti novému, který s ním nesouvisí.
                if !added.isEmpty { flush() }
                removed.append((id, line))
            case .added:
                added.append((id, line))
            case .context:
                flush()
                result.append(.pair(id, left: line, right: line))
            case .meta:
                flush()
                result.append(row)
            }
        }
        flush()
        return result
    }
}
