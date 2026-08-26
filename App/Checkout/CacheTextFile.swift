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
/// Kontroly jsou dvě a **žádná nenahrazuje druhou**:
///
/// - `CacheLayout.contains` rozbaluje symlinky v **rodiči**, protože zápis (a mazání) přes odkaz
///   v cestě sáhne na cíl, ne na odkaz;
/// - `CacheLayout.isSymbolicLink` odmítá odkaz na **samotném souboru**. `contains` ho nezachytí,
///   protože rozbaluje symlinky na obou stranách a cíl vyjde rovný cíli — a u čtení na tom záleží
///   nejvíc: vrácená cesta jde do promptu, takže by odkaz poslal session číst **mimo cache**.
enum CacheTextFile {
    /// Zapíše text a vrátí cestu, na kterou se má session podívat.
    ///
    /// Selhání **vyhazuje**, nespolkne se: běh sice pokračuje i bez souboru (materiál bez souboru
    /// je horší odpověď, ne rozbitá aplikace), ale rozhodnout o tom má volající, který to umí
    /// ukázat v okně. `try?` tady by znamenal, že session materiál nedostala a nikdo se to
    /// nedozví.
    @discardableResult
    static func write(_ text: String, to url: URL, in layout: CacheLayout) throws -> URL {
        let checked = try CacheEviction.insideCache(url, of: layout)
        // Změřeno u #120, že na zápisu **dnes** nestojí nic: `write(to:options: .atomic)` odkaz
        // nahradí souborem a cíl nechá být, kdežto tentýž zápis **bez** `.atomic` cíl přepíše.
        // Bezpečnost tedy visela na jednom příznaku u zápisu, což je slabší záruka než vyjmenovaná
        // kontrola.
        guard !layout.isSymbolicLink(checked) else {
            throw CheckoutError.cacheUnavailable(
                "Na cestě \(checked.path(percentEncoded: false)) leží symbolický odkaz."
            )
        }
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
        guard layout.contains(url),
              !layout.isSymbolicLink(url),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return nil }
        return url
    }
}
