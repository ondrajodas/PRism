import Foundation

/// Textový soubor, který si aplikace položí do své cache — zápis i čtení s **kontrolou hranice
/// na jednom místě** (#452).
///
/// Vzniklo to z toho, že takové soubory jsou od #452 dva: zadání pro reviewera (#120,
/// `ReviewIntentStore`) a materiál pro rozhovor (`AskContextStore`). Obojí je markdown vedle
/// pracovního stromu, obojí jde do promptu **cestou**, ne obsahem, a obojí si session otevře
/// `Read`em. Druhá kopie těch dvou kontrol by byla přesně ten vzor, na který si `CLAUDE.md`
/// stěžuje: *kontrola, která jinde v repu je, a tady chybí*.
///
/// Samotné pravidlo o hranici cache už tady **nebydlí** — je v `CacheFile`, protože ho vedle
/// tohohle typu potřebují i stores s JSONem (nález Copilota na #458). Tady zbylo to, co je vlastní
/// textovému souboru: atomický zápis a odpověď „je tam?“.
enum CacheTextFile {
    /// Zapíše text a vrátí cestu, na kterou se má session podívat.
    ///
    /// Selhání **vyhazuje**, nespolkne se: běh sice pokračuje i bez souboru (materiál bez souboru
    /// je horší odpověď, ne rozbitá aplikace), ale rozhodnout o tom má volající, který to umí
    /// ukázat v okně. `try?` tady by znamenal, že session materiál nedostala a nikdo se to
    /// nedozví.
    @discardableResult
    static func write(_ text: String, to url: URL, in layout: CacheLayout) throws -> URL {
        // Obě kontroly hranice cache, a odkaz na souboru mezi nimi: změřeno u #120, že na zápisu
        // **dnes** nestojí nic — `write(to:options: .atomic)` odkaz nahradí souborem a cíl nechá
        // být, kdežto tentýž zápis **bez** `.atomic` cíl přepíše. Bezpečnost tedy visela na jednom
        // příznaku u zápisu, což je slabší záruka než vyjmenovaná kontrola.
        let checked = try CacheFile.checked(url, in: layout)
        try FileManager.default.createDirectory(
            at: checked.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomicky, ze stejného důvodu jako u nálezů: půlka souboru se od celého nedá odlišit
        // ničím jiným než tím, že v něm chybí sekce — a to by vypadalo jako nedotažený materiál.
        try Data(text.utf8).write(to: checked, options: .atomic)
        return checked
    }

    /// Cesta k souboru, **pokud na disku je**. Nic nezakládá a nikdy nevyhazuje — volající se ptá
    /// „je tam?“, ne „vyrob mi ho“.
    static func existing(_ url: URL, in layout: CacheLayout) -> URL? {
        guard CacheFile.refusal(for: url, in: layout) == nil,
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return nil }
        return url
    }
}
