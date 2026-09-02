import CoreGraphics

/// Jeden přeměřený řádek diffu pro hledání kotvy scrollu (#527).
///
/// **Číslo řádku, ne `id`.** Identita řádku v seznamu je `<soubor>|h0l3` nebo `<soubor>|c412`
/// (viz `DiffRow.id`), tedy pozice v hunku — z ní se číslo řádku zpátky nepřečte. Kotva se přitom
/// ukládá na disk a po restartu se hledá znovu (`DiffRow.anchor(in:file:line:)`), takže musí být
/// vyjádřená v **kódu**: soubor a číslo. Číslo dodává `DraftAnchor`, který u řádku v krabici
/// ploch (`DiffRowFrames`) leží kvůli tažení rozsahu.
struct DiffScrollRow: Equatable, Sendable {
    /// Svislý rozsah řádku v souřadnicích **obsahu** diffu.
    let extent: ClosedRange<Double>
    /// Číslo řádku v **nové** verzi souboru.
    let line: Int
}

extension Policy {
    /// Kde stojí výřez diffu, vyjádřené jako **soubor a řádek** (#527).
    ///
    /// Skládá se ze dvou nezávislých odpovědí, protože každá má jiný zdroj a jinou přesnost:
    ///
    /// - **soubor** se bere z rozsahů souborů (`DiffFileExtents`) **tou samou funkcí, jakou se
    ///   vybírá ukotvená hlavička** (`pinnedFileHeader`). Dvě různá rozhodnutí o tom, „který
    ///   soubor drží horní hranu“, by znamenala, že se po restartu přistane u jiného souboru,
    ///   než jakého hlavička nad výřezem tvrdila;
    /// - **řádek** se hledá mezi přeměřenými řádky **toho** souboru: bere se ten, který hranu
    ///   protíná, a když ji neprotíná žádný (hrana padla mezi bloky, nebo se do pásu ještě
    ///   nenasadily), tak **první pod ní**. Nikdy ne ten nad ní: kotva má ukázat na kód, který je
    ///   vidět.
    ///
    /// `nil` se vrací **jen tehdy, když se nedá pojmenovat ani soubor** — tedy dokud se rozsahy
    /// nezměřily nebo dokud je výřez nad prvním souborem. Soubor **bez** řádku je platná odpověď:
    /// přistane se na jeho hlavičce, což je pořád blíž než začátek diffu.
    ///
    /// - Parameters:
    ///   - top: horní hrana výřezu v souřadnicích obsahu (`DiffViewport.top`).
    ///   - files: cesty souborů v pořadí, jak jsou pod sebou.
    ///   - extents: jejich svislé rozsahy, v **tomtéž** pořadí. Kratší pole než `files` znamená
    ///     „ještě se to celé nezměřilo“ (`DiffFileExtents.ordered(of:)` vrací prázdno, dokud
    ///     chybí jediný rozsah), takže se vrací `nil`.
    ///   - rows: přeměřené řádky **jednoho** souboru, toho, který hranu drží. Nemusí být řazené.
    static func diffScrollAnchor(
        top: Double,
        files: [String],
        extents: [ClosedRange<Double>],
        rows: (_ file: String, _ extent: ClosedRange<Double>) -> [DiffScrollRow]
    ) -> DiffScrollAnchor? {
        guard files.count == extents.count,
              let index = pinnedFileHeader(files: extents, top: top, headerHeight: 0)?.index,
              files.indices.contains(index)
        else { return nil }
        let file = files[index]
        return DiffScrollAnchor(file: file, line: line(at: top, in: rows(file, extents[index])))
    }

    /// Řádek, který drží horní hranu — nebo první pod ní. `nil` = žádný přeměřený není.
    ///
    /// Vlastní funkce, aby se dala vyčerpat výčtem bez skládání rozsahů souborů: hrana **mezi**
    /// bloky, hrana nad prvním řádkem i hrana pod posledním jsou tři různé případy a každý má
    /// jinou správnou odpověď.
    static func line(at top: Double, in rows: [DiffScrollRow]) -> Int? {
        // Jeden průchod, žádné řazení: krabice ploch je slovník, takže pořadí nemá, a řadit
        // tisíce řádků kvůli jedné odpovědi by byla práce navíc na cestě, která běží při
        // scrollování.
        var covering: DiffScrollRow?
        var below: DiffScrollRow?
        for row in rows where row.extent.upperBound >= top {
            if row.extent.lowerBound <= top {
                // Řádky se nepřekrývají, takže hranu protíná nejvýš jeden — a ten vyhrává.
                covering = row
            } else if row.extent.lowerBound < (below?.extent.lowerBound ?? .infinity) {
                below = row
            }
        }
        // **Nikdy řádek nad hranou.** Když je výřez pod posledním přeměřeným řádkem (blok se
        // odpojil, protože je mimo pás), je správná odpověď „nevím“ — soubor sám je pořád
        // pojmenovaný, takže se přistane na jeho hlavičce, ne na cizím řádku.
        return (covering ?? below)?.line
    }
}
