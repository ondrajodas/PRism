import Foundation

extension Policy {
    // MARK: - Slévání sad z jednoho běhu

    /// Sloučí jednu sadu anotací hunků do toho, co dorazilo dřív (#524).
    ///
    /// **Pozdější hlášení přepíše dřívější**, jako u nálezů (`Policy.mergedFindings`): session,
    /// která si větu rozmyslí, má poslat opravu a ne druhý řádek nad týmž hunkem. „Týž hunk“ je
    /// dvojice `(soubor, index)` — text v rozhodnutí nefiguruje, protože právě tím se ta oprava
    /// od originálu liší.
    ///
    /// **Pořadí drží to první hlášení.** Přepsaná anotace zůstane na svém místě, aby se uložený
    /// soubor dal číst očima ve stejném pořadí, v jakém stojí diff.
    static func mergedHunkAnnotations(
        _ existing: [HunkAnnotation],
        reporting batch: [HunkAnnotation]
    ) -> [HunkAnnotation] {
        merged(existing, reporting: batch) { AnnotationKey(file: $0.file, hunk: $0.hunk) }
    }

    /// Totéž pro druhy změny u souborů — klíčem je **cesta**, protože druh je na soubor jeden.
    static func mergedFileAnnotations(
        _ existing: [FileAnnotation],
        reporting batch: [FileAnnotation]
    ) -> [FileAnnotation] {
        merged(existing, reporting: batch) { AnnotationKey(file: $0.file, hunk: nil) }
    }

    /// Klíč, podle kterého se pozná „totéž místo“. **Vlastní typ, ne řetězec složený lepením**:
    /// cesta může obsahovat cokoli včetně oddělovače, takže by `"\(file)#\(hunk)"` uměl srazit dvě
    /// různá místa do jednoho.
    private struct AnnotationKey: Hashable {
        let file: String
        let hunk: Int?
    }

    private static func merged<Item>(
        _ existing: [Item],
        reporting batch: [Item],
        by key: (Item) -> AnnotationKey
    ) -> [Item] {
        var result = existing
        var positions = Dictionary(
            existing.enumerated().map { (key($0.element), $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        for item in batch {
            if let index = positions[key(item)] {
                result[index] = item
            } else {
                positions[key(item)] = result.count
                result.append(item)
            }
        }
        return result
    }

    // MARK: - Co se z uloženého záznamu smí ukázat

    /// Anotace, které platí pro **tuhle** hlavu (#524). `nil` = neplatí žádné.
    ///
    /// Je to tatáž brána jako `Policy.recheck(of:head:)` u kontroly nálezů a plyne z tvrdé
    /// podmínky č. 5: jak se hlava posune, anotace přestanou platit a nic se z nich nekreslí.
    /// **U anotací je to navíc tvrdší než u nálezů** — nález se dá ukázat jako `zastaralý`,
    /// kdežto anotace je vázaná na **pořadí hunku**, takže po pushi by neukazovala na starý kód,
    /// ale na **cizí**: stačí hunk přidaný nad ní a posunou se všechny.
    ///
    /// Neznámá hlava (`nil`) je **zákaz, ne povolení**: dokud se detail nenačetl, není proti čemu
    /// platnost posoudit, a věta nad hunkem, o které se neví, jestli platí, je horší než prázdno.
    static func annotations(of stored: StoredAnnotations?, head: String?) -> StoredAnnotations? {
        guard let stored, let head, !head.isEmpty, stored.headSha == head else { return nil }
        return stored
    }

    /// Anotace hunků jednoho souboru, **spárované přes index** (#524).
    ///
    /// Klíčem výsledku je **index do `file.hunks`, počítaný od nuly**, tedy to, čím se v diffu
    /// indexuje; nástroj hlásí pořadí od jedné, protože to je to, co je vidět v textu.
    ///
    /// **Páruje se přes index, ne přes text** (zadání #524). Úryvek kódu by se musel v diffu
    /// hledat, a řádek, který je v souboru dvakrát (`}` na konci metody), by anotaci posadil
    /// k cizímu hunku — tedy tichá chyba přesně toho druhu, kterou tenhle repozitář hlídá.
    ///
    /// **Index mimo rozsah se zahazuje.** Session popisuje diff, který si přečetla sama, takže
    /// dvanáctý hunk u souboru o třech znamená, že se spletla — a věta u posledního hunku „aby se
    /// neztratila“ by tvrdila něco o kódu, kterého se netýká.
    static func annotations(of stored: StoredAnnotations?, in file: FileDiff) -> [Int: HunkAnnotation] {
        guard let stored else { return [:] }
        var result: [Int: HunkAnnotation] = [:]
        for annotation in stored.hunks where matches(annotation.file, file) {
            let index = annotation.hunk - 1
            guard file.hunks.indices.contains(index) else { continue }
            result[index] = annotation
        }
        return result
    }

    /// Druh změny u jednoho souboru. `nil` = session ho neurčila, nebo anotace neplatí.
    static func changeKind(of stored: StoredAnnotations?, in file: FileDiff) -> FileChangeKind? {
        stored?.files.first { matches($0.file, file) }?.kind
    }

    /// Sedí cesta z anotace na tenhle soubor diffu?
    ///
    /// Zkouší se **nové i staré jméno**: u přejmenování si session může opsat kterékoli z nich
    /// a obojí je pravda o tomtéž souboru. Srovnává se **přesně**, ne podle přípony — soubor
    /// stejného jména v jiné složce je jiný soubor.
    private static func matches(_ path: String, _ file: FileDiff) -> Bool {
        path == file.newPath || path == file.oldPath
    }
}
